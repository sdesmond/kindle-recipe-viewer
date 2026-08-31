---
name: recipe-scaling-model
description: Recipe scaling design decisions and a POSIX read/IFS-tab bug found while building it.
metadata:
  type: project
  date: 2026-08-30
---

# Recipe scaling model

Implements the recipe-scaling feature
([spec](../../specs/001-recipe-scaling/spec.md)): a title-bar badge cycles
`1x -> 1 1/2x -> 2x -> 3x -> 1/2x -> 1x` and rescales ingredient amounts as
exact rationals, rendered as whole numbers, cookbook-natural conversions, or
an exact reduced fraction when no natural conversion exists.

## Critical: `read`/IFS-tab collapses consecutive empty fields

Discovered while adding layout-row column 9 (the `~`/`!` marker) to
`rv_draw_pane` in `ui.sh`. Confirmed under **both** bash and the Kindle's
actual `dash`:

```sh
printf '8\titem\ttext\t1\t293\t\t\t\t!\n' | IFS=$(printf '\t') read -r a b c d e f g h i
# i is empty -- "!" never arrives, even though it is clearly the 9th field
```

Tab is classified as an "IFS whitespace" character by POSIX regardless of
what `IFS` is explicitly set to. Runs of IFS-whitespace collapse into a
single delimiter and get trimmed from field edges — this applies even when
`IFS` contains *only* the tab character. A non-whitespace IFS character
(comma tested) does not have this problem and preserves empty fields
correctly. Capturing "the rest of the line" into a final catch-all `read`
variable does **not** help either — the leading tabs are consumed as
delimiter noise before the remainder is captured, so they never reach the
variable.

This had been a **latent** bug in this codebase: every existing consumer of
`IFS="$RV_TAB" read -r ...` (`rv_draw_pane`, `rv_manifest_load`,
`rv_render_list_body`, ...) only ever had empty fields as the *last*
column(s) with nothing meaningful after them, so the collapsing was
invisible — trimmed trailing empties still land correctly on the final
variable. It only surfaces when a **non-empty field follows one or more
empty fields** via `read`, which the new marker column (empty columns 6-8,
non-empty column 9 on an unlinked flagged/approximated ingredient) is the
first case in this codebase to trigger.

**Fix** (`rv_draw_pane` in `ui.sh`): re-delimit the layout file on a unit
separator (`\037`, never IFS whitespace) once per `rv_draw_pane` call via
`tr`, then `read` from that temp file instead of the original — not once
per row, which would add a fork to the per-row hot path FBInk cost model
cares about. One `tr` + one `rm` per pane draw is negligible next to the
~20+ FBInk forks a full redraw already costs.

**Lesson**: any *new* TSV column added to a shell `read`-consumed format
must be checked for this specifically if it can be non-empty while a column
before it can be empty. `awk -F'\t'` consumers (`rv_layout_hit`,
`rv_build_layout`) do not have this problem — only shell `read`/word
splitting does, because only they apply the IFS-whitespace collapsing rule.

## Design decisions worth remembering

- **Exact integer rationals, never floats.** The common-fraction set guides
  unit selection but is never a reason to round. Preserve an exact reduced
  fraction such as `1 1/6 oz` when no cookbook-natural conversion exists;
  demote `1/16 cup` to its exact `1 tablespoon` form and render `1/16 tsp`
  as `a pinch of`.
- **Promotion set is {1,2,4}, not the full {1,2,3,4,8} expressible set** —
  the single tunable knob. Forced by the counter-example: naively promoting
  whenever a larger unit is exactly expressible turns `1 teaspoon` at 2x
  into `2/3 tablespoon` instead of `2 teaspoons`, and lets `2 tablespoons`
  become `1/8 cup`. Restricting promotion to halves/quarters only fixes both
  while still promoting `4 tablespoons` at 2x to `1/2 cup`.
- **Promotion targets are a subset of the recognition ladder.** `us_volume`
  recognizes teaspoon/tablespoon/fl oz/cup/pint/quart/gallon (so a recipe
  that already writes "1 quart" parses and demotes correctly), but
  *promotes* only up to cup. Real cookbook recipes never call for a pint or
  quart even at 6+ cups; the literal FR-017 threshold (>= half the larger
  unit) would otherwise promote `2 cups` into `1 pint` and beyond, chasing
  through pint and quart because each successive threshold is still
  satisfied. `fl_oz` is excluded from demotion for the same
  cookbook-realism reason (`1/3 cup` demotes to `2 2/3 tablespoons`, never
  `5 1/3 fl oz`) even though it stays fully recognized when a recipe states
  it explicitly.
- Case-sensitive `t`/`T` (teaspoon/tablespoon); `c`/`C` both mean cup and are
  case-insensitive. Bare `ounce`/`oz` is weight; only `fl oz`/`fluid ounce`
  is volume.
- Parenthetical equivalents may also be a conservative `about` bare count:
  `about 2 stalks` and `about 1/2 of a large pepper` scale with the leading
  quantity and retain a grammatical count noun. Other numeric parentheticals,
  including `(1 large)`, still flag rather than being guessed.
- Alternatives are ingredient expressions, not a reason to abandon scaling:
  every concrete quantity in each `or` choice is scaled, including quantities
  joined by `and`, `+`, or `mixed with`. Relative `1 part + 1 part` formulas
  stay unchanged because their ratio is already supplied by the concrete
  quantity in the other choice. Parenthetical `or` choices are shielded while
  the outer quantity scales, then parsed as their own expression.
- Ingredient metadata must not be treated as an equivalent: oven temperatures,
  dimensions, percentages, and per-item package/size labels stay unchanged.
  Direct and parenthetical equivalents, compound amounts, trailing `about`/
  `enough for` measures, decimals, and Paprika Unicode fractions are all
  normalized and scaled as exact rationals instead.
- Text markers (`~`/`!` prepended inside the row's existing `rv_text` call)
  instead of a per-row drawn gutter mark — FBInk's ~100-200 ms per-invocation
  cost makes one extra `rv_rect` per flagged row measurably expensive across
  a recipe with several flagged lines.
- A factor of 1/1 is bypassed entirely by the caller in production
  (`rv_load_recipe`/`rv_apply_scale` read the original recipe file directly
  at index 0), but `rv_scale_ingredients` *also* guarantees identity when
  `mnum == mden` even if invoked directly — otherwise
  `tests/test_scaling.sh`'s direct-call SC-004 corpus check would be
  exercising a caller behavior it cannot see, not the scaler itself.

## On-device validation

Partially performed. The scale badge's FBInk word-wrap bug (see [the runtime
memory](kindle-paperwhite-2-runtime.md)) was found on an actual device and
the badge was widened in response (`RV_SCALE_BADGE_W` 120px -> 162px in
`core.sh`), but that fix itself has not yet been re-verified on device. See
`specs/001-recipe-scaling/quickstart.md` scenario 7 (SC-008: a scale change
should feel no slower than an ingredient-pane swipe) before considering this
feature fully validated. Deploy with `tools/deploy.ps1` first.
