# GLES Direct candidate validation

Implementation branch: `refact/gl-optimization`, based on verified fullscreen/input
checkpoint `7d5e7874c37bff5cdd781d90dbc750cb6a7a4de4`. This is a candidate,
not a declaration that the optimization roadmap or device gates are complete.

## Preserved checkpoint

- Original `codex/graphics-refactor-performance` branch remains intact.
- The verified 1.3.2 / API 23 / ARM64 debug HAP is retained under ignored
  `.hvigor/outputs/gl-direct-baseline-20260831/baseline-1.3.2-arm64.hap`.
  SHA-256: `08233d398b036a231f092ff8e4ca329af0512ce7d89d6fb8ab91ef9f79b9395e`.
- That directory's `rollback.md` records exact artifact provenance and local
  Wine font / GStreamer build patches. No runtime submodule is changed here.
- Reuse `vp-build` and `/home/maple/vp-src`; incremental Host/HAP builds only.
  Build-machine paths are evidence, not portable defaults.

## Measurement entry

`automation/Measure-WineHuaGlPerformance.ps1` launches the regular game Want
using WineD3D and the existing `observe-product-summary` diagnostic policy.
It does not add a launch environment, product profile or batch-flush override.
`-Attach` samples an already running, manually checked menu.

Every 120 successful presents, the explicitly enabled summary records bounded
raw presenter CPU durations, four stage sums, and frame intervals. The parser
rejects mixed transports/surfaces, lost windows and truncated samples. Frame
intervals are Host publication cadence, **not** GPU completion latency or proof
of consumer-visible frame order. Screenshots and manual checks remain required.

The initial EGL-only instrumented HAP is also retained as `egl-timing-baseline.hap`:
SHA-256 `6a15e0eb608a0bc821a8e5aa64380070b1a8ae07f9de1a44924895afa0b6f7e1`.
The existing container built it incrementally in 11.2 seconds; signature,
payload, replacement installation and War3 menu visibility were checked.

2026-08-31 exploratory samples (not the three-pair acceptance benchmark):

- `egl-initial-20260831-123031`: invalid, existing EGL path reported
  `GL_OUT_OF_MEMORY (0x505)`. GLES target was not in this binary.
- `egl-ready-20260831-123512`: 5,040 samples / 91.24 seconds; presenter cadence
  55.24 FPS, presenter CPU P95 540 us; frame interval P95 21,230 us and P99
  23,692 us. Menu screenshot visible. The first failure remains an open
  stability observation; a passing second sample does not erase it.
- Temperature/power matching and repeated-pair noise estimates are not yet
  available. These values cannot justify enabling GLES Direct by default.

## Acceptance gates still required

War3 cold starts x3 (intro/menu, fullscreen pointer, minimize/restore); GL x86
and x64, resize and foreground/background x5 each, then ten continuous minutes;
Modern DXVK media with CPU UI around it and normal video completion; both
DXVK generations' D3D11 cube. Record the pre-existing brief War3 minimize
transition separately from any new regression.

For default enablement: alternate EGL/candidate three times at the same War3
800x600 menu, warm 30 seconds, sample 90 seconds. Match thermal, power and
display conditions. Require a gain above noise and either FPS >=5% or CPU
P95 reduction >=10%, without repeatable frame-interval P95/P99 regression >3%.
Otherwise retain EGL as default. Do not test batchMappedFlush=off.

PC/x86_64 host device matrix, D3D12, heavier GPU workloads, longer stability,
scanout copy elimination, Host upload/sync work and capability-gate cleanup
remain separate follow-ups. The stable fullscreen fix is independently
reviewable; this candidate must not delay or imply requalification of it.
