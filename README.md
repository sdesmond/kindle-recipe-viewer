# Kindle Recipe Viewer

A touch-native, USB-deployed recipe reader for the Kindle Paperwhite 2. Paprika
archives are compiled on the computer into a small deterministic library; the
Kindle runtime is POSIX shell and draws with firmware `eips` plus KOReader's
`fbink`.

## Current vertical slice

- Alphabetical recipe list with large 17 pt, 64 px touch rows, vertical
  swipes, a proportional scroll rail, and case-insensitive title filtering
  through a built-in touch keyboard.
- Portrait 758×1024 cook screen with a 300 px Ingredients pane, 2 px divider,
  and 456 px Instructions pane.
- Flush-left ingredients with text strikethrough checks and independent pane
  scrolling.
- Non-flashing rectangular refreshes for checks/cursors (`DU`) and pane/list
  scrolling (`GC16`), with full flashing refreshes on screen transitions and
  after every 12 partial updates to clean the panel.
- Larger 13 pt body text. Instructions use 39 px line advances with a 10 px
  gap between steps while wrapped lines within one step remain continuous.
  Ingredients use tighter 34 px advances between wrapped lines of the same
  item, plus a wider 16 px gap between separate items, so a multi-line
  ingredient reads as one entry instead of blurring into the next.
- Instructions or ingredients that link to another recipe in the same library
  (a Paprika `[recipe:Title]` reference) are underlined and tappable. In an
  instruction step only the linked phrase itself is underlined/tappable, so
  the rest of the step still reads and taps like plain text; in an ingredient
  line there's no competing tap action (checking it off wouldn't mean much
  for a sub-recipe reference), so the whole line is the target and replaces
  the usual check toggle.
- A back button always occupies the top-left of the title bar. With link
  history to unwind it steps back one recipe (chaining through multiple
  hops); at the root, with nothing left to go back to, it takes over what
  the old separate `END RECIPE` button did — asking to confirm before
  clearing checks and returning to the list. Opening a recipe from the
  list/search clears any stale back history. The recipe list itself has the
  same button in the same spot; since there's no recipe left to unwind to,
  it exits the app back to the Kindle Home screen instead.
- There is no idle timeout. The app only closes when the back button on the
  recipe list is tapped.
- Pixel-aware wrapping uses bundled Atkinson metrics calibrated against the
  Kindle's narrower FBInk rasterization to fill each pane while preserving its
  right margin. A shared content-bottom boundary keeps body text and tap
  targets within the visible card.
- Session state exists only in RAM. Exiting or relaunching starts at the list
  with no checks restored; the last e-ink image remains visible.
- Append-only `extensions/RecipeViewer/debug.log` records launches, dependency
  detection, touch/gesture evidence, selections, geometry, and failures.

The target is a Paperwhite 2 on firmware 5.12.2.2 (758×1024, 212 DPI), with
KOReader's FBInk at `/mnt/us/koreader/fbink` and raw touch at
`/dev/input/event1`.

## Build the 19-recipe library

From this repository:

```powershell
python tools/compile_paprika.py `
  ..\recipe-viewer\paprika-export-examples\bulk-export.paprikarecipes `
  --output build\library
```

The compiler reads ZIP entries containing gzip-compressed Paprika JSON. It
normalizes text, splits ingredients and instruction paragraphs, classifies
section headers, removes matched emphasis and manual step numbers,
transliterates unsupported characters, and appends Notes. Paprika recipe
links (`[recipe:Title]`, appearing in ingredients and directions alike) are
resolved by title against the other recipes in the same archive: a match
records the target's uid on that record, plus the exact linked phrase text
for instruction steps (so the device can locate and underline just that
span); a title with no match in the archive falls back to plain text. It
emits `manifest.tsv` plus one ordinal `.recipe` record file per recipe.
Photos and every other unused Paprika field are excluded. `build/` is ignored
because it contains the personal, deployable library artifact.

## Install

Connect the Kindle over USB and pass its drive root explicitly:

```powershell
.\tools\deploy.ps1 -KindleRoot E:\ -ClearLog
```

The command refuses roots without both `documents` and `extensions`, copies the
launcher, bundle, fonts, and compiled library, then compares SHA-256 hashes of
every source/deployed file. Add `-Eject` to request safe ejection after
verification. Restart the Kindle once so `documents/RecipeViewer.sh` is indexed
as a library book.

## Test

```powershell
python -m unittest discover -s tests -p "test_*.py"
bash tests/test_runtime.sh
bash -n documents/RecipeViewer.sh extensions/RecipeViewer/bin/recipe_viewer.sh extensions/RecipeViewer/lib/*.sh
```

Runtime host overrides are `RV_DISPLAY_COMMAND`, `RV_TOUCH_EVENT_FILE`,
`RV_APP_ROOT`, `RV_LIBRARY_ROOT`, `RV_LOG`,
`RV_FBINK_COMMAND`, `RV_EIPS_COMMAND`, `RV_FONT_REGULAR`, and `RV_FONT_BOLD`.
Refresh tuning overrides are `RV_PARTIAL_REFRESH` (`1` or `0`),
`RV_PARTIAL_FULL_EVERY` (default `12`), and `RV_INSTRUCTION_STEP_GAP`
(default `10` px).
The display override receives high-level `clear`, `refresh`, `rect`, and `text`
commands plus `clear-region` and `refresh-region`, enabling golden command-log
tests without a Kindle emulator.
