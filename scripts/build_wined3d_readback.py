#!/usr/bin/env python3
"""Compile one WineD3D diagnostic object per PE width, relink cached objects only."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess

HOOKS = (
    "wined3d_device_context_emit_map", "wined3d_texture_load_location",
    "wined3d_texture_download_from_texture", "wined3d_device_context_emit_blt_sub_resource",
    "wined3d_cs_emit_present",
)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE).stdout


def parse_command(output, target, executable):
    matches = []
    for line in output.replace("\\\n", " ").splitlines():
        args = shlex.split(line)
        if not args or Path(args[0]).name != executable:
            continue
        if "-o" in args and args[args.index("-o") + 1] == target:
            matches.append(args)
    if len(matches) != 1:
        raise ValueError(f"Require one cached {executable} recipe for {target}")
    if any(a in {";", "&&", "||", "|", ">", ">>", "&"} for a in matches[0]):
        raise ValueError("Unexpected shell syntax in recipe")
    return matches[0]


def command(cache, target, prerequisite, executable):
    # -n expands the existing recipe; no forced compile or new configure.
    output = run(["make", "-n", "-o", "Makefile", "-W", prerequisite, target], cache)
    return parse_command(output, target, executable)


def diagnostic_commands(compile_args, link_args, original, source, obj, dll):
    # Preserve the original recipes in the fingerprint/manifest. In particular,
    # inserting the new object must not mutate the recorded cache link recipe.
    compile_args, link_args = list(compile_args), list(link_args)
    compile_args[compile_args.index("-o") + 1] = str(obj)
    compile_args[compile_args.index(str(original))] = str(source)
    compile_args += ["-Werror", "-Wno-declaration-after-statement"]
    link_args[link_args.index("-o") + 1] = str(dll)
    # Import archives are order-sensitive: expose the bridge's API references
    # before kernel32/ntdll/ucrtbase import-library scanning.
    first_obj = next(i for i, a in enumerate(link_args) if a.endswith(".o"))
    link_args.insert(first_obj, str(obj))
    link_args += [f"-Wl,--wrap={h}" for h in HOOKS]
    return compile_args, link_args


def parse_exports(output):
    marker = "[Ordinal/Name Pointer] Table"
    if output.count(marker) != 1:
        raise ValueError("Require one PE named export table")
    bases = set(re.findall(r"Ordinal Base\s+(\d+)", output))
    if len(bases) != 1:
        raise ValueError("Missing or ambiguous PE ordinal base")
    base = int(bases.pop())
    section = output.split(marker, 1)[1].strip().split("\n\n", 1)[0]
    # Binutils variants print either '[index] name' or
    # '[index] +base[ordinal] hint name'. Never accept an empty/empty comparison.
    rows = re.findall(r"^\s*\[\s*(\d+)\]\s+(?:\+base\[\s*(\d+)\]\s+[0-9a-fA-F]+\s+)?(\S+)\s*$",
                      section, re.MULTILINE)
    exports = []
    for index, explicit, name in rows:
        ordinal = int(index) + base
        if explicit and int(explicit) != ordinal:
            raise ValueError("Inconsistent export ordinal")
        exports.append((ordinal, name))
    if not exports or len({name for _, name in exports}) != len(exports):
        raise ValueError("Empty or duplicate named exports")
    if len(re.findall(r"^\s*\[", section, re.MULTILINE)) != len(rows):
        raise ValueError("Unparsed export row")
    return exports


def build(root, arch, prefix):
    cache = root / "build/wine-ohos"
    out = root / "build/wined3d-readback" / arch
    source = root / "smoke/winehua_wined3d_readback.c"
    original = root / "thirdparty/wine/dlls/wined3d/texture_gl.c"
    obj_target = f"dlls/wined3d/{arch}/texture_gl.o"
    dll_target = f"dlls/wined3d/{arch}/wined3d.dll"
    if not (cache / obj_target).is_file() or not (cache / dll_target).is_file():
        raise ValueError(f"Missing {arch} WineD3D cache; no full rebuild allowed")
    compile_args = command(cache, obj_target, str(original), prefix + "-gcc")
    link_args = command(cache, dll_target, obj_target, "winegcc")
    if "-shared" not in link_args or prefix not in link_args:
        raise ValueError("Unexpected WineD3D link ABI")
    nm = prefix + "-nm"
    leading = "_" if arch == "i386-windows" else ""
    references = {
        "device.o": (HOOKS[0], HOOKS[3]), "surface.o": (HOOKS[1], HOOKS[2]),
        "texture_gl.o": (HOOKS[1],), "swapchain.o": (HOOKS[4],),
    }
    for obj_name, hooks in references.items():
        undefined = {line.split()[-1] for line in run([nm, "-u", f"dlls/wined3d/{arch}/{obj_name}"], cache).splitlines() if line.split()}
        if not {leading + h for h in hooks}.issubset(undefined):
            raise ValueError(f"Unwrappable cross-object calls in {obj_name}")
    inputs = {Path(__file__).resolve(), source, cache / "Makefile", cache / dll_target}
    for args in (compile_args, link_args):
        for a in args:
            p = Path(a)
            p = p if p.is_absolute() else cache / p
            if not a.startswith("-") and p.is_file():
                inputs.add(p)
    for headers in (root / "thirdparty/wine/include", root / "thirdparty/wine/dlls/wined3d",
                    root / "thirdparty/wine/libs/vkd3d/include", cache / "include"):
        inputs.update(headers.rglob("*.h"))
    inventory = {str(p): digest(p) for p in sorted(inputs)}
    signature = dict(inputs=inventory, compile=compile_args, link=link_args, hooks=HOOKS)
    fingerprint = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()
    dll, obj, manifest = out / "wined3d.dll", out / "readback.o", out / "manifest.json"
    deploy = out / "deploy/wined3d.dll"
    if out.is_symlink() or not out.resolve().is_relative_to(root / "build") or any(p.is_symlink() for p in (dll, obj, manifest, deploy, deploy.parent)):
        raise ValueError("Diagnostic output must stay inside build")
    if dll.is_file() and manifest.is_file():
        old = json.loads(manifest.read_text())
        if old.get("fingerprint") == fingerprint and old.get("sha256") == digest(dll) and deploy.is_file() and old.get("deploy_sha256") == digest(deploy):
            print(f"WineD3D {arch} diagnostic unchanged, not staged: {dll}")
            return
    out.mkdir(parents=True, exist_ok=True)
    diagnostic_compile, diagnostic_link = diagnostic_commands(
        compile_args, link_args, original, source, obj, dll)
    print(f"Compiling one {arch} diagnostic object; all original Wine objects reused", flush=True)
    run(diagnostic_compile, cache)
    run(diagnostic_link, cache)
    symbols = {line.split()[-1] for line in run([nm, str(dll)], cache).splitlines() if line.split()}
    if not {leading + "__wrap_" + h for h in HOOKS}.issubset(symbols):
        raise ValueError("Missing linked WineD3D diagnostic wrappers")
    objdump = prefix + "-objdump"
    for function, hook in (("wined3d_device_context_map", HOOKS[0]),
                           ("wined3d_swapchain_present", HOOKS[4])):
        assembly = run([objdump, "-d", "--disassemble=" + leading + function, str(dll)], cache)
        if "<" + leading + "__wrap_" + hook + ">" not in assembly:
            raise ValueError(f"Hook not actually called from {function}")
    def exports(path):
        return parse_exports(run([objdump, "-p", str(path)], cache))
    if exports(dll) != exports(cache / dll_target):
        raise ValueError("WineD3D export names/ordinals changed")
    deploy.parent.mkdir(exist_ok=True)
    run([prefix + "-strip", "--strip-debug", "-o", str(deploy), str(dll)], cache)
    if exports(deploy) != exports(dll):
        raise ValueError("Stripping changed exports")
    for path, before in inventory.items():
        if digest(Path(path)) != before:
            raise ValueError(f"Original input changed: {path}")
    metadata = dict(signature, fingerprint=fingerprint, sha256=digest(dll),
                    baseline_sha256=digest(cache / dll_target), deploy_sha256=digest(deploy),
                    diagnostic_compile=diagnostic_compile, diagnostic_link=diagnostic_link,
                    diagnostic_only=True, staged=False)
    manifest.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"WineD3D diagnostic only, not staged: {deploy}\nSHA256 {metadata['deploy_sha256']}")


def main():
    root = Path(__file__).resolve().parent.parent
    for arch, prefix in (("i386-windows", "i686-w64-mingw32"), ("x86_64-windows", "x86_64-w64-mingw32")):
        build(root, arch, prefix)


if __name__ == "__main__":
    main()
