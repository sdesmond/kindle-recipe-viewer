# Kindle Recipe Viewer

A touch-native recipe reader for e-ink Kindles, built for cooking with a
[Paprika Recipe Manager](https://www.paprikaapp.com/) collection.

## Overview

Export your recipes from Paprika, compile them on a computer into a small
deterministic library, and copy the result onto a jailbroken Kindle. The
Kindle-side runtime is POSIX shell that draws with firmware `eips` and
KOReader's `fbink`, giving a large-text, e-ink-tuned reading and cooking
experience with no network dependency once it's on the device.

## Features

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

## Supported hardware

Right now this targets exactly one device: a **Kindle Paperwhite 2**
(758×1024, 212 DPI) on **firmware 5.12.2.2**, with KOReader's FBInk at
`/mnt/us/koreader/fbink` and raw touch at `/dev/input/event1`.

### Porting to other Kindle models

Other Kindles aren't supported today, but the parts of the runtime that are
device-specific are contained enough to port deliberately. Getting this
running on a different model or firmware would mean re-establishing, on that
hardware:

- **Screen geometry and DPI** — panel resolution, orientation, and the
  318 px/12 px-style layout constants derived from it.
- **Display command paths** — where `eips` and/or FBInk live on that
  firmware, and which draw/refresh commands (`DU`, `GC16`, etc.) they
  support.
- **Touch device path and event format** — the raw `/dev/input/eventN` node
  and confirmation that it emits standard Linux `input_event` records mapped
  1:1 to screen pixels (some panels report scaled or rotated coordinates).
- **Font metrics calibration** — FBInk's rendered glyph width/height can
  differ from host font metrics; the wrapping code needs a measured
  correction factor for the new device, the same way `RV_FONT_WIDTH_PERCENT`
  was measured for the Paperwhite 2.

`.agents/memories/kindle-paperwhite-2-runtime.md` documents exactly how each
of these was determined for the Paperwhite 2 through hardware trials — it's
the template to repeat for a new device, including the dead ends (like
`orientationLock` not working) worth not retrying.

## Requirements

- A **jailbroken Kindle**. Stock Kindle firmware only runs Amazon-signed
  code; this project needs to run its own unsigned shell script and call
  KOReader's `fbink` binary directly, both of which require a jailbreak.
  Jailbreak availability and method depend on your exact device model and
  firmware version — this repo doesn't document that process itself. Start
  with the community references, which stay current as Amazon ships new
  firmware:
  - [KindleModding jailbreak FAQ](https://kindlemodding.org/jailbreaking/jailbreak-faq.html)
  - [Installing KUAL/MRPI](https://kindlemodding.gitbook.io/kindlemodding/post-jailbreak/installing-kual-mrpi)
- **KOReader installed** on the device, per its
  [official installation guide](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices).
  This project uses KOReader only for the `fbink` binary it ships
  (`/mnt/us/koreader/fbink`); you don't need to use KOReader itself as a
  reader.
- A computer with **Python 3** and **PowerShell** (for `tools/compile_paprika.py`
  and `tools/deploy.ps1`) and a USB cable to the Kindle.

## Exporting your recipes from Paprika

Get [Paprika](https://www.paprikaapp.com/) to produce a `.paprikarecipes`
file — a zip archive of gzip-compressed per-recipe JSON, which
`tools/compile_paprika.py` reads directly.

### Desktop (Mac/Windows)

1. In Paprika, choose **File > Export**.
2. Pick a category to export, or leave it on the default **All Recipes**.
3. Choose **Paprika Recipe Format** (not HTML).
4. Save the resulting `My Recipes.paprikarecipes` file somewhere you can
   point `tools/compile_paprika.py` at it.

### Mobile (iOS/Android)

1. In Paprika, go to **Settings > Export Recipes**.
2. Choose **Paprika Recipe Format** (Android also offers HTML — you want
   Paprika Recipe Format).
3. On Android, the exported file is written to the device's Downloads
   folder. On iOS, the share sheet opens — send it to Files, AirDrop, or
   email it to yourself.
4. Get the `.paprikarecipes` file onto the computer you'll run
   `tools/compile_paprika.py` on.

## Build the recipe library

From this repository, against the full 229-recipe archive:

```powershell
python tools/compile_paprika.py `
  ..\recipe-viewer\paprika-export-examples\full-set-cleaned.paprikarecipes `
  --output build\library
```

(`bulk-export.paprikarecipes`, a 19-recipe subset, is handy for quicker
iteration.)

The compiler reads ZIP entries containing gzip-compressed Paprika JSON and
transforms them for the Kindle rather than copying them through untouched:

- Normalizes text: converts CRLF/CR/U+2028 line endings to `\n`, maps curly
  quotes, en/em dashes, the ellipsis character, fraction glyphs (`½`, `¼`,
  etc.), and the multiplication sign to plain ASCII equivalents, then
  NFKD-normalizes and strips combining marks — so accented characters lose
  their diacritics (the Kindle font/rasterizer doesn't support them).
- Splits ingredients and instruction paragraphs into individual lines,
  classifies section headers, and strips manual step numbers (`1.`, `2)`)
  and matched emphasis markers (`**bold**`, `_italic_`), since the Kindle
  renderer has no inline styling to preserve them for.
- Resolves Paprika recipe links (`[recipe:Title]`, appearing in ingredients
  and directions alike) by title against the other recipes in the same
  archive: a match records the target's uid on that record, plus the exact
  linked phrase text for instruction steps (so the device can locate and
  underline just that span); a title with no match in the archive falls
  back to plain text.
- Appends Notes to the instructions.
- Excludes photos and every other Paprika field the viewer doesn't use.
- Rejects a recipe only if it has an empty ingredient list — a recipe with
  no directions at all (an ingredients-only rub or mix) compiles fine with
  an empty instructions pane.

It emits `manifest.tsv` plus one ordinal `.recipe` record file per recipe.
`build/` is ignored because it contains the personal, deployable library
artifact.

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
