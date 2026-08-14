#!/usr/bin/env python3
"""Compile a Paprika export into the Kindle Recipe Viewer record format."""

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import sys
import tempfile
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 4
RECIPE_LINK = re.compile(r"\[recipe:([^\]\r\n]+)\]", re.IGNORECASE)
STEP_NUMBER = re.compile(r"^\s*\d+\s*[.)]\s+")
WHOLE_EMPHASIS = re.compile(r"^(\*\*|__|\*|_)(?P<body>\S(?:.*?\S)?)\1$")
PARAGRAPH_BREAK = re.compile(r"\n[ \t]*\n+")

CHARACTER_MAP = str.maketrans(
    {
        "\u00bd": "1/2",
        "\u00bc": "1/4",
        "\u00be": "3/4",
        "\u215b": "1/8",
        "\u215c": "3/8",
        "\u215d": "5/8",
        "\u215e": "7/8",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\u00d7": "x",
        "\u00a0": " ",
        "\u2026": "...",
    }
)


class CompileError(ValueError):
    """A readable, user-facing archive validation failure."""


@dataclass(frozen=True)
class Line:
    kind: str
    text: str
    link_title: str = ""


@dataclass(frozen=True)
class Recipe:
    uid: str
    title: str
    ingredients: tuple[Line, ...]
    instructions: tuple[Line, ...]


def normalize_text(value: object, *, preserve_newlines: bool = True) -> str:
    """Normalize source text to the glyphs and records supported on the Kindle."""
    if value is None:
        return ""
    if not isinstance(value, str):
        raise CompileError(f"expected text field, got {type(value).__name__}")
    text = value.replace("\r\n", "\n").replace("\r", "\n").replace("\u2028", "\n")
    text = text.translate(CHARACTER_MAP)
    text = "".join(
        character
        for character in unicodedata.normalize("NFKD", text)
        if not unicodedata.combining(character)
    )
    text = text.replace("\t", " ")
    if preserve_newlines:
        return "\n".join(re.sub(r"[ ]+", " ", line).strip() for line in text.split("\n"))
    return re.sub(r"\s+", " ", text).strip()


def strip_inline_markup(text: str) -> str:
    """Strip matched emphasis pairs on one line, retaining unmatched markers."""
    patterns = (
        re.compile(r"\*\*(?=\S)(.+?)(?<=\S)\*\*"),
        re.compile(r"(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)"),
        re.compile(r"(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)"),
        re.compile(r"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"),
    )
    for pattern in patterns:
        previous = None
        while previous != text:
            previous = text
            text = pattern.sub(r"\1", text)
    return re.sub(r"\s+", " ", text).strip()


def classify_line(raw_line: str) -> Line:
    text = raw_line.strip()
    # Paprika links are plain title references (no id); the target is resolved
    # against the rest of the compiled library once every title is known. Only
    # the first link in a line becomes navigable, matching real-world exports
    # where at most one appears per instruction step.
    link_title = ""
    link_match = RECIPE_LINK.search(text)
    if link_match:
        # The device later locates this phrase inside the flattened line with
        # a plain substring search, so the inserted text must be byte-identical
        # to link_title, not the raw (unsqueezed) bracket contents.
        link_title = normalize_text(link_match.group(1), preserve_newlines=False)
        text = text[: link_match.start()] + link_title + text[link_match.end() :]
        text = RECIPE_LINK.sub(lambda match: match.group(1), text)
    whole = WHOLE_EMPHASIS.fullmatch(text)
    if whole:
        return Line("section-header", strip_inline_markup(whole.group("body")), link_title)
    kind = "section-header" if len(text) < 60 and text.endswith(":") else "item"
    return Line(kind, strip_inline_markup(text), link_title)


def parse_ingredients(value: object) -> tuple[Line, ...]:
    normalized = normalize_text(value)
    return tuple(classify_line(line) for line in normalized.split("\n") if line.strip())


def _instruction_blocks(value: object) -> Iterable[list[str]]:
    normalized = normalize_text(value)
    for paragraph in PARAGRAPH_BREAK.split(normalized):
        lines = [line.strip() for line in paragraph.split("\n") if line.strip()]
        if lines:
            yield lines


def parse_instructions(value: object) -> tuple[Line, ...]:
    result: list[Line] = []
    for block in _instruction_blocks(value):
        first = classify_line(block[0])
        if first.kind == "section-header":
            result.append(first)
            block = block[1:]
        if block:
            item = classify_line(" ".join(block))
            # A header is only recognized independently at the start of a block.
            text = STEP_NUMBER.sub("", item.text)
            if text:
                result.append(Line("item", text, item.link_title))
    return tuple(result)


def compile_recipe(payload: object, entry_name: str = "<recipe>") -> Recipe:
    if not isinstance(payload, dict):
        raise CompileError(f"{entry_name}: recipe JSON must be an object")
    try:
        uid_value = payload["uid"]
        title_value = payload["name"]
        ingredients_value = payload["ingredients"]
        directions_value = payload["directions"]
    except KeyError as error:
        raise CompileError(f"{entry_name}: missing required field {error.args[0]!r}") from error

    uid = normalize_text(uid_value, preserve_newlines=False)
    title = normalize_text(title_value, preserve_newlines=False)
    if not uid:
        raise CompileError(f"{entry_name}: uid is empty")
    if not title:
        raise CompileError(f"{entry_name}: title is empty")

    ingredients = parse_ingredients(ingredients_value)
    instructions = list(parse_instructions(directions_value))
    notes = parse_instructions(payload.get("notes", ""))
    if notes:
        instructions.append(Line("section-header", "Notes:"))
        instructions.extend(notes)
    if not ingredients:
        raise CompileError(f"{entry_name}: ingredients contain no items")
    # Some real recipes (a spice rub, "combine and serve") have no separate
    # directions beyond the ingredient list itself, so an empty instructions
    # pane is valid rather than a sign of a malformed entry.
    return Recipe(uid, title, ingredients, tuple(instructions))


def read_archive(archive: Path) -> list[Recipe]:
    if not archive.is_file():
        raise CompileError(f"archive not found: {archive}")
    recipes: list[Recipe] = []
    seen_uids: set[str] = set()
    try:
        with zipfile.ZipFile(archive) as source:
            entries = sorted(name for name in source.namelist() if not name.endswith("/"))
            if not entries:
                raise CompileError("archive contains no recipes")
            for name in entries:
                try:
                    raw_json = gzip.decompress(source.read(name))
                except (OSError, EOFError) as error:
                    raise CompileError(f"{name}: entry is not valid gzip data") from error
                try:
                    payload = json.loads(raw_json.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as error:
                    raise CompileError(f"{name}: entry is not valid UTF-8 JSON") from error
                recipe = compile_recipe(payload, name)
                if recipe.uid in seen_uids:
                    raise CompileError(f"{name}: duplicate uid {recipe.uid!r}")
                seen_uids.add(recipe.uid)
                recipes.append(recipe)
    except zipfile.BadZipFile as error:
        raise CompileError(f"not a valid Paprika ZIP archive: {archive}") from error
    recipes.sort(key=lambda recipe: (recipe.title.casefold(), recipe.uid))
    return recipes


def _record_field(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\t", " ")).strip()


def write_library(recipes: list[Recipe], output: Path) -> None:
    if not recipes:
        raise CompileError("refusing to write an empty library")
    output_parent = output.parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}-", dir=output_parent))
    try:
        # Paprika links reference a target by title text alone, so resolution
        # can only happen once every recipe's title is known.
        title_to_uid = {recipe.title.casefold(): recipe.uid for recipe in recipes}
        manifest_lines = [f"SCHEMA\t{SCHEMA_VERSION}", f"COUNT\t{len(recipes)}"]
        for ordinal, recipe in enumerate(recipes, 1):
            filename = f"{ordinal:04d}.recipe"
            manifest_lines.append(
                "\t".join(("RECIPE", filename, _record_field(recipe.uid), _record_field(recipe.title)))
            )
            record_lines = [f"TITLE\t{_record_field(recipe.title)}"]
            for line in recipe.ingredients:
                link_uid = title_to_uid.get(line.link_title.casefold(), "") if line.link_title else ""
                # An ingredient link has no competing tap action (unlike an
                # instruction step, which still needs to work for its other
                # text), so the device treats the whole line as the target
                # instead of locating a specific phrase within it.
                record_lines.append(
                    "\t".join(("INGREDIENT", line.kind, _record_field(line.text), _record_field(link_uid)))
                )
            for line in recipe.instructions:
                link_uid = title_to_uid.get(line.link_title.casefold(), "") if line.link_title else ""
                # Only a resolved link carries its phrase forward: the device
                # locates this exact substring within the line to underline and
                # hit-test just that phrase, not the whole instruction step.
                link_phrase = line.link_title if link_uid else ""
                record_lines.append(
                    "\t".join((
                        "INSTRUCTION",
                        line.kind,
                        _record_field(line.text),
                        _record_field(link_uid),
                        _record_field(link_phrase),
                    ))
                )
            (stage / filename).write_text("\n".join(record_lines) + "\n", encoding="utf-8", newline="\n")
        (stage / "manifest.tsv").write_text(
            "\n".join(manifest_lines) + "\n", encoding="utf-8", newline="\n"
        )

        output.mkdir(parents=True, exist_ok=True)
        for old in output.glob("[0-9][0-9][0-9][0-9].recipe"):
            old.unlink()
        for generated in sorted(stage.iterdir()):
            shutil.move(str(generated), output / generated.name)
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compile ZIP/gzip Paprika recipes into Kindle-safe record files."
    )
    parser.add_argument("archive", type=Path, help="input .paprikarecipes archive")
    parser.add_argument("--output", required=True, type=Path, help="output library directory")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        recipes = read_archive(args.archive)
        write_library(recipes, args.output)
    except (CompileError, OSError) as error:
        print(f"compile_paprika: error: {error}", file=sys.stderr)
        return 2
    print(f"Compiled {len(recipes)} recipes into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

