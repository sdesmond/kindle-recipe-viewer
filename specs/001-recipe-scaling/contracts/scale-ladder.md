# Contract: Scale Ladder and Badge Control

The cook-facing surface of the feature: the fixed factor set, its cycle order,
the badge that displays it, and the tap that changes it.

## Ladder

Defined in `extensions/RecipeViewer/lib/core.sh`. Closed set (FR-002, FR-029);
there is no free numeric entry.

| index | num/den | label | notes |
|---|---|---|---|
| 0 | 1/1 | `1x` | the recipe as written; scaler bypassed |
| 1 | 3/2 | `1 1/2x` | |
| 2 | 2/1 | `2x` | |
| 3 | 3/1 | `3x` | |
| 4 | 1/2 | `1/2x` | |

**Cycle**: `index = (index + 1) mod 5`, wrapping from `1/2x` back to `1x`.
Scaling up is the more common intent, so the ladder ascends first and puts
`1 1/2x` one tap from the default. `1x` is always at most four taps away
(FR-003).

**Reset to index 0** on: opening any recipe (`rv_load_recipe`), following or
unwinding a recipe link, ending the recipe, and `rv_reset_session` (FR-006).

## Badge

Drawn in the cook screen's title bar, right-aligned, on every `rv_draw_cook`.

| Property | Value | Constraint |
|---|---|---|
| x | `RV_SCALE_BADGE_X` = 632 | |
| y | `RV_SCALE_BADGE_Y` = 4 | matches the back button's y |
| width | `RV_SCALE_BADGE_W` = 120 | must fit `1 1/2x` at 19 pt |
| height | `RV_SCALE_BADGE_H` = 58 | matches the back button; sits inside `RV_TITLE_H` = 66 |
| stroke | 2 | same as the back button outline |
| label point size | `RV_TITLE_PT` = 19 | vertically centred with `rv_pxh "$RV_TITLE_PT" 0` |

**Always drawn**, at every factor including `1x`, because it is the only
control for changing scale. FR-005 requires the *factor* be visible when it is
not `1x`; the *control* must be reachable always.

**Knock-on**: the cook screen title truncation shrinks from 28 characters to
**22**, since the title's available width drops from 688 px to 554 px. The
golden geometry assertions in `tests/test_runtime.sh` cover this.

**Visible from both panes**: the badge is in the title bar, above the pane
divider, so it is on screen while the cook reads the instruction pane — whose
amounts never scale (FR-030). This is what satisfies FR-031 and SC-009.

## Tap

Handled in `rv_handle_cook_gesture`, ordered **after** the existing back-button
check so the two title-bar targets cannot overlap.

```
gesture == tap
  AND RV_Y2 <  RV_TITLE_H            (66)
  AND RV_X2 >= RV_SCALE_BADGE_X      (632)
  → advance the ladder, rescale, request RV_REDRAW=scale
```

The back button tests `RV_X1 < 64` (touch **start**); the badge tests
`RV_X2 >= 632` (touch **end**), consistent with how the existing handlers
already split start-x for pane selection and end-x for in-pane targets.

The badge is a cook-screen control only. The recipe list, search, and
confirmation screens have no badge and no scale gesture.

## Redraw

A scale change sets `RV_REDRAW=scale`, dispatched by
`bin/recipe_viewer.sh` to a new `rv_draw_cook_scale_partial`, which refreshes
**two** regions with `GC16` — the waveform pane scrolling already uses:

| Region | x, y, w, h |
|---|---|
| badge | 632, 4, 120, 58 |
| ingredient pane | 0, `RV_CONTENT_TOP` (110), `RV_INGREDIENT_W` (300), 904 |

The instruction pane is **not** redrawn and its layout file is **not** rebuilt
(FR-030, SC-010). Both regions honour `rv_partial_allowed`, falling back to a
full `rv_draw_cook` on the periodic cleanup cycle or on a region failure,
exactly like the existing partial paths.

## Post-conditions of a scale change

| Requirement | Guarantee |
|---|---|
| FR-004 / SC-005 | Scaling reads the original recipe file, never the previous scaled output |
| FR-026 | `RV_INGREDIENT_CHECKS` is untouched — the scale path must **not** call `rv_load_recipe`, which clears it |
| FR-027 | Ingredient scroll is re-anchored to the record index that was at the top of the pane; instruction scroll is not modified at all |
| FR-003 / SC-004 | Returning to index 0 rebuilds the layout from the original recipe file |
| SC-008 | Two partial regions, one `awk` fork; no full-screen refresh on the normal path |
