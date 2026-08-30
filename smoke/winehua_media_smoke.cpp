#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dshow.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cwchar>

namespace {

constexpr DWORD kDefaultTimeoutMs = 30000;
constexpr DWORD kStatusIntervalMs = 500;

void LogHresult(const wchar_t* action, HRESULT hr)
{
    std::fwprintf(stderr, L"MEDIA_SMOKE action=%ls hr=0x%08lx\n",
                  action, static_cast<unsigned long>(hr));
    std::fflush(stderr);
}

uint64_t ReferenceTimeToMilliseconds(LONGLONG value)
{
    return value > 0 ? static_cast<uint64_t>(value / 10000) : 0;
}

void PumpWindowMessages()
{
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    if (argc < 2 || !argv[1][0]) {
        std::fwprintf(stderr,
                      L"MEDIA_SMOKE result=FAIL reason=usage "
                      L"usage=winehua_media_smoke.exe_media_path_[timeout_ms]\n");
        return 2;
    }

    DWORD timeoutMs = kDefaultTimeoutMs;
    if (argc >= 3) {
        wchar_t* end = nullptr;
        const unsigned long parsed = std::wcstoul(argv[2], &end, 10);
        if (end && !*end && parsed >= 1000 && parsed <= 300000)
            timeoutMs = static_cast<DWORD>(parsed);
    }

    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) {
        LogHresult(L"CoInitializeEx", hr);
        return 3;
    }

    IGraphBuilder* graph = nullptr;
    IMediaControl* control = nullptr;
    IMediaEvent* events = nullptr;
    IMediaSeeking* seeking = nullptr;
    IVideoWindow* videoWindow = nullptr;
    int exitCode = 1;
    LONGLONG duration = 0;
    ULONGLONG startedAt = 0;
    ULONGLONG nextStatusAt = 0;
    bool completed = false;
    long completionCode = 0;

    hr = CoCreateInstance(CLSID_FilterGraph, nullptr, CLSCTX_INPROC_SERVER,
                          IID_IGraphBuilder,
                          reinterpret_cast<void**>(&graph));
    if (FAILED(hr)) {
        LogHresult(L"CoCreateInstance_FilterGraph", hr);
        goto cleanup;
    }

    hr = graph->QueryInterface(IID_IMediaControl,
                               reinterpret_cast<void**>(&control));
    if (FAILED(hr)) {
        LogHresult(L"QueryInterface_IMediaControl", hr);
        goto cleanup;
    }
    hr = graph->QueryInterface(IID_IMediaEvent,
                               reinterpret_cast<void**>(&events));
    if (FAILED(hr)) {
        LogHresult(L"QueryInterface_IMediaEvent", hr);
        goto cleanup;
    }
    graph->QueryInterface(IID_IMediaSeeking,
                          reinterpret_cast<void**>(&seeking));
    graph->QueryInterface(IID_IVideoWindow,
                          reinterpret_cast<void**>(&videoWindow));

    std::fwprintf(stderr,
                  L"MEDIA_SMOKE action=RenderFile path=%ls timeout_ms=%lu\n",
                  argv[1], static_cast<unsigned long>(timeoutMs));
    std::fflush(stderr);
    hr = graph->RenderFile(argv[1], nullptr);
    if (FAILED(hr)) {
        LogHresult(L"RenderFile", hr);
        goto cleanup;
    }

    if (seeking && SUCCEEDED(seeking->GetDuration(&duration))) {
        std::fprintf(stderr, "MEDIA_SMOKE duration_ms=%llu\n",
                     static_cast<unsigned long long>(
                         ReferenceTimeToMilliseconds(duration)));
    }
    if (videoWindow) {
        videoWindow->put_AutoShow(OATRUE);
        videoWindow->put_Visible(OATRUE);
    }

    hr = control->Run();
    if (FAILED(hr)) {
        LogHresult(L"Run", hr);
        goto cleanup;
    }

    startedAt = GetTickCount64();
    nextStatusAt = startedAt;
    while (GetTickCount64() - startedAt < timeoutMs) {
        PumpWindowMessages();

        long eventCode = 0;
        LONG_PTR parameter1 = 0;
        LONG_PTR parameter2 = 0;
        while (events->GetEvent(&eventCode, &parameter1, &parameter2, 0) == S_OK) {
            events->FreeEventParams(eventCode, parameter1, parameter2);
            if (eventCode == EC_COMPLETE || eventCode == EC_ERRORABORT ||
                eventCode == EC_USERABORT) {
                completed = true;
                completionCode = eventCode;
                break;
            }
        }
        if (completed) break;

        const ULONGLONG now = GetTickCount64();
        if (now >= nextStatusAt) {
            LONGLONG position = 0;
            const HRESULT positionHr = seeking ?
                seeking->GetCurrentPosition(&position) : E_NOINTERFACE;
            std::fprintf(stderr,
                         "MEDIA_SMOKE progress wall_ms=%llu pts_ms=%llu "
                         "position_hr=0x%08lx\n",
                         static_cast<unsigned long long>(now - startedAt),
                         static_cast<unsigned long long>(
                             ReferenceTimeToMilliseconds(position)),
                         static_cast<unsigned long>(positionHr));
            std::fflush(stderr);
            nextStatusAt = now + kStatusIntervalMs;
        }
        Sleep(10);
    }

    control->Stop();
    if (completed && completionCode == EC_COMPLETE) {
        LONGLONG finalPosition = 0;
        if (seeking) seeking->GetCurrentPosition(&finalPosition);
        std::fprintf(stderr,
                     "MEDIA_SMOKE result=PASS event=EC_COMPLETE pts_ms=%llu\n",
                     static_cast<unsigned long long>(
                         ReferenceTimeToMilliseconds(finalPosition)));
        exitCode = 0;
    } else if (completed) {
        std::fprintf(stderr,
                     "MEDIA_SMOKE result=FAIL reason=media_event event=0x%lx\n",
                     completionCode);
        exitCode = 4;
    } else {
        LONGLONG finalPosition = 0;
        if (seeking) seeking->GetCurrentPosition(&finalPosition);
        std::fprintf(stderr,
                     "MEDIA_SMOKE result=FAIL reason=timeout pts_ms=%llu\n",
                     static_cast<unsigned long long>(
                         ReferenceTimeToMilliseconds(finalPosition)));
        exitCode = 5;
    }

cleanup:
    if (videoWindow) {
        videoWindow->put_Visible(OAFALSE);
        videoWindow->Release();
    }
    if (seeking) seeking->Release();
    if (events) events->Release();
    if (control) control->Release();
    if (graph) graph->Release();
    CoUninitialize();
    std::fflush(stderr);
    return exitCode;
}
