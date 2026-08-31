"""Build-helper tests only; actual Wine ABI/call sites need both PE relinks."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "scripts/build_wined3d_readback.py"
spec = importlib.util.spec_from_file_location("readback_build", path)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class RecipeTest(unittest.TestCase):
    def test_continuation_and_unrelated_targets(self):
        recipe = ('cc -o unrelated.o unrelated.c\n'
                  'i686-w64-mingw32-gcc -c \\\n'
                  '"/source with space/texture_gl.c" -o target.o\n')
        args = build.parse_command(recipe, "target.o", "i686-w64-mingw32-gcc")
        self.assertEqual(args[2], "/source with space/texture_gl.c")

    def test_missing_and_ambiguous_fail_closed(self):
        line = "winegcc -shared -o target.dll source.o\n"
        for output in ("", line + line, line.replace("target.dll", "other.dll")):
            with self.assertRaises(ValueError):
                build.parse_command(output, "target.dll", "winegcc")

    def test_shell_operators_rejected(self):
        for operator in (";", "&&", "||", "|", ">", ">>", "&"):
            with self.assertRaises(ValueError):
                build.parse_command(f"winegcc -o target.dll a.o {operator} other",
                                    "target.dll", "winegcc")

    def test_redirect_does_not_mutate_original_recipes(self):
        compile_args = ["gcc", "-c", "/wine/texture_gl.c", "-o", "texture_gl.o"]
        link_args = ["winegcc", "-shared", "-o", "original.dll", "a.o", "kernel32.a"]
        original_compile, original_link = list(compile_args), list(link_args)
        c, link = build.diagnostic_commands(compile_args, link_args,
            "/wine/texture_gl.c", "/root/probe.c", "/build/probe.o", "/build/probe.dll")
        self.assertEqual(compile_args, original_compile)
        self.assertEqual(link_args, original_link)
        self.assertEqual(c[c.index("-o") + 1], "/build/probe.o")
        self.assertIn("/root/probe.c", c)
        self.assertNotIn("/wine/texture_gl.c", c)
        self.assertEqual(link[link.index("-o") + 1], "/build/probe.dll")
        self.assertLess(link.index("/build/probe.o"), link.index("kernel32.a"))
        self.assertEqual(sum(arg.startswith("-Wl,--wrap=") for arg in link), len(build.HOOKS))

    def test_changed_source_recipe_rejected(self):
        with self.assertRaises(ValueError):
            build.diagnostic_commands(["gcc", "-c", "different.c", "-o", "a.o"],
                ["winegcc", "-o", "a.dll", "a.o"], "expected.c", "probe.c", "probe.o", "probe.dll")

    def test_export_names_and_ordinals(self):
        output = "Ordinal Base 1\n[Ordinal/Name Pointer] Table\n\t[ 0] alpha\n\t[ 2] beta\n\nRelocations:\n[ 3] not_export"
        self.assertEqual(build.parse_exports(output), [(1, "alpha"), (3, "beta")])
        changed = output.replace("[ 2] beta", "[ 3] beta")
        self.assertNotEqual(build.parse_exports(output), build.parse_exports(changed))

    def test_new_binutils_export_format(self):
        output = "[Ordinal/Name Pointer] Table -- Ordinal Base 1\n\tOrdinal Hint Name\n\t[ 329] +base[ 330] 0000 alpha\n\t[ 0] +base[ 1] 0001 beta\n"
        self.assertEqual(build.parse_exports(output), [(330, "alpha"), (1, "beta")])
        with self.assertRaises(ValueError):
            build.parse_exports(output.replace("+base[ 330]", "+base[ 331]"))

    def test_missing_empty_duplicate_exports_rejected(self):
        for output in ("", "[Ordinal/Name Pointer] Table\n",
                       "Ordinal Base 1\n[Ordinal/Name Pointer] Table\n[ 0] a\n[ 1] a\n",
                       "Ordinal Base 1\n[Ordinal/Name Pointer] Table\n[ 0] a\n[ 1] unexpected format b\n"):
            with self.assertRaises(ValueError):
                build.parse_exports(output)


if __name__ == "__main__":
    unittest.main()
