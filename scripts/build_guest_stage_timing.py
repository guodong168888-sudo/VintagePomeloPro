#!/usr/bin/env python3
"""Build one diagnostic Guest bridge and relink cached Mesa; never stage/deploy.

No Meson configure, Ninja build, runtime zip, submodule edits or cache changes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess

HOOKS = (
    "virgl_vtest_connect", "virgl_vtest_busy_wait", "virgl_vtest_submit_cmd",
    "virgl_vtest_send_transfer_get", "virgl_vtest_send_transfer_put",
    "virgl_vtest_send_winehua_present",
    "st_ReadPixels", "st_GetTexSubImage",
)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE).stdout


def argv(command, name):
    args = shlex.split(command)
    if not args or Path(args[0]).name != name:
        raise ValueError(f"Expected cached {name} command")
    if any(a in {"&&", ";", "|", "||", ">", ">>", "<", "&"} for a in args):
        raise ValueError("Shell operators in compiler command")
    if "--target=x86_64-linux-ohos" not in args:
        raise ValueError("Guest ABI must be x86_64-linux-ohos")
    return args


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--busy-io", action="store_true", help="Isolated packed busy I/O candidate; not a product default")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    cache = root / "build/guest_gfx_build/x86_64/wayland-virpipe"
    out = root / "build" / ("guest-busy-io" if options.busy_io else "guest-stage-timing") / "x86_64"
    if out.is_symlink() or not out.resolve().is_relative_to(root / "build"):
        raise ValueError("Output escapes build directory")
    libraries = list((cache / "src/gallium/targets/dri").glob("libgallium-*.so"))
    if len(libraries) != 1:
        raise ValueError("Require exactly one existing Guest Mesa library; no full rebuild")
    baseline = libraries[0]
    target = str(baseline.relative_to(cache))
    database = json.loads((cache / "compile_commands.json").read_text())
    entry = next(e for e in database if e["file"].endswith("/virgl_vtest_socket.c"))
    if Path(entry["directory"]).resolve() != cache.resolve():
        raise ValueError("Compile database belongs to another checkout")
    compile_args = argv(entry["command"], "clang")
    link_args = argv(run(["ninja", "-t", "commands", target], cache).splitlines()[-1], "clang++")
    if link_args[link_args.index("-o") + 1] != target or "-shared" not in link_args:
        raise ValueError("Unexpected cached link target")
    if Path(compile_args[0]).parent != Path(link_args[0]).parent:
        raise ValueError("Compiler/linker toolchain mismatch")
    nm = str(Path(compile_args[0]).with_name("llvm-nm"))
    references = (
        ("src/gallium/winsys/virgl/vtest/libvirglvtest.a.p/virgl_vtest_winsys.c.o", HOOKS[:6]),
        ("src/mesa/libmesa.a.p/main_readpix.c.o", HOOKS[6:7]),
        ("src/mesa/libmesa.a.p/main_texgetimage.c.o", HOOKS[7:]),
    )
    for obj_path, hooks in references:
        undefined = {line.split()[-1] for line in run([nm, "-u", obj_path], cache).splitlines() if line.split()}
        if not set(hooks).issubset(undefined):
            raise ValueError(f"Unavailable wrappers in {obj_path}: {set(hooks) - undefined}")
    source = root / "smoke/winehua_guest_stage_timing.c"
    inputs = {source, Path(__file__).resolve(), baseline, cache / "compile_commands.json", cache / "build.ninja"}
    if options.busy_io:
        inputs.add(root / "smoke/winehua_vtest_busy_io.h")
    for pattern in ("*.o", "*.a", "*.sym", "*.h"):
        inputs.update(cache.rglob(pattern))
    inputs.update((root / "thirdparty/mesa/src/gallium/winsys/virgl/vtest").glob("*.h"))
    inputs.add(root / "thirdparty/mesa/src/virtio/virtio-gpu/virgl_protocol.h")
    inputs.add(root / "thirdparty/mesa/src/virtio/vtest/vtest_protocol.h")
    inputs.add(root / "thirdparty/mesa/src/mesa/state_tracker/st_cb_readpixels.h")
    inputs.add(root / "thirdparty/mesa/src/mesa/state_tracker/st_cb_texture.h")
    inputs.add(root / "thirdparty/mesa/src/mesa/main/formats.h")
    # Record explicit extra link inputs, including the SDK shared zlib dependency.
    for a in link_args:
        p = Path(a)
        if not a.startswith("-") and p.is_absolute() and p.is_file():
            inputs.add(p)
    inventory = {str(p): digest(p) for p in sorted(inputs)}
    defines = ["-DWINEHUA_GUEST_BUSY_IO=1"] if options.busy_io else []
    signature = {"inputs": inventory, "hooks": HOOKS, "compile": compile_args,
                 "link": link_args, "defines": defines, "busy_io": options.busy_io}
    fingerprint = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()
    candidate, obj, manifest = out / baseline.name, out / "guest_stage_timing.o", out / "manifest.json"
    if any(p.is_symlink() for p in (candidate, obj, manifest)):
        raise ValueError("Refusing symlink diagnostic outputs")
    if candidate.is_file() and manifest.is_file():
        previous = json.loads(manifest.read_text())
        if previous.get("fingerprint") == fingerprint and previous.get("sha256") == digest(candidate):
            print(f"Guest diagnostic unchanged, not staged: {candidate}")
            return
    out.mkdir(parents=True, exist_ok=True)
    filtered, index = [], 0
    while index < len(compile_args):
        a = compile_args[index]
        if a in ("-o", "-c", "-MF", "-MQ", "-MT"):
            index += 2
            continue
        if a not in ("-MD", "-MMD", "-MP"):
            filtered.append(a)
        index += 1
    print("Compiling one Guest diagnostic bridge; reusing all Mesa objects", flush=True)
    run(filtered + defines + ["-c", str(source), "-o", str(obj)], cache)
    link_args[link_args.index("-o") + 1] = str(candidate)
    link_args += [str(obj)] + [f"-Wl,--wrap={hook}" for hook in HOOKS]
    run(link_args, cache)
    symbols = {line.split()[-1] for line in run([nm, str(candidate)], cache).splitlines() if line.split()}
    if not {"__wrap_" + h for h in HOOKS}.issubset(symbols):
        raise ValueError("Missing linked Guest hooks")
    for p, before in inventory.items():
        if digest(Path(p)) != before:
            raise ValueError(f"Build input changed: {p}")
    metadata = dict(signature, fingerprint=fingerprint, sha256=digest(candidate),
                    baseline_sha256=digest(baseline), diagnostic_only=True, staged=False)
    manifest.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Guest diagnostic only, NOT staged or installed: {candidate}")
    print(f"SHA256 {metadata['sha256']}")


if __name__ == "__main__":
    main()
