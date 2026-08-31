# Contract: Layout Row (extended to 10 columns)

**Producer**: `rv_build_layout` (`extensions/RecipeViewer/lib/ui.sh`)
**Consumers**: `rv_draw_pane`, `rv_layout_hit` (same file)
**Location**: `$RV_TMP/ingredients.layout`, `$RV_TMP/instructions.layout`

This is an **existing** format. Recipe scaling appends two columns; columns
1-8 keep their current meaning and position exactly, so any consumer that
does not care about markers keeps working unmodified.

## Columns

| # | Name | Values | Status |
|---|---|---|---|
| 1 | record index | 1-based index of the source record within its type | unchanged |
| 2 | kind | `item` \| `section-header` | unchanged |
| 3 | row text | this wrapped row's text | unchanged |
| 4 | first-row marker | `1` on an item's first wrapped row, `0` after | unchanged |
| 5 | measured width | row width in 35 px Atkinson units | unchanged |
| 6 | link uid | uid, or empty | unchanged |
| 7 | link prefix width | units from row start to the link phrase | unchanged |
| 8 | link phrase width | units spanned by the link phrase | unchanged |
| 9 | marker | empty \| `~` \| `!` | **new** |
| 10 | marker width | width of `<marker><space>` in 35 px Atkinson units, or `0` | **new** |

## Column 9 rules

- Sourced from column 6 of the [scaled ingredient
  record](./scaled-ingredient-record.md): `approx` → `~`, `flag` → `!`,
  empty → empty.
- Set on an item's **first wrapped row only** (column 4 == `1`). Continuation
  rows always carry an empty marker, so a wrapped flagged ingredient is marked
  once, not once per row.
- Always empty for `instructions.layout`. Instruction records never pass
  through the scaler (FR-030).
- Always empty when the active scale factor is `1x`, because the scaler does
  not run.

## Column 10 rules

- `measured(marker " ")` when column 9 is non-empty, `0` otherwise — the
  on-screen width the marker prefix consumes before the row's own text
  begins.
- Exists because the marker is drawn as a literal `<marker><space>` prefix
  inside the row's own `rv_text` call (see column 9 rules for `rv_draw_pane`
  below), which shifts where the row's *actual* glyphs start relative to
  column 5's measurement (which is taken from the unmarked text). Consumers
  that derive pixel geometry from column 5 or column 7 must add column 10's
  pixel-converted value to their start X on a marked row, or that geometry
  drifts left by the marker's width relative to the text it should align to.

## Consumer obligations

**`rv_draw_pane`**
- Add a ninth and tenth variable to its `IFS`-split `read`. A `read` with too
  few variables would fold trailing columns into the last variable and
  corrupt link underline geometry.
- When column 9 is non-empty, draw the row text as `<marker><space><text>`,
  and offset the strikethrough/link-underline start X by column 10 (converted
  to pixels the same way column 5/7 are) so that geometry stays aligned with
  the ingredient text itself rather than starting under the marker.
- Do not spend an extra `rv_rect`/`rv_text` call on the marker. Each FBInk
  invocation costs ~100-200 ms on this device; the marker must ride inside the
  row's existing single `rv_text` call.

**`rv_layout_hit`**
- Ignores columns 9 and 10. It hit-tests by `y` (and, for instruction links,
  by the column 7/8 pixel span), neither of which the marker participates in.
- Its behaviour is unchanged, but its field expectations are asserted by the
  golden tests in `tests/test_runtime.sh`, which must be updated alongside.

**Any new consumer** must tolerate an empty column 9 / zero column 10 rather
than requiring them, since instruction layouts and 1x ingredient layouts
always emit them empty/zero.

## Compatibility note

The synthetic layout fixture in `tests/test_runtime.sh` (the 30-row gap-dense
scroll regression) writes rows with a literal `printf` format string and must
gain the ninth and tenth fields, or `rv_draw_pane`'s widened `read` will
silently see an empty text column.
