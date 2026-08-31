/* Read-only guest-side attribution: no injection, suspension, tuning or graphics calls.
 * Run through the normal WineHua application launcher, never a shell Wine instance.
 * Thread start addresses identify roles, NOT sampled execution hotspots.
 */
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <io.h>
#include <fcntl.h>

#define MAX_MODULES 512
#define MAX_THREADS 512
typedef LONG (WINAPI *QueryThreadFn)(HANDLE, ULONG, void *, ULONG, ULONG *);
typedef HRESULT (WINAPI *ThreadDescriptionFn)(HANDLE, PWSTR *);
typedef struct { uintptr_t base; DWORD size; char name[MAX_MODULE_NAME32 + 1]; } Module;
typedef struct { DWORD id; HANDLE handle; uint64_t cpu; LARGE_INTEGER sampled_at; BOOL valid; } Thread;
static Module modules[MAX_MODULES];
static unsigned module_count;
static FILE *out;

static DWORD WINAPI watchdog(void *unused)
{
    (void)unused;
    Sleep(10000);
    /* Only this diagnostic process. Never suspend or terminate the target. */
    TerminateProcess(GetCurrentProcess(), 6);
    return 0;
}

static void json_string(const char *s)
{
    fputc('"', out);
    for (; *s; ++s) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') fprintf(out, "\\%c", c);
        else if (c < 32) fprintf(out, "\\u%04x", c);
        else fputc(c, out);
    }
    fputc('"', out);
}

static void error_record(const char *operation, DWORD code)
{
    fputs("{\"type\":\"error\",\"operation\":", out);
    json_string(operation);
    fprintf(out, ",\"code\":%lu}\n", (unsigned long)code);
}

static const Module *find_module(uintptr_t address)
{
    unsigned i;
    for (i = 0; i < module_count; ++i)
        if (address >= modules[i].base && address - modules[i].base < modules[i].size)
            return &modules[i];
    return NULL;
}

static uint64_t filetime_value(FILETIME t)
{
    return ((uint64_t)t.dwHighDateTime << 32) | t.dwLowDateTime;
}

static BOOL thread_cpu(HANDLE h, uint64_t *value)
{
    FILETIME create, exit, kernel, user;
    if (!GetThreadTimes(h, &create, &exit, &kernel, &user)) return FALSE;
    *value = filetime_value(kernel) + filetime_value(user);
    return TRUE;
}

static int inspect_modules(DWORD pid)
{
    fputs("{\"type\":\"stage\",\"name\":\"module_snapshot\"}\n", out);
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    MODULEENTRY32 entry;
    if (snapshot == INVALID_HANDLE_VALUE) { error_record("module_snapshot", GetLastError()); return 1; }
    memset(&entry, 0, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (!Module32First(snapshot, &entry)) {
        error_record("module_first", GetLastError());
        CloseHandle(snapshot);
        return 1;
    }
    do {
        if (module_count == MAX_MODULES) {
            error_record("module_limit", MAX_MODULES);
            CloseHandle(snapshot);
            return 1;
        }
        Module *m = &modules[module_count++];
        m->base = (uintptr_t)entry.modBaseAddr;
        m->size = entry.modBaseSize;
        snprintf(m->name, sizeof(m->name), "%s", entry.szModule);
        fputs("{\"type\":\"module\",\"name\":", out);
        json_string(m->name);
        fprintf(out, ",\"base\":\"0x%llx\",\"size\":%lu}\n",
                (unsigned long long)m->base, (unsigned long)m->size);
    } while (Module32Next(snapshot, &entry));
    DWORD last = GetLastError();
    CloseHandle(snapshot);
    if (last != ERROR_NO_MORE_FILES) { error_record("module_next", last); return 1; }
    return 0;
}

static int inspect_threads(DWORD pid, unsigned duration_ms)
{
    fputs("{\"type\":\"stage\",\"name\":\"thread_snapshot\"}\n", out);
    Thread threads[MAX_THREADS];
    unsigned count = 0, i;
    int result = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    THREADENTRY32 entry;
    QueryThreadFn query = (QueryThreadFn)(void *)GetProcAddress(GetModuleHandleA("ntdll.dll"), "NtQueryInformationThread");
    ThreadDescriptionFn description = (ThreadDescriptionFn)(void *)GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetThreadDescription");
    LARGE_INTEGER end, frequency;
    if (snapshot == INVALID_HANDLE_VALUE) { error_record("thread_snapshot", GetLastError()); return 1; }
    memset(&entry, 0, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (!Thread32First(snapshot, &entry)) {
        error_record("thread_first", GetLastError());
        CloseHandle(snapshot);
        return 1;
    }
    do {
        if (entry.th32OwnerProcessID != pid) continue;
        if (count == MAX_THREADS) { error_record("thread_limit", MAX_THREADS); result = 1; break; }
        HANDLE h = OpenThread(THREAD_QUERY_INFORMATION, FALSE, entry.th32ThreadID);
        if (!h) { error_record("thread_open", GetLastError()); result = 1; continue; }
        threads[count].id = entry.th32ThreadID;
        threads[count].handle = h;
        threads[count].cpu = 0;
        threads[count].valid = FALSE;
        ++count;
    } while (Thread32Next(snapshot, &entry));
    if (!result && GetLastError() != ERROR_NO_MORE_FILES) { error_record("thread_next", GetLastError()); result = 1; }
    CloseHandle(snapshot);
    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
        error_record("clock", GetLastError());
        for (i = 0; i < count; ++i) CloseHandle(threads[i].handle);
        return 1;
    }
    fputs("{\"type\":\"stage\",\"name\":\"thread_times\"}\n", out);
    for (i = 0; i < count; ++i) {
        threads[i].valid = thread_cpu(threads[i].handle, &threads[i].cpu);
        threads[i].valid = QueryPerformanceCounter(&threads[i].sampled_at) && threads[i].valid;
    }
    Sleep(duration_ms);
    for (i = 0; i < count; ++i) {
        Thread *t = &threads[i];
        uintptr_t address = 0;
        PWSTR wide = NULL;
        char name[256] = "";
        uint64_t after = 0;
        BOOL valid = thread_cpu(t->handle, &after) && t->valid && after >= t->cpu;
        BOOL clock_valid = QueryPerformanceCounter(&end);
        double wall_ms = clock_valid && t->valid ?
            (double)(end.QuadPart - t->sampled_at.QuadPart) * 1000.0 / frequency.QuadPart : 0.0;
        double cpu_ms = valid ? (after - t->cpu) / 10000.0 : 0.0;
        valid = valid && wall_ms > 0.0 && cpu_ms <= wall_ms + 20.0;
        LONG query_status = query ? query(t->handle, 9, &address, sizeof(address), NULL) : (LONG)0xc0000002;
        if (description && SUCCEEDED(description(t->handle, &wide)) && wide) {
            WideCharToMultiByte(CP_UTF8, 0, wide, -1, name, sizeof(name), NULL, NULL);
            name[sizeof(name) - 1] = 0;
            LocalFree(wide);
        }
        const Module *m = query_status >= 0 ? find_module(address) : NULL;
        fprintf(out, "{\"type\":\"thread\",\"guestTid\":%lu,\"description\":", (unsigned long)t->id);
        json_string(name);
        fprintf(out, ",\"cpuValid\":%s,\"cpuMs\":%.3f,\"wallMs\":%.3f,\"cpuPercent\":%.2f,\"startQueryStatus\":%ld,\"startAddress\":\"0x%llx\",\"startModule\":",
                valid ? "true" : "false", cpu_ms, wall_ms, valid ? cpu_ms / wall_ms * 100.0 : 0.0,
                (long)query_status, (unsigned long long)address);
        json_string(m ? m->name : "");
        fprintf(out, ",\"startRva\":\"0x%llx\"}\n", (unsigned long long)(m ? address - m->base : 0));
        CloseHandle(t->handle);
    }
    fprintf(out, "{\"type\":\"thread_summary\",\"count\":%u,\"startAddressIsHotspot\":false,\"threadSetMayChange\":true}\n", count);
    return result;
}

int main(int argc, char **argv)
{
    const char *process = NULL, *output = NULL;
    unsigned duration_ms = 1000;
    int i, matches = 0, result = 0;
    DWORD pid = 0;
    for (i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--process") && i + 1 < argc) process = argv[++i];
        else if (!strcmp(argv[i], "--output") && i + 1 < argc) output = argv[++i];
        else if (!strcmp(argv[i], "--duration-ms") && i + 1 < argc) {
            char *end;
            unsigned long value = strtoul(argv[++i], &end, 10);
            if (*end || value < 100 || value > 5000) return 2;
            duration_ms = (unsigned)value;
        } else if (!strcmp(argv[i], "--list")) { /* process snapshot only */ }
        else return 2;
    }
    if (!output) return 2;
    /* MSVCRT does not consistently implement C11 fopen("wx"). */
    HANDLE file = CreateFileA(output, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 3;
    int fd = _open_osfhandle((intptr_t)file, _O_WRONLY | _O_BINARY);
    if (fd < 0) { CloseHandle(file); return 3; }
    out = _fdopen(fd, "wb");
    if (!out) { _close(fd); return 3; }
    setvbuf(out, NULL, _IONBF, 0);
    HANDLE guard = CreateThread(NULL, 0, watchdog, NULL, 0, NULL);
    if (!guard) { error_record("watchdog", GetLastError()); fclose(out); return 6; }
    CloseHandle(guard);
    fprintf(out, "{\"type\":\"capture\",\"version\":1,\"readerBits\":%u,\"selfPid\":%lu,\"durationMs\":%u}\n",
            (unsigned)(sizeof(void *) * 8), (unsigned long)GetCurrentProcessId(), duration_ms);
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32 entry;
    memset(&entry, 0, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (snapshot == INVALID_HANDLE_VALUE || !Process32First(snapshot, &entry)) {
        error_record("process_snapshot", GetLastError());
        if (snapshot != INVALID_HANDLE_VALUE) CloseHandle(snapshot);
        fclose(out);
        return 4;
    }
    do {
        if (process && _stricmp(process, entry.szExeFile)) continue;
        fprintf(out, "{\"type\":\"process\",\"guestPid\":%lu,\"name\":", (unsigned long)entry.th32ProcessID);
        json_string(entry.szExeFile);
        fprintf(out, ",\"threads\":%lu}\n", (unsigned long)entry.cntThreads);
        pid = entry.th32ProcessID;
        ++matches;
    } while (Process32Next(snapshot, &entry));
    DWORD last = GetLastError();
    CloseHandle(snapshot);
    if (last != ERROR_NO_MORE_FILES) { error_record("process_next", last); result = 1; }
    if (process && !result) {
        if (matches != 1) { error_record("unique_process_required", matches); result = 1; }
        else { result = inspect_modules(pid); result |= inspect_threads(pid, duration_ms); }
    }
    fprintf(out, "{\"type\":\"complete\",\"status\":%d}\n", result);
    if (fclose(out)) return 5;
    return result;
}
