# Controller Hub capability notes (Phase 0)

Base: VintagePomeloPro **1.3.1** (`fc2b8799`) / branch `feature/controller-hub-p0`.

## Game Controller Kit (host)

| Item | Status |
|------|--------|
| Headers (`game_pad.h` / `game_device.h`) | Used via **dlopen** symbols in `game_controller_bridge.cpp` (existing path) |
| `libohgame_controller.z.so` | Runtime `dlopen`; not statically linked in P0 |
| Online/offline | `OH_GameDevice_RegisterDeviceMonitor` → Hub `ResetSource(Physical)` + ArkTS UI |
| ABXY / shoulders / menu / L3R3 / DPad buttons | Mapped OH codes → `LogicalButton` in `physical_gamepad.cpp` |
| Sticks / triggers / hat axes | Axis monitors → Hub; **+Y=Up** flipped once in Physical adapter |
| Deadzone | Hub radial inner **0.10** (settings deadzone still used by keyboard_legacy sink) |

## Wine / duplicate risk

| Item | Status |
|------|--------|
| `bus_sdl` on OHOS | Can enumerate physical pads → **duplicate** with Hub |
| Mitigation | `WINEHUA_CONTROLLER_HUB=1` gates `sdl_add_device` |
| `bus_ohos` | WHGP AF_UNIX → `hid_device_add_gamepad()`; MVP `is_gamepad=FALSE` (DInput) |
| Env | `WINEHUA_GAMEPAD_ENABLE`, `WINEHUA_GAMEPAD_MODE`, `WINEHUA_GAMEPAD_SOCKET` |

## Architecture (P0)

```
Touch Overlay ──NAPI──┐
  STICK analog / D-Pad hat / mapped face buttons
Physical Kit ─Native──┼─► ControllerHub ─► WHGP sock ─► winebus bus_ohos ─► DInput
keyboard_legacy ──────┘ (legacy: GamepadManager → evdev only; Hub off for Wine)
```

## File map

| Path | Role |
|------|------|
| `entry/.../cpp/controller/*` | Hub, merge, WHGP server, NAPI, Physical feed, runtime mode |
| `entry/.../cpp/game_controller_bridge.cpp` | Kit dlopen; dual-feed Hub + ArkTS TSFN |
| `thirdparty/wine/dlls/winebus.sys/bus_ohos.c` | Wine virtual gamepad |
| `host_tests/controller_merge_test.cpp` | Ownership / trigger max / deadzone |

## Risks

- Kit axis polarity may differ by pad firmware — verify on tablet test page.
- Wine rebuild required after `bus_ohos` changes (`make wine` + `make hap`).
- Mode switch needs session restart for Wine env to refresh.
