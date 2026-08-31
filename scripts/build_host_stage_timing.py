#!/usr/bin/env python3
"""Relink a diagnostic vtest library from an EXISTING native cache; never stage it.

No shell command evaluation, configure, Ninja build, submodule edit, or HAP build.
The result lives only in build/host-stage-timing/<ABI> and is not auto-packaged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess


HOOKS = (
    "vtest_create_context", "vtest_set_current_context", "vtest_destroy_context",
    "vtest_submit_cmd", "vtest_submit_cmd2", "vtest_transfer_put",
    "vtest_transfer_put2", "vtest_transfer_get", "vtest_transfer_get2",
    "vtest_resource_busy_wait", "vtest_sync_wait", "vtest_winehua_present",
    "vtest_set_winehua_present_callback", "virgl_renderer_submit_cmd",
    "virgl_renderer_context_finish", "virgl_renderer_transfer_read_iov",
    "virgl_renderer_transfer_write_iov",
)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE).stdout


def safe_argv(command):
    argv = shlex.split(command)
    if any(arg in {"&&", ";", "|", "||", ">", ">>", "<", "&"} for arg in argv):
        raise ValueError("shell operators are not allowed in a compiler command")
    if not argv or Path(argv[0]).name != "clang":
        raise ValueError("expected cached Clang command")
    return argv


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=("arm64-v8a", "x86_64"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    cache = root / "build" / f"native_{args.arch}" / "virglrenderer"
    output = root / "build" / "host-stage-timing" / args.arch
    if output.is_symlink() or not output.resolve().is_relative_to(root / "build"):
        raise ValueError("diagnostic output must remain inside the existing build directory")
    target = "vtest/libwinehua_vtest_server.so"
    baseline = cache / target
    if not baseline.is_file():
        raise SystemExit("Existing native cache missing; refusing a clean/full rebuild")
    entries = json.loads((cache / "compile_commands.json").read_text())
    entry = next(e for e in entries if e["file"].endswith("/vtest_renderer.c"))
    if Path(entry["directory"]).resolve() != cache.resolve():
        raise ValueError("compile database belongs to a different checkout")
    compile_argv = safe_argv(entry["command"])
    commands = run(["ninja", "-t", "commands", target], cache).splitlines()
    link_argv = safe_argv(commands[-1])
    if link_argv[link_argv.index("-o") + 1] != target or "-shared" not in link_argv:
        raise ValueError("unexpected cached link target")
    compiler = Path(compile_argv[0])
    if Path(link_argv[0]) != compiler:
        raise ValueError("compiler/linker mismatch")
    nm = compiler.with_name("llvm-nm")
    # Validate the cross-object references on which --wrap depends. Same-TU or
    # future LTO inlining must not silently yield a convincing but empty profile.
    references = (
        ("vtest/libvtest.a.p/vtest_server.c.o", HOOKS[:12]),
        ("vtest/libwinehua_vtest_server.so.p/winehua_vtest_server.c.o", HOOKS[12:13]),
        ("vtest/libvtest.a.p/vtest_renderer.c.o", HOOKS[13:]),
    )
    for obj, symbols in references:
        undefined = {line.split()[-1] for line in run([str(nm), "-u", obj], cache).splitlines()
                     if line.split()}
        if not set(symbols).issubset(undefined):
            raise ValueError(f"missing wrap references in {obj}: {set(symbols) - undefined}")
    # Inventory thin archive members as well as the archive itself.
    inputs = {baseline, cache / "compile_commands.json", cache / "build.ninja",
              root / "smoke/winehua_host_stage_timing.c", Path(__file__).resolve()}
    inputs.update(cache.rglob("*.o"))
    inputs.update(cache.rglob("*.a"))
    inputs.update(cache.rglob("*.so*"))
    inputs.update((root / "thirdparty/virglrenderer/vtest").glob("*.h"))
    inputs.add(root / "thirdparty/virglrenderer/src/virglrenderer.h")
    inputs.add(cache / "src/virgl-version.h")
    inputs.add(cache / "config.h")
    for value in link_argv[1:]:
        path = Path(value)
        if not value.startswith("-") and path.is_absolute() and path.is_file():
            if not path.resolve().is_relative_to(root):
                raise ValueError("unexpected external cached link input")
            inputs.add(path)
    inventory = {str(p.relative_to(root)): digest(p) for p in sorted(inputs) if p.is_file()}
    candidate = output / "libwinehua_vtest_server.so"
    manifest_path = output / "manifest.json"
    object_path = output / "host_stage_timing.o"
    if any(path.is_symlink() for path in (candidate, manifest_path, object_path)):
        raise ValueError("refusing symlink diagnostic outputs")
    signature = {"arch": args.arch, "inputs": inventory, "hooks": HOOKS,
                 "compile": compile_argv, "link": link_argv}
    fingerprint = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()
    if manifest_path.is_file() and candidate.is_file():
        previous = json.loads(manifest_path.read_text())
        if previous.get("fingerprint") == fingerprint and previous.get("sha256") == digest(candidate):
            print(f"Diagnostic library unchanged: {candidate}")
            return
    output.mkdir(parents=True, exist_ok=True)
    # Keep the original include/ABI/optimization flags but redirect every output.
    filtered = []
    index = 0
    while index < len(compile_argv):
        value = compile_argv[index]
        if value in ("-o", "-MF", "-MQ", "-MT", "-c"):
            index += 2
            continue
        if value not in ("-MD", "-MMD", "-MP"):
            filtered.append(value)
        index += 1
    filtered += ["-c", str(root / "smoke/winehua_host_stage_timing.c"),
                 "-o", str(object_path)]
    print("Compiling one diagnostic bridge; reusing all existing renderer objects", flush=True)
    run(filtered, cache)
    link_argv[link_argv.index("-o") + 1] = str(candidate)
    link_argv += [str(object_path)] + [f"-Wl,--wrap={name}" for name in HOOKS]
    run(link_argv, cache)
    symbols = {line.split()[-1] for line in run([str(nm), str(candidate)], cache).splitlines()
               if line.split()}
    if not {"__wrap_" + name for name in HOOKS}.issubset(symbols):
        raise ValueError("linked diagnostic hooks missing")
    # Confirm relinking did not modify any cache object or production library.
    for path, before in inventory.items():
        if digest(root / path) != before:
            raise RuntimeError(f"Input changed during diagnostic build: {path}")
    manifest = dict(signature, fingerprint=fingerprint, sha256=digest(candidate),
                    diagnostic_only=True, staged=False,
                    metrics="calls/wall_us/cpu_us/max_wall_us/nonzero_returns/invalid_clock/submit_words")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Diagnostic only; NOT staged or installed: {candidate}")
    print(f"SHA256 {manifest['sha256']}")


if __name__ == "__main__":
    main()
