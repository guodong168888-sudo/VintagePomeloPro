/*
 * WinINet part of the network test.  Kept in a separate translation unit
 * because MinGW's winhttp.h and wininet.h cannot be included together
 * (conflicting URL_COMPONENTS typedefs).
 */

#include <windows.h>
#include <wininet.h>
#include <stdio.h>

int wininet_https_test(char *out, size_t outlen)
{
    static const char url[] = "https://www.baidu.com/";
    HINTERNET session = NULL, hurl = NULL;
    char buf[2048];
    DWORD nread = 0, total = 0, status = 0, status_size = sizeof(status), index = 0;
    DWORD timeout = 8000;
    int rc = 1;

    if (!out || outlen == 0) return 1;
    out[0] = 0;

    session = InternetOpenA("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                            "AppleWebKit/537.36 (KHTML, like Gecko) "
                            "Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
                            INTERNET_OPEN_TYPE_PRECONFIG,
                            NULL, NULL, 0);
    if (!session)
    {
        _snprintf(out, outlen, "[WinINet] open FAILED err=%lu", GetLastError());
        return 1;
    }
    InternetSetOptionA(session, INTERNET_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
    InternetSetOptionA(session, INTERNET_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));

    hurl = InternetOpenUrlA(session, url, NULL, 0,
                            INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE, 0);
    if (!hurl)
    {
        _snprintf(out, outlen, "[WinINet] %s FAILED err=%lu", url, GetLastError());
        goto done;
    }
    if (HttpQueryInfoA(hurl, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER,
                       &status, &status_size, &index))
        _snprintf(out, outlen, "[WinINet] %s status=%lu", url, status);
    while (total < 4096 && InternetReadFile(hurl, buf, sizeof(buf), &nread) && nread > 0)
        total += nread;
    if (out[0])
    {
        size_t len = strlen(out);
        _snprintf(out + len, outlen - len, " read=%lu", total);
    }
    rc = 0;

done:
    if (hurl) InternetCloseHandle(hurl);
    if (session) InternetCloseHandle(session);
    return rc;
}
