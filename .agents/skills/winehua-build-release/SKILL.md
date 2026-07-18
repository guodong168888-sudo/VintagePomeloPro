---
name: winehua-build-release
description: Project-local workflow for updating, developing, compiling, signing, validating, installing, and packaging the WineHua HarmonyOS application. Use for changes on VintagePomeloMaster, ARM64 Pad builds, guest gfx/VirGL validation, debug HAPs, formal signed APPs, version bumps, native interface changes, device deployment, and release troubleshooting.
---

# WineHua Build And Release

Use this skill for work in the WSL repository `/home/yifengling0/src/WineHua`. Keep source and generated build data in the WSL filesystem; use Windows paths only for explicitly requested handoff files, signing material import, or device tooling.

## Current Baseline

The current product line is the branded master line:

| Item | Current value |
| --- | --- |
| Repository | `/home/yifengling0/src/WineHua` |
| Primary branch | `VintagePomeloMaster` |
| Upstream source | `origin/master` |
| Bundle name | `com.vintage.pomelopro` |
| Display name | `旧柚Pro` |
| Current release version | `1.0.5` / version code `1000005` |
| Target device | ARM64 HarmonyOS Pad |
| Docker image | `winehua-dev` |
| Command-line tools | `/mnt/f/command-line-tools` mounted read-only into Docker |

The branch may contain local branding and asset changes that are intentionally not upstream changes. Before source updates, inspect the worktree and preserve unrelated user changes.

## Source And Git Workflow

1. Work from WSL, not from `/mnt/f` or a Windows checkout, for source, dependency, and build IO.
2. Check the branch and worktree before changing anything:

   ```bash
   git -C /home/yifengling0/src/WineHua status --short --branch
   git -C /home/yifengling0/src/WineHua branch --show-current
   git -C /home/yifengling0/src/WineHua log -1 --oneline
   ```

3. Update only from the requested upstream branch. The normal update is:

   ```bash
   git -C /home/yifengling0/src/WineHua fetch origin
   git -C /home/yifengling0/src/WineHua log --oneline HEAD..origin/master
   ```

   Merge or rebase `origin/master` into `VintagePomeloMaster` only after checking that local branding, icon, version, signing, and build-script changes are understood. Do not switch to or modify `dev` unless explicitly requested.

4. The Wine submodule is part of the build input. After updating the parent repository, check its pointer and status:

   ```bash
   git -C /home/yifengling0/src/WineHua submodule status -- thirdparty/wine
   git -C /home/yifengling0/src/WineHua/thirdparty/wine status --short
   ```

   Do not reset or clean a dirty submodule without explicit approval.

## Branding And Versioning

Keep the following values consistent when changing the product identity:

- `AppScope/app.json5`: `bundleName` must remain `com.vintage.pomelopro`.
- AppScope and entry localized string resources: `app_name` and `EntryAbility_label` must be `旧柚Pro` in every shipped locale.
- Runtime launch, uninstall, path, or package-name constants must use `com.vintage.pomelopro`. Check at least `entry/src/main/cpp/wine_child.cpp`, `entry/src/main/ets/service/WineWindowManager.ets`, `entry/src/main/ets/pages/Index.ets`, and `scripts/package.sh` when changing package identity.
- The desktop icon is the foreground/application icon asset. Do not replace the startup/splash asset when the request is only to change the desktop icon. Check both AppScope and entry media resources after an icon update.
- Increase both `versionName` and numeric `versionCode` for a functional release. Keep the two values aligned with the intended release, for example `1.0.5` and `1000005`.

Do not alter package identity or version as an incidental build fix. Verify the final HAP and APP metadata rather than relying only on source text.

## Docker Build Environment

The canonical build runs in WSL with the repository bind-mounted into Docker. The Harmony command-line tools are mounted from Windows only as a tool input; build output and source remain under `/home` in WSL.

Use this ARM assemble command for the native build and HAP assembly:

```bash
wsl.exe -d Ubuntu-22.04 -- docker run --rm -i \
  --mount type=bind,src=/home/yifengling0/src/WineHua,dst=/data/src/winehua \
  --mount type=bind,src=/mnt/f/command-line-tools,dst=/apps/harmony,readonly \
  -w /data/src/winehua \
  -e NATIVE_ARCH=arm64-v8a \
  -e BUILD_GUEST_GFX=1 \
  -e TOOL_HOME=/apps/harmony \
  -e OHOS_SDK=/apps/harmony/sdk/default/openharmony \
  winehua-dev make NATIVE_ARCH=arm64-v8a BUILD_GUEST_GFX=1 assemble
```

The formal APP step uses the same mounts and environment:

```bash
docker run --rm -i \
  --mount type=bind,src=/home/yifengling0/src/WineHua,dst=/data/src/winehua \
  --mount type=bind,src=/mnt/f/command-line-tools,dst=/apps/harmony,readonly \
  -w /data/src/winehua \
  -e NATIVE_ARCH=arm64-v8a \
  -e TOOL_HOME=/apps/harmony \
  -e OHOS_SDK=/apps/harmony/sdk/default/openharmony \
  winehua-dev hvigorw assembleApp -m project -p product=proRelease -p buildMode=release
```

The repository's Makefile and scripts may accept equivalent `make` targets. Prefer the repository's existing target implementation over manually invoking individual compiler or signing commands.

### Stamps And Rebuilds

The Makefile uses generated stamps. If a source or build-script change is incorrectly reported as up-to-date, remove only the exact affected stamp, then rerun the target:

```bash
docker run --rm -i \
  --mount type=bind,src=/home/yifengling0/src/WineHua,dst=/data/src/winehua \
  winehua-dev rm -f /data/src/winehua/build/.stamps/arm64-v8a/assemble
```

Do not use a broad clean or delete the whole build tree to work around a stamp without first checking the dependency and output state. Some generated files are root-owned because they were created by Docker.

## Guest Graphics And ARM Validation

`BUILD_GUEST_GFX=1` is required for the ARM Pad VirGL package. Host VirGL libraries alone are not sufficient. The nested `resources/rawfile/wine-data.zip` must contain the guest Mesa bundle, including:

```text
bin/guest_gfx/winehua-guest-gfx.env
bin/guest_gfx/lib/libEGL.so
bin/guest_gfx/lib/dri/virtio_gpu_dri.so
```

The main HAP must also contain these ARM libraries:

```text
libs/arm64-v8a/libentry.so
libs/arm64-v8a/libwinehua_vtest_server.so
libs/arm64-v8a/libvirglrenderer.so.1
libs/arm64-v8a/libvirgl_child.so
resources/rawfile/wine-data.zip
```

When validating a package, inspect the outer APP, its main HAP, and the nested `wine-data.zip`. A package with host libraries but `guest_gfx_count=0` is incomplete and must not be installed or released.

The local `scripts/build_ohos_guest_gfx.sh` contains an important build workaround: it resolves the Wayland scanner from the Wayland build tree and regenerates `wayland-scanner.pc` with the actual scanner path. Preserve this behavior when updating Mesa or guest gfx scripts.

## Debug HAP Flow

Keep the existing debug HAP path unchanged. Use the repository's debug target, for example:

```bash
make NATIVE_ARCH=arm64-v8a DEVICE_TYPE=pad BUILD_GUEST_GFX=1 hap
```

or the equivalent `scripts/package.sh hap` interface documented by the repository. Debug builds use the `default` signing configuration in the local `build-profile.json5` and should produce an `entry-default-signed.hap`-style artifact. Confirm the output metadata before installing it.

Do not use the formal release profile for routine device debugging. Debug HAP installation and uninstall commands must use the current bundle name `com.vintage.pomelopro`.

## Formal APP Flow And Signing

Formal packaging is separate from `buildMode=release`:

- The formal product is `proRelease`.
- The formal signing configuration is `release`.
- Invoke `hvigorw assembleApp -m project -p product=proRelease -p buildMode=release` after the ARM assemble step.
- Do not route the formal APP through the hand-written debug `sign.py` path.
- Expected output naming is `WineHua-proRelease-signed.app` from hvigor; the project handoff may rename or copy it to a versioned file such as `VintagePomeloMaster-v1.0.5-signed.app`.

The local ignored `build-profile.json5` contains both profiles:

- `default`: existing debug signing materials under `.ohos/`.
- `release`: formal signing materials under the local ignored `signs/` directory, alias `hv`, and `SHA256withECDSA`.
- `proRelease`: product bound to the `release` signing profile.

Never put passwords, encrypted password values, private keys, certificate contents, or profile contents in this skill, source control, logs, or final reports. The expected local formal files are:

```text
signs/hyperview.cer
signs/hyperview.p12
signs/pomelo-pro-release.p7b
```

Before formal signing, verify that the local `signs/` files are the newly supplied materials and that `build-profile.json5` remains ignored. If signing reports a profile/bundle mismatch, inspect the profile's bundle name and certificate before changing source metadata.

## Artifact Validation

For every release candidate, record the absolute output path, file size, SHA-256, version, bundle name, and signing result. A useful Windows-side handoff directory is `F:\Release\VPPro`; the authoritative build should still run in WSL.

At minimum, validate:

1. APP exists and is non-empty.
2. The APP contains the expected main HAP.
3. HAP metadata reports `com.vintage.pomelopro` and `旧柚Pro`.
4. Version name and numeric version code match the intended release.
5. ARM native libraries and nested guest gfx files listed above exist.
6. The artifact is signed by the intended debug or formal profile.

For a repeatable hash report from WSL:

```bash
sha256sum /home/yifengling0/src/WineHua/dist/*.app
du -h /home/yifengling0/src/WineHua/dist/*.app
```

Do not infer a successful package from a successful native compile alone; validate the final archive contents.

## Device Deployment

Use `hdc` only after a package passes artifact validation. For a connected Pad, identify the device and uninstall the old package before installing the replacement:

```bash
hdc list targets
hdc shell bm uninstall -n com.vintage.pomelopro
hdc install -r /path/to/entry-default-signed.hap
```

If the device is not visible from WSL, USB/IP may need to be configured on the Windows host with `usbipd-win`, then the USB device attached to WSL. This is a transport prerequisite, not a reason to move the repository or build output to `/mnt/f`.

Use debug-signed HAPs for development installation unless formal-signature testing is specifically requested. Keep the package identity unchanged so uninstall and upgrade behavior is meaningful.

## Native Interface Guardrails

Recent master changes refactored broker environment propagation to a single `__env__` entry-parameter channel and fixed bundled-library lookup for x86_64 Unixlibs. When merging upstream or changing launch code, inspect these files together:

```text
entry/src/main/cpp/wine_env.h
entry/src/main/cpp/wine_env.cpp
entry/src/main/cpp/wine_launch.h
entry/src/main/cpp/wine_launch.cpp
entry/src/main/cpp/wine_exe.cpp
entry/src/main/cpp/wine_child.cpp
entry/src/main/cpp/broker.cpp
entry/src/main/cpp/broker.h
```

The serialization declaration/definition and all callers must stay consistent. Do not reintroduce the removed broker-session environment override path without a documented compatibility need. Run the ARM assemble and package-content checks after native launch changes.

## Submission And Privacy Errors

If AppGallery reports that the privacy statement's application name is incorrect, compare the final package before changing the archive format. The known 1.0.4-to-1.0.5 package comparison showed identical outer entries, HAP entry counts, nested `wine-data.zip` entry counts, and `pac.json`; only version metadata and expected binaries changed. This indicates a portal-side privacy statement association issue, not a missing arbitrary privacy JSON in the APP.

For that error, create or associate a new privacy statement in the AppGallery console using:

```text
Application name: 旧柚Pro
Bundle name: com.vintage.pomelopro
```

Do not add guessed privacy fields to `pac.json` or alter signing/package structure to solve a portal association error.

## Safety Rules

- Never expose or commit signing passwords or private signing material.
- Preserve unrelated dirty worktree changes.
- Do not reset, force-clean, or rewrite the Wine submodule without explicit approval.
- Do not build the heavy source/dependency tree under `/mnt/f`.
- Do not silently switch branches; confirm the requested branch before updating.
- Do not install a package that has not passed nested guest gfx and bundle metadata checks.
- When a build appears stuck, inspect the active Docker/hvigor process and stamp state before starting another overlapping build.
