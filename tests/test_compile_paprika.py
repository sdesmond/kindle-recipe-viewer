from __future__ import annotations

import gzip
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("compile_paprika", ROOT / "tools" / "compile_paprika.py")
assert SPEC and SPEC.loader
compiler = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = compiler
SPEC.loader.exec_module(compiler)


def write_archive(path: Path, recipes: list[dict]) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for index, recipe in enumerate(recipes):
            payload = json.dumps(recipe, ensure_ascii=False).encode("utf-8")
            archive.writestr(f"recipe-{index}.paprikarecipe", gzip.compress(payload, mtime=0))


class CompilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixtures = json.loads((ROOT / "tests" / "fixtures" / "recipes.json").read_text(encoding="utf-8"))

    def test_zip_gzip_ingestion_sort_and_record_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            archive = base / "fixture.paprikarecipes"
            output = base / "library"
            write_archive(archive, list(reversed(self.fixtures)))
            recipes = compiler.read_archive(archive)
            compiler.write_library(recipes, output)
            manifest = (output / "manifest.tsv").read_text(encoding="utf-8")
            self.assertIn("SCHEMA\t1\nCOUNT\t2\n", manifest)
            self.assertLess(manifest.index("Apple Pie"), manifest.index("Zesty Soup"))
            record = (output / "0002.recipe").read_text(encoding="utf-8")
            self.assertTrue(record.startswith("TITLE\tZesty Soup\n"))
            self.assertNotIn("photo", record.lower())

    def test_parsing_and_normalization_rules(self) -> None:
        recipe = compiler.compile_recipe(self.fixtures[0])
        self.assertEqual(recipe.title, "Zesty Soup")
        self.assertEqual(
            [(line.kind, line.text) for line in recipe.ingredients],
            [
                ("section-header", "Soup:"),
                ("item", "1 cup water"),
                ("item", "1 cup water"),
                ("section-header", "Seasoning"),
                ("item", "1/2 tsp salt"),
            ],
        )
        self.assertEqual(recipe.instructions[0], compiler.Line("section-header", "Prepare:"))
        self.assertEqual(
            recipe.instructions[1].text,
            "Stir the Ragu Base into the water. This is a soft wrap.",
        )
        self.assertEqual(recipe.instructions[2].text, "Simmer for 10 minutes.")
        self.assertEqual(recipe.instructions[-2], compiler.Line("section-header", "Notes:"))
        self.assertEqual(recipe.instructions[-1].text, "Keeps for two days.")

    def test_inline_markup_is_line_local_and_unmatched_markers_survive(self) -> None:
        self.assertEqual(compiler.strip_inline_markup("4. **Preheat oven**. Now."), "4. Preheat oven. Now.")
        self.assertEqual(compiler.strip_inline_markup("bring water ** to a boil"), "bring water ** to a boil")
        self.assertEqual(compiler.strip_inline_markup("use sous_vide mode"), "use sous_vide mode")
        self.assertEqual(compiler.classify_line("TOPPINGS").kind, "item")
        self.assertEqual(compiler.classify_line("For serving:").kind, "section-header")

    def test_typographic_characters_tabs_and_line_separator(self) -> None:
        value = "¼ cup crème fraîche\u2028‘yes’ — 2×\t"
        self.assertEqual(compiler.normalize_text(value), "1/4 cup creme fraiche\n'yes' - 2x")

    def test_output_is_deterministic_and_removes_stale_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            archive = base / "fixture.paprikarecipes"
            first = base / "first"
            second = base / "second"
            write_archive(archive, self.fixtures)
            recipes = compiler.read_archive(archive)
            compiler.write_library(recipes, first)
            (first / "9999.recipe").write_text("stale", encoding="utf-8")
            compiler.write_library(recipes, first)
            compiler.write_library(recipes, second)
            self.assertFalse((first / "9999.recipe").exists())
            self.assertEqual(
                {path.name: path.read_bytes() for path in first.iterdir()},
                {path.name: path.read_bytes() for path in second.iterdir()},
            )

    def test_malformed_and_empty_archives_fail_readably(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            empty = base / "empty.paprikarecipes"
            with zipfile.ZipFile(empty, "w"):
                pass
            with self.assertRaisesRegex(compiler.CompileError, "no recipes"):
                compiler.read_archive(empty)
            malformed = base / "bad.paprikarecipes"
            write_archive(malformed, [{"uid": "bad", "name": "Bad"}])
            with self.assertRaisesRegex(compiler.CompileError, "missing required field"):
                compiler.read_archive(malformed)

    def test_cli_has_nonzero_exit_and_diagnostic(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "compile_paprika.py"), "missing.paprikarecipes", "--output", "unused"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("archive not found", result.stderr)

    def test_real_bulk_archive_has_19_recipes(self) -> None:
        archive = ROOT.parent / "recipe-viewer" / "paprika-export-examples" / "bulk-export.paprikarecipes"
        if not archive.exists():
            self.skipTest("sibling recipe-viewer archive is not available")
        self.assertEqual(len(compiler.read_archive(archive)), 19)


if __name__ == "__main__":
    unittest.main()

