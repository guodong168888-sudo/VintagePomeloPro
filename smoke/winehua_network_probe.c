/*
 * WineHua network test (GUI).
 *
 * Runs DNS / raw TCP / WinHTTP HTTP / WinHTTP HTTPS / WinINet HTTPS checks and
 * shows the progress and result in a small window.  Results are also appended
 * to Z:\logs\wine_net_probe.txt so the app log export can pick them up.
 */

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

extern int wininet_https_test(char *out, size_t outlen);

enum
{
    IDC_EDIT = 1001,
    IDC_START = 1002,
    IDC_CLOSE = 1003
};

static HWND gEdit;
static HWND gStart;
static volatile LONG gRunning;

static void log_file(const char *line)
{
    fprintf(stderr, "%s\n", line);
    fflush(stderr);

    CreateDirectoryA("Z:\\logs", NULL);
    HANDLE h = CreateFileA("Z:\\logs\\wine_net_probe.txt",
                           GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE)
    {
        DWORD written;
        SetFilePointer(h, 0, NULL, FILE_END);
        WriteFile(h, line, (DWORD)strlen(line), &written, NULL);
        WriteFile(h, "\r\n", 2, &written, NULL);
        CloseHandle(h);
    }
}

static void append_line(const char *line)
{
    log_file(line);
    SendMessageA(gEdit, EM_SETSEL, (WPARAM)-1, (LPARAM)-1);
    SendMessageA(gEdit, EM_REPLACESEL, FALSE, (LPARAM)line);
    SendMessageA(gEdit, EM_REPLACESEL, FALSE, (LPARAM)"\r\n");
}

static void out_fmt(const char *fmt, ...)
{
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    append_line(line);
}

static int dns_probe(const char *host)
{
    struct addrinfo hints, *res = NULL;
    int ret;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    ret = getaddrinfo(host, "443", &hints, &res);
    if (ret != 0)
    {
        out_fmt("[DNS] %s FAILED (gai=%d)", host, ret);
        return 1;
    }

    out_fmt("[DNS] %s OK", host);
    for (struct addrinfo *p = res; p; p = p->ai_next)
    {
        char ip[64] = "";
        void *addr = NULL;
        if (p->ai_family == AF_INET)
            addr = &((struct sockaddr_in *)p->ai_addr)->sin_addr;
        else if (p->ai_family == AF_INET6)
            addr = &((struct sockaddr_in6 *)p->ai_addr)->sin6_addr;
        if (addr) inet_ntop(p->ai_family, addr, ip, sizeof(ip));
        out_fmt("        %s", ip);
    }
    freeaddrinfo(res);
    return 0;
}

static int tcp_probe(const char *host)
{
    struct addrinfo hints, *res = NULL;
    SOCKET s = INVALID_SOCKET;
    int ret, sockerr;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    ret = getaddrinfo(host, "443", &hints, &res);
    if (ret != 0)
    {
        out_fmt("[TCP] %s:443 FAILED getaddrinfo=%d", host, ret);
        return 1;
    }

    s = socket(res->ai_family, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET)
    {
        out_fmt("[TCP] socket() FAILED wsae=%d", WSAGetLastError());
        freeaddrinfo(res);
        return 1;
    }

    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);
    ret = connect(s, res->ai_addr, (int)res->ai_addrlen);
    sockerr = WSAGetLastError();
    if (ret == SOCKET_ERROR && sockerr != WSAEWOULDBLOCK &&
        sockerr != WSAEINPROGRESS && sockerr != WSAEINVAL)
    {
        out_fmt("[TCP] %s:443 connect FAILED wsae=%d", host, sockerr);
        closesocket(s);
        freeaddrinfo(res);
        return 1;
    }

    fd_set wf;
    struct timeval tv = { 10, 0 };
    FD_ZERO(&wf);
    FD_SET(s, &wf);
    ret = select(0, NULL, &wf, NULL, &tv);
    if (ret <= 0)
    {
        out_fmt("[TCP] %s:443 timeout/failed ret=%d wsae=%d", host, ret, WSAGetLastError());
        closesocket(s);
        freeaddrinfo(res);
        return 1;
    }

    int err = 0;
    int errlen = sizeof(err);
    getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &errlen);
    out_fmt("[TCP] %s:443 %s", host, err == 0 ? "OK" : "FAILED");
    closesocket(s);
    freeaddrinfo(res);
    return err == 0 ? 0 : 1;
}

static int tcp_probe6(const char *host)
{
    struct addrinfo hints, *res = NULL;
    SOCKET s = INVALID_SOCKET;
    int ret, sockerr;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET6;
    hints.ai_socktype = SOCK_STREAM;
    ret = getaddrinfo(host, "443", &hints, &res);
    if (ret != 0)
    {
        out_fmt("[TCP6] %s:443 getaddrinfo(AF_INET6) FAILED gai=%d", host, ret);
        return 1;
    }

    s = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET)
    {
        out_fmt("[TCP6] socket() FAILED wsae=%d", WSAGetLastError());
        freeaddrinfo(res);
        return 1;
    }

    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);
    ret = connect(s, res->ai_addr, (int)res->ai_addrlen);
    sockerr = WSAGetLastError();
    if (ret == SOCKET_ERROR && sockerr != WSAEWOULDBLOCK &&
        sockerr != WSAEINPROGRESS && sockerr != WSAEINVAL)
    {
        out_fmt("[TCP6] %s:443 connect FAILED wsae=%d", host, sockerr);
        closesocket(s);
        freeaddrinfo(res);
        return 1;
    }

    fd_set wf;
    struct timeval tv = { 10, 0 };
    FD_ZERO(&wf);
    FD_SET(s, &wf);
    ret = select(0, NULL, &wf, NULL, &tv);
    if (ret <= 0)
    {
        out_fmt("[TCP6] %s:443 timeout/failed ret=%d wsae=%d", host, ret, WSAGetLastError());
        closesocket(s);
        freeaddrinfo(res);
        return 1;
    }

    int err = 0;
    int errlen = sizeof(err);
    getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &errlen);
    out_fmt("[TCP6] %s:443 %s", host, err == 0 ? "OK" : "FAILED");
    closesocket(s);
    freeaddrinfo(res);
    return err == 0 ? 0 : 1;
}

static int winhttp_get(const char *host, const char *path, BOOL secure)
{
    HINTERNET session = NULL, conn = NULL, req = NULL;
    DWORD status = 0, status_size = sizeof(status), index = 0;
    char buf[2048];
    DWORD nread = 0, total = 0;
    int rc = 1;

    out_fmt("[WinHTTP] %s://%s%s starting...", secure ? "https" : "http", host, path);
    session = WinHttpOpen(L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                          L"AppleWebKit/537.36 (KHTML, like Gecko) "
                          L"Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
                          WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session)
    {
        out_fmt("[WinHTTP] open FAILED err=%lu", GetLastError());
        return 1;
    }
    WinHttpSetTimeouts(session, 10000, 10000, 40000, 40000);

    wchar_t whost[256], wpath[512];
    MultiByteToWideChar(CP_UTF8, 0, host, -1, whost, 256);
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 512);

    conn = WinHttpConnect(session, whost, secure ? INTERNET_DEFAULT_HTTPS_PORT
                                                : INTERNET_DEFAULT_HTTP_PORT, 0);
    if (!conn)
    {
        out_fmt("[WinHTTP] connect FAILED err=%lu", GetLastError());
        goto out;
    }
    req = WinHttpOpenRequest(conn, L"GET", wpath, NULL, WINHTTP_NO_REFERER,
                             WINHTTP_DEFAULT_ACCEPT_TYPES,
                             secure ? WINHTTP_FLAG_SECURE : 0);
    if (!req)
    {
        out_fmt("[WinHTTP] open request FAILED err=%lu", GetLastError());
        goto out;
    }
    if (!WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0))
    {
        out_fmt("[WinHTTP] send FAILED err=%lu", GetLastError());
        goto out;
    }
    if (!WinHttpReceiveResponse(req, NULL))
    {
        out_fmt("[WinHTTP] receive FAILED err=%lu", GetLastError());
        goto out;
    }
    WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size, &index);
    while (total < 4096 && WinHttpReadData(req, buf, sizeof(buf), &nread) && nread > 0)
        total += nread;
    out_fmt("[WinHTTP] %s://%s%s OK status=%lu read=%lu",
            secure ? "https" : "http", host, path, status, total);
    rc = 0;

out:
    if (req) WinHttpCloseHandle(req);
    if (conn) WinHttpCloseHandle(conn);
    if (session) WinHttpCloseHandle(session);
    return rc;
}

static DWORD WINAPI run_tests(LPVOID param)
{
    WSADATA wsa;
    int failures = 0;
    char wininet_line[512] = "";

    WSAStartup(MAKEWORD(2, 2), &wsa);
    append_line("========== Network test started ==========");

    failures += dns_probe("cdn.steamstatic.com");
    failures += dns_probe("www.baidu.com");
    failures += dns_probe("msedge.api.cdp.microsoft.com");
    failures += tcp_probe("cdn.steamstatic.com");
    failures += tcp_probe6("msedge.api.cdp.microsoft.com");

    /* Run the Steam CDN HTTPS first to measure the cold-start TLS handshake,
     * which is the request order a real updater uses. */
    append_line("[Note] Testing Steam CDN HTTPS first (cold TLS handshake)...");
    DWORD started = GetTickCount();
    failures += winhttp_get("cdn.steamstatic.com", "/client/steam_client_win32", TRUE);
    out_fmt("[WinHTTP] Steam CDN attempt took %lu ms", GetTickCount() - started);

    failures += winhttp_get("www.baidu.com", "/", FALSE);
    failures += winhttp_get("www.baidu.com", "/", TRUE);
    failures += winhttp_get("msedge.api.cdp.microsoft.com", "/", TRUE);
    failures += wininet_https_test(wininet_line, sizeof(wininet_line));
    if (wininet_line[0]) append_line(wininet_line);

    out_fmt("========== Test finished: %d failed ==========", failures);
    WSACleanup();
    InterlockedExchange(&gRunning, 0);
    EnableWindow(gStart, TRUE);
    return 0;
}

static void start_tests(void)
{
    if (InterlockedCompareExchange(&gRunning, 1, 0) != 0) return;
    EnableWindow(gStart, FALSE);
    SendMessageA(gEdit, EM_SETSEL, 0, -1);
    SendMessageA(gEdit, EM_REPLACESEL, FALSE, (LPARAM)"");
    HANDLE thread = CreateThread(NULL, 0, run_tests, NULL, 0, NULL);
    if (thread) CloseHandle(thread);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg)
    {
    case WM_CREATE:
    {
        HFONT font = CreateFontA(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                 DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                 CLEARTYPE_QUALITY, DEFAULT_PITCH, "MS Shell Dlg");
        gEdit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL |
                                ES_READONLY | WS_VSCROLL,
                                12, 12, 500, 300, hwnd, (HMENU)(INT_PTR)IDC_EDIT,
                                GetModuleHandleA(NULL), NULL);
        gStart = CreateWindowExA(0, "BUTTON", "Run Test",
                                 WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
                                 12, 322, 110, 36, hwnd, (HMENU)(INT_PTR)IDC_START,
                                 GetModuleHandleA(NULL), NULL);
        HWND close = CreateWindowExA(0, "BUTTON", "Close",
                                     WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                                     130, 322, 110, 36, hwnd, (HMENU)(INT_PTR)IDC_CLOSE,
                                     GetModuleHandleA(NULL), NULL);
        if (font)
        {
            SendMessageA(gEdit, WM_SETFONT, (WPARAM)font, TRUE);
            SendMessageA(gStart, WM_SETFONT, (WPARAM)font, TRUE);
            SendMessageA(close, WM_SETFONT, (WPARAM)font, TRUE);
        }
        PostMessageA(hwnd, WM_COMMAND, IDC_START, 0);
        return 0;
    }
    case WM_COMMAND:
        switch (LOWORD(wparam))
        {
        case IDC_START:
            start_tests();
            return 0;
        case IDC_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        }
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wparam, lparam);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmdline, int show)
{
    (void)prev;
    (void)cmdline;
    (void)show;

    WNDCLASSA cls;
    memset(&cls, 0, sizeof(cls));
    cls.lpfnWndProc = WndProc;
    cls.hInstance = instance;
    cls.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    cls.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    cls.lpszClassName = "WineHuaNetworkTest";
    RegisterClassA(&cls);

    HWND hwnd = CreateWindowExA(0, cls.lpszClassName, "WineHua Network Test",
                                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                                CW_USEDEFAULT, CW_USEDEFAULT, 540, 410,
                                NULL, NULL, instance, NULL);
    if (!hwnd) return 1;
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    MSG message;
    while (GetMessageA(&message, NULL, 0, 0) > 0)
    {
        TranslateMessage(&message);
        DispatchMessageA(&message);
    }
    return (int)message.wParam;
}
