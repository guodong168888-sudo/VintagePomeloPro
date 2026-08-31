# Bottom navigation layout fix — 2026-08-31

## Root cause

The custom `PhoneNavigationTab` in `Index.ets` specified a fixed 48vp height,
the same as `HdsTabs.barHeight(48)`. On the tested HDS implementation the bar
reserves 4vp padding on each side vertically, leaving a **40vp inner slot**.
The 48vp custom child overflowed that slot by 8vp and its centered contents
were therefore 4vp below the actual bar center. `justifyContent(Center)` was
already present; adding another centering modifier would not fix the mismatch.

Device density was 3.5 px/vp. Baseline layout evidence:

- TabBar y=2615..2783 (168px = 48vp).
- Inner slot y=2629..2769 (140px = 40vp).
- Custom child y=2629..2797 (168px), extending 28px below its slot.
- Combined icon/text y=2656..2770, center 2713; bar center 2699.

## Change

Use a 56vp floating bar, matching the documented HDS floating-tab default,
and let the custom content height follow its inner slot with `height('100%')`.
The existing horizontal and vertical centering remains; icon/text gap is 2vp.
A small pure layout helper owns bar height, gesture-safe bottom margin, outer
container height and list/file-browser bottom clearance so these cannot drift.
No graphics/runtime/input-routing policy changes are involved.

Reference: [Huawei HdsTabs barHeight](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs).

## Validation

`make test-bottom-navigation test-performance-hud` passes in the existing
container; HAP incrementally built in 9.4 seconds, signature verified and
replacement-installed. `scripts/verify_bottom_navigation_layout.ps1` checks the
real UI layout dump, not screenshots alone. It rejects the baseline overflow
and passes all five fixed tabs, including after cycling through the five tabs.

Fixed device layout: bar y=2587..2783; slot and custom child both y=2601..2769;
icon/text extent y=2626..2744. Both centers are 2685: **0px vertical offset**.
Visual screenshot confirms increased breathing room and centered labels/icons.
Portrait ARM64 is device-tested; landscape and varying safe insets have model
tests, not a completed physical device matrix.

Combined HUD/navigation development HAP: 1.3.2 (1003002), API 23, ARM64 debug,
467,413,093 bytes, SHA-256
`64a8fc96ebedda8c28be4234b20f83a9596b56a4157e4e9cafe622ed160fc154`.
Evidence stays in ignored `.hvigor/outputs/performance-hud-20260831`.
