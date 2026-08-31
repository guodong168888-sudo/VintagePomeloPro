# Performance HUD

The independent **System settings → 性能监控** section controls a compact,
single-line 10sp strip at the top of the game (not a vertical status panel).
The existing `showFpsHud` preference remains the master switch. Old installations
keep their previous on/off choice and FPS-only content; new metric choices are
stored in `performanceHud`. Disabling the master retains the selections.
All-off hides the overlay and stops sampling. No graphics profile, guest
environment, WHIP field or `batchMappedFlush` policy changes are involved.

## Metric meanings

- **FPS**: existing Host compositor displayed-frame counter, refreshed every
  500 ms; not the game's internal FPS or a GPU completion measurement.
- **Application CPU**: sum of readable same-UID processes, including Wine/NCP
  children and forked grandchildren. 100% means one logical CPU, so 200% is valid.
  PID plus start-time identity prevents reused PIDs producing spikes; exited or
  new processes can make a sample a lower bound, explicitly marked `≥`.
- **System CPU**: aggregate busy percentage across logical CPUs, 0–100%.
  `/proc/stat` idle plus iowait are idle; guest ticks are not counted twice.
  If the app sandbox denies this node, public HiDebug CPU usage is requested
  on the same worker (its system-managed averaging window can differ).
  Its ambiguous zero/error result is displayed as unavailable, not 0%.
- **GPU utilization / chip temperature**: currently not offered as switches
  or placeholder labels; no private/system-only dump API, privileged
  shell command or guessed GPU counter is invoked. This is an implementation
  limit, not a claim that every device lacks sensors. A permitted, documented
  driver adapter remains future work.
- **Battery temperature**: public `batteryInfo.batteryTemperature` in 0.1°C,
  converted to °C. It is not chip temperature.
- **Thermal level**: public `thermal.getLevel()` (0–7), not measured °C and not
  proof that frequency throttling has occurred.

## Sampling and lifecycle

Desktop, managed Wine windows and popups share a sampler. Only selected metrics
are read. CPU procfs IO runs in NAPI async work, capped at 4,096 process entries,
256 owned processes and a 50 ms scan budget; no command lines or environments
are read. Telemetry is sampled every two seconds, never per rendered frame.
Unsupported GPU/chip metrics have no recurring probe. FPS-only mode does not
read procfs, battery or thermal APIs.

The last subscriber leaving, the master/all-metrics being disabled, and
application background callbacks clear the timer and CPU baseline. Stale async
completions are discarded using a generation number. Foregrounding establishes
a fresh CPU baseline. HUD text does not accept pointer hits, and floating
thumbnails retain their existing suppression.

First CPU samples display an ellipsis; inaccessible counters are hidden.
Partial process coverage must not be presented as an exact full-application
number. The sampler observes the current UID, not other apps' command lines.

## Checks

In the existing build container: `make test-performance-hud` exercises actual
native stat parsers/live procfs, old-setting migration, every settings-store
copy path, persistence/reload, PID reuse/birth, units, shared timers,
background/foreground and late completions. `make ... hap` is the actual ArkTS,
resource and native-link gate. ARM64 device results are recorded separately;
unit tests cannot prove sensor/procfs permissions on a device.

HiDebug reference: [official native API](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-performance-analysis-kit/capi-hidebug-h.md)
and [CPU usage units](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-performance-analysis-kit/js-apis-hidebug.md#hidebuggetsystemcpuusage12).

## ARM64 device check (2026-08-31)

The single-line candidate was incrementally built in 12.9 seconds, signature
verified and replacement-installed, preserving the 1.3.2/API 23 debug identity.
Tested HAP SHA-256:
`d0fa1cd23d0e52e8474b9b1eecce51480a9328267548b991e237939763d459c5`
(467,414,574 bytes). Subsequent label clarification spells out application vs
system CPU and was separately compiled; do not confuse candidate hashes.

War3 reached its animated menu through the regular WineD3D product launch,
without batch overrides. All five selected metrics persisted through replacement
installation and restart. A screenshot showed 54 FPS, application CPU ≥233%,
system CPU 41%, battery 32°C, thermal level 0. These are UI functionality
observations, **not** a controlled performance benchmark. The phone exposes 12
logical CPUs to `top`; application 200% therefore need not conflict with a much
lower system percentage. The HiDebug fallback supplies system CPU because the
app's direct system-counter read did not produce usable data.

Backgrounding stopped the HiDebug sampling calls (quiet over the checked four
seconds after settling); returning through EntryAbility resumed them. A direct
HDC launch of non-exported DesktopAbility was correctly rejected and was not
used to bypass visibility. A coordinate-based master-toggle check was
inconclusive because the list position changed; do not count it as a pass.
The automated sampler lifecycle/all-off tests pass; final live switch inspection
continues alongside the separately requested bottom-navigation layout fix.
ARM64 and x86_64 API 23 native syntax checks pass. Only ARM64 is linked and
tested on hardware; the broader GL/Vulkan/performance qualification remains open.
