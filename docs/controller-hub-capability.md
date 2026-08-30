# Controller Hub capability notes

Base: VintagePomeloPro **1.3.1** / branch `feature/controller-hub-p0`.

## Game Controller Kit (host)

| Item | Status |
|------|--------|
| Headers (`game_pad.h` / `game_device.h`) | Used via **dlopen** symbols in `game_controller_bridge.cpp` |
| `libohgame_controller.z.so` | Runtime `dlopen`; not statically linked |
| Online/offline | `OH_GameDevice_RegisterDeviceMonitor` → Hub `ResetSource(Physical)` + ArkTS UI |
| ABXY / shoulders / menu / L3R3 / DPad buttons | Mapped OH codes → `LogicalButton` in `physical_gamepad.cpp` |
| Sticks / triggers / hat axes | Axis monitors → Hub; **+Y=Up** flipped once in Physical adapter |
| Deadzone | Hub radial inner **0.10** (settings deadzone still used by keyboard_legacy sink) |
| Kit vibration | **None** — Game Controller Kit is input-only |

## Rumble / haptics

Wine XInput/DInput force-feedback → `winebus` `hid_device_add_haptics` → WHGP `WHGP_MSG_RUMBLE` → host `GamepadBridge` recv loop → ArkTS `@kit.SensorServiceKit` vibrator.

| Item | Status |
|------|--------|
| Target | **External pad motors only** (`!isLocalVibrator`). Never the tablet motor. |
| Dual motor | Two exposed vibrators: low → first, high → second. One vibrator: `max(low,high)`. |
| Intensity | HD pattern (`VibratorPatternBuilder`) when `isHdHapticSupported`; else time vibration. |
| Permission | `ohos.permission.VIBRATE` |

## Wine / duplicate risk

| Item | Status |
|------|--------|
| `bus_sdl` on OHOS | Can enumerate physical pads → **duplicate** with Hub |
| Mitigation | `WINEHUA_CONTROLLER_HUB=1` gates `sdl_add_device` |
| `bus_ohos` | WHGP AF_UNIX → `hid_device_add_gamepad()` + haptics; `is_gamepad=TRUE` (XInput + DInput) |
| Env | `WINEHUA_GAMEPAD_ENABLE`, `WINEHUA_GAMEPAD_MODE`, `WINEHUA_GAMEPAD_SOCKET` |

## Architecture

```
Touch Overlay ──NAPI──┐
  STICK analog / D-Pad hat / mapped face buttons
Physical Kit ─Native──┼─► ControllerHub ─► WHGP sock ─► winebus bus_ohos ─► DInput/XInput
keyboard_legacy ──────┘ (legacy: GamepadManager → evdev only; Hub off for Wine)

Wine haptics ──WHGP rumble──► GamepadBridge RecvLoop ──TSFN──► ArkTS vibrator (pad motors)
```

## File map

| Path | Role |
|------|------|
| `entry/.../cpp/controller/*` | Hub, merge, WHGP server (state + rumble recv), NAPI, Physical feed |
| `entry/.../cpp/game_controller_bridge.cpp` | Kit dlopen; dual-feed Hub + ArkTS TSFN including rumble |
| `entry/.../ets/service/GamepadManager.ets` | Overlay / legacy mapping; pad vibrator targeting |
| `thirdparty/wine/dlls/winebus.sys/bus_ohos.c` | Wine virtual gamepad + rumble write |
| `host_tests/controller_merge_test.cpp` | Ownership / trigger max / deadzone |

## Risks

- Kit axis polarity may differ by pad firmware — verify on tablet test page.
- Harmony may not expose a gamepad vibrator (`getVibratorInfoSync` empty of `!isLocalVibrator`) — settings shows `震动: 无外接马达`; tablet will not buzz. Unverified on pads without a system vibrator.
- Wine rebuild required after `bus_ohos` changes (`make wine` + `make hap`).
- Mode switch needs session restart for Wine env to refresh.
