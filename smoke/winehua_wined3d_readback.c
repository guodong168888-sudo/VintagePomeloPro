/* Diagnostic only. Relink cached WineD3D objects without editing the submodule.
 * Wrapping only cross-object references is intentional; no negative conclusion
 * can be drawn about same-object calls from the absence of a load event.
 */
#include "wined3d_private.h"
#include <stdio.h>
#include <string.h>

#define WRAP(name) extern __typeof__(name) __real_##name; extern __typeof__(name) __wrap_##name
static LONG map_count, load_count, copy_count, blit_count, present_count;

struct resource_snapshot {
    const void *identity;
    unsigned int width, height, format, usage, access, bind, locations, map_binding;
    BOOL has_box;
    struct wined3d_box box;
};
static struct resource_snapshot snapshot(const struct wined3d_resource *r, unsigned int sub)
{
    struct resource_snapshot s = {0};
    if (!r) return s;
    s.identity = r; s.width = r->width; s.height = r->height;
    s.format = r->format->id; s.usage = r->usage; s.access = r->access;
    s.bind = r->bind_flags; s.map_binding = r->map_binding;
    if (r->type == WINED3D_RTYPE_TEXTURE_2D) {
        const struct wined3d_texture *t = CONTAINING_RECORD(r, struct wined3d_texture, resource);
        if (sub < t->level_count * t->layer_count) s.locations = t->sub_resources[sub].locations;
    }
    return s;
}
static BOOL large_texture(const struct wined3d_resource *r)
{
    return r && r->type == WINED3D_RTYPE_TEXTURE_2D && r->width >= 640 && r->height >= 480;
}
static ULONG sample(LONG *counter)
{
    ULONG n = (ULONG)InterlockedIncrement(counter);
    /* Bound logging for accidental long sessions. Counts are per event/process,
     * not per frame/texture; timings below are samples, not aggregate means. */
    return n && n <= 8192 && (n <= 6 || n % 120 == 0) ? n : 0;
}
static void append_address(char *line, size_t cap, const char *label, void *address)
{
    HMODULE module = NULL;
    char path[MAX_PATH] = {0};
    const char *name = "unmapped", *part;
    ULONG_PTR rva = 0;
    size_t length = strlen(line);
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (const char *)address, &module)) {
        if (GetModuleFileNameA(module, path, sizeof(path) - 1)) {
            part = strrchr(path, '\\');
            name = part ? part + 1 : path;
        } else name = "mapped-no-name";
        rva = (ULONG_PTR)address - (ULONG_PTR)module;
    }
    if (length < cap)
        snprintf(line + length, cap - length, " %s=%s+0x%Ix", label, name, (SIZE_T)rva);
}
static LARGE_INTEGER stamp(void)
{
    LARGE_INTEGER value = {0};
    QueryPerformanceCounter(&value);
    return value;
}
static void report(const char *kind, ULONG n, const struct resource_snapshot *s,
        const struct resource_snapshot *peer, unsigned int sub, unsigned int flags,
        unsigned int location, LONG result, LARGE_INTEGER start, void *caller)
{
    DWORD saved_error = GetLastError(), written;
    LARGE_INTEGER end = stamp(), frequency = {0};
    char line[2048], label[16];
    void *frames[10];
    USHORT count, i;
    HANDLE file;
    double elapsed = -1.0;
    if (QueryPerformanceFrequency(&frequency) && frequency.QuadPart > 0 &&
            start.QuadPart && end.QuadPart >= start.QuadPart)
        elapsed = (end.QuadPart - start.QuadPart) * 1000000.0 / frequency.QuadPart;
    snprintf(line, sizeof(line),
        "[WINED3D-READBACK] v=2 bits=%u pid=%lu tid=%lu kind=%s sample=%lu "
        "resource=%p size=%ux%u format=%u usage=0x%x access=0x%x bind=0x%x "
        "before=0x%x map_binding=0x%x sub=%u flags=0x%x destination=0x%x "
        "box_valid=%d box=%u,%u,%u,%u,%u,%u "
        "peer=%p peer_size=%ux%u peer_format=%u result=0x%lx sampled_wall_us=%.0f",
        (unsigned int)(sizeof(void *) * 8), GetCurrentProcessId(), GetCurrentThreadId(), kind, n,
        s->identity, s->width, s->height, s->format, s->usage, s->access, s->bind,
        s->locations, s->map_binding, sub, flags, location, s->has_box,
        s->box.left, s->box.top, s->box.right, s->box.bottom, s->box.front, s->box.back, peer->identity,
        peer->width, peer->height, peer->format, result, elapsed);
    append_address(line, sizeof(line), "caller", caller);
    count = RtlCaptureStackBackTrace(1, ARRAY_SIZE(frames), frames, NULL);
    for (i = 0; i < count; ++i) {
        snprintf(label, sizeof(label), "stack%u", i);
        append_address(line, sizeof(line), label, frames[i]);
    }
    strncat(line, "\r\n", sizeof(line) - strlen(line) - 1);
    file = CreateFileW(L"C:\\windows\\temp\\winehua_wined3d_readback.log", FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_ALWAYS, 0, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        WriteFile(file, line, (DWORD)strlen(line), &written, NULL);
        CloseHandle(file);
    }
    SetLastError(saved_error);
}

WRAP(wined3d_device_context_emit_map);
HRESULT __wrap_wined3d_device_context_emit_map(struct wined3d_device_context *context,
        struct wined3d_resource *resource, unsigned int sub, struct wined3d_map_desc *desc,
        const struct wined3d_box *box, unsigned int flags)
{
    ULONG n = large_texture(resource) ? sample(&map_count) : 0;
    struct resource_snapshot s = n ? snapshot(resource, sub) : (struct resource_snapshot){0}, peer = {0};
    if (n && box) { s.has_box = TRUE; s.box = *box; }
    LARGE_INTEGER start = n ? stamp() : (LARGE_INTEGER){0};
    HRESULT result = __real_wined3d_device_context_emit_map(context, resource, sub, desc, box, flags);
    if (n) report("map", n, &s, &peer, sub, flags, 0, result, start, __builtin_return_address(0));
    return result;
}
WRAP(wined3d_texture_load_location);
BOOL __wrap_wined3d_texture_load_location(struct wined3d_texture *texture,
        unsigned int sub, struct wined3d_context *context, uint32_t location)
{
    BOOL cpu = location & (WINED3D_LOCATION_SYSMEM | WINED3D_LOCATION_BUFFER);
    ULONG n = cpu && large_texture(&texture->resource) &&
            !(texture->sub_resources[sub].locations & location) ? sample(&load_count) : 0;
    struct resource_snapshot s = n ? snapshot(&texture->resource, sub) : (struct resource_snapshot){0}, peer = {0};
    LARGE_INTEGER start = n ? stamp() : (LARGE_INTEGER){0};
    BOOL result = __real_wined3d_texture_load_location(texture, sub, context, location);
    if (n) report("load_cpu", n, &s, &peer, sub, 0, location, result, start, __builtin_return_address(0));
    return result;
}
WRAP(wined3d_texture_download_from_texture);
void __wrap_wined3d_texture_download_from_texture(struct wined3d_texture *dst, unsigned int dst_sub,
        struct wined3d_texture *src, unsigned int src_sub)
{
    ULONG n = large_texture(&src->resource) ? sample(&copy_count) : 0;
    struct resource_snapshot s = n ? snapshot(&src->resource, src_sub) : (struct resource_snapshot){0};
    struct resource_snapshot peer = n ? snapshot(&dst->resource, dst_sub) : (struct resource_snapshot){0};
    LARGE_INTEGER start = n ? stamp() : (LARGE_INTEGER){0};
    __real_wined3d_texture_download_from_texture(dst, dst_sub, src, src_sub);
    if (n) report("download_copy", n, &s, &peer, src_sub, 0, 0, 0, start, __builtin_return_address(0));
}
WRAP(wined3d_device_context_emit_blt_sub_resource);
void __wrap_wined3d_device_context_emit_blt_sub_resource(struct wined3d_device_context *context,
        struct wined3d_resource *dst, unsigned int dst_sub, const struct wined3d_box *dst_box,
        struct wined3d_resource *src, unsigned int src_sub, const struct wined3d_box *src_box,
        unsigned int flags, const struct wined3d_blt_fx *fx, enum wined3d_texture_filter_type filter)
{
    ULONG n = large_texture(src) ? sample(&blit_count) : 0;
    struct resource_snapshot s = n ? snapshot(src, src_sub) : (struct resource_snapshot){0};
    struct resource_snapshot peer = n ? snapshot(dst, dst_sub) : (struct resource_snapshot){0};
    LARGE_INTEGER start = n ? stamp() : (LARGE_INTEGER){0};
    __real_wined3d_device_context_emit_blt_sub_resource(context, dst, dst_sub, dst_box, src, src_sub, src_box, flags, fx, filter);
    if (n) report("blit_enqueue", n, &s, &peer, src_sub, flags, 0, 0, start, __builtin_return_address(0));
}
WRAP(wined3d_cs_emit_present);
void __wrap_wined3d_cs_emit_present(struct wined3d_cs *cs, struct wined3d_swapchain *swapchain,
        const RECT *src_rect, const RECT *dst_rect, HWND window, unsigned int interval, uint32_t flags)
{
    ULONG n = sample(&present_count);
    struct resource_snapshot s = {0}, peer = {0};
    LARGE_INTEGER start = {0};
    if (n) {
        if (swapchain->state.desc.backbuffer_count)
            s = snapshot(&swapchain->back_buffers[0]->resource, 0);
        peer = snapshot(&swapchain->front_buffer->resource, 0);
        start = stamp();
    }
    __real_wined3d_cs_emit_present(cs, swapchain, src_rect, dst_rect, window, interval, flags);
    if (n) report("present_enqueue", n, &s, &peer, 0, flags, interval, 0, start, __builtin_return_address(0));
}
