# Contract: Layout Row (extended to 9 columns)

**Producer**: `rv_build_layout` (`extensions/RecipeViewer/lib/ui.sh`)
**Consumers**: `rv_draw_pane`, `rv_layout_hit` (same file)
**Location**: `$RV_TMP/ingredients.layout`, `$RV_TMP/instructions.layout`

This is an **existing** format. Recipe scaling appends one column; columns 1-8
keep their current meaning and position exactly, so any consumer that does not
care about markers keeps working unmodified.

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

## Consumer obligations

**`rv_draw_pane`**
- Add a ninth variable to its `IFS`-split `read`. A `read` with too few
  variables would fold column 9 into column 8's variable and corrupt link
  underline geometry.
- When column 9 is non-empty, draw the row text as `<marker><space><text>`.
  The marker is presentation only: it is **not** included in the column 5
  measured width, so strikethrough and link underline widths — both computed
  from column 5 — stay aligned with the ingredient text they belong to, not
  with the marker.
- Do not spend an extra `rv_rect`/`rv_text` call on the marker. Each FBInk
  invocation costs ~100-200 ms on this device; the marker must ride inside the
  row's existing single `rv_text` call.

**`rv_layout_hit`**
- Ignores column 9. It hit-tests by `y` (and, for instruction links, by the
  column 7/8 pixel span), neither of which the marker participates in.
- Its behaviour is unchanged, but its field expectations are asserted by the
  golden tests in `tests/test_runtime.sh`, which must be updated alongside.

**Any new consumer** must tolerate an empty column 9 rather than requiring it,
since instruction layouts and 1x ingredient layouts always emit it empty.

## Compatibility note

The synthetic layout fixture in `tests/test_runtime.sh` (the 30-row gap-dense
scroll regression) writes rows with a literal `printf` format string and must
gain the ninth field, or `rv_draw_pane`'s widened `read` will silently see an
empty text column.
