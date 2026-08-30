# Contract: Scaled Ingredient Record

**Producer**: `rv_scale_ingredients` (`extensions/RecipeViewer/lib/scale.sh`)
**Consumer**: `rv_build_layout` (`extensions/RecipeViewer/lib/ui.sh`)
**Location**: `$RV_TMP/ingredients.scaled`
**Encoding**: ASCII, LF line endings, tab-separated. Never sourced as shell.

## Invocation

```sh
rv_scale_ingredients <recipe-file> <scale-num> <scale-den> <output-file>
```

Reads the `INGREDIENT` records of `<recipe-file>` in file order and writes one
output record per input record. Exit status is 0 on success; a non-zero status
means the caller must fall back to the unscaled recipe file and log the
failure — it must never render a partially written file.

At scale `1/1` the function is **not called**: `rv_build_layout` reads the
original recipe file directly. This is what makes FR-003/SC-004 exact rather
than dependent on the parser round-tripping its own input.

## Columns

| # | Name | Values | Notes |
|---|---|---|---|
| 1 | record type | `INGREDIENT` | literal, so the file is drop-in for `rv_build_layout -v wanted=INGREDIENT` |
| 2 | kind | `item` \| `section-header` | copied verbatim from the source record |
| 3 | text | display text | scaled text, or the source text byte-for-byte when the classification is `unchanged` or `flagged` |
| 4 | link uid | uid or empty | copied verbatim; scaling never creates, destroys, or alters a link |
| 5 | reserved | always empty | `rv_build_layout` reads column 5 as an instruction link phrase; it **must** stay empty here or ingredient rows will be mis-hit-tested |
| 6 | flag | empty \| `approx` \| `flag` | drives the layout marker |

## Guarantees

1. **Record count and order are preserved.** Output line *N* corresponds to
   input `INGREDIENT` record *N*. Ingredient checks are keyed by this index
   (FR-026), so violating this silently corrupts a cook's progress.
2. **No field contains a tab or a newline.** Source records are already
   whitespace-squeezed by `tools/compile_paprika.py::_record_field`; the
   scaler must not introduce either.
3. **Column 3 never contains a decimal point in a scaled amount** (FR-015).
   A decimal may still appear in text the scaler passed through untouched —
   for example the package size in `3 (4.3 oz) packages dry ramen`.
4. **Column 3 never contains a fraction outside `1/2 1/3 2/3 1/4 3/4 1/8 3/8
   5/8 7/8`** in an amount the scaler wrote (FR-016). As above, an untouched
   package size is exempt.
5. **`flag` implies column 3 equals the source text exactly.** A flagged line
   is never partially rewritten (FR-025).
6. **`section-header` rows always carry an empty flag** and unmodified text
   (FR-014).
7. **Idempotent in the factor, not in the file.** The scaler is always applied
   to the original recipe file. It is never valid to feed a scaled file back
   in (FR-004).

## Worked examples

Source column 3 → output column 3 (flag in parentheses when non-empty):

| Source | 2x | 1/2x |
|---|---|---|
| `1 cup whole milk` | `2 cups whole milk` | `1/2 cup whole milk` |
| `1 1/2 cups whole milk` | `3 cups whole milk` | `3/4 cup whole milk` |
| `1/2 teaspoon salt` | `1 teaspoon salt` | `1/4 teaspoon salt` |
| `1 teaspoon garlic powder` | `2 teaspoons garlic powder` | `1/2 teaspoon garlic powder` |
| `4 tablespoons butter` | `1/2 cup butter` | `2 tablespoons butter` |
| `1/3 cup pine nuts` | `2/3 cup pine nuts` | `2 2/3 tablespoons pine nuts` |
| `8 ounces elbow macaroni` | `1 pound elbow macaroni` | `4 ounces elbow macaroni` |
| `3 green onions, chopped` | `6 green onions, chopped` | `1 1/2 green onions, chopped` |
| `1-2 cups quality chicken stock` | `2-4 cups quality chicken stock` | `1/2-1 cup quality chicken stock` |
| `400g '00' flour (plus more for work surface)` | `800g '00' flour (plus more for work surface)` | `200g '00' flour (plus more for work surface)` |
| `1 cup (236 ml) whole milk` | `2 cups (472 ml) whole milk` | `1/2 cup (118 ml) whole milk` |
| `1 (28-oz) Can Diced Tomatoes` | `2 (28-oz) Cans Diced Tomatoes` | *(flag)* `1 (28-oz) Can Diced Tomatoes` |
| `1 cup chopped onion (1 large)` | *(flag)* unchanged | *(flag)* unchanged |
| `1 small head cauliflower (1 1/2 to 2 pounds), enough for 6 cups florets` | *(flag)* unchanged | *(flag)* unchanged |
| `5 Quart Sauce Pan` | unchanged, no flag | unchanged, no flag |
| `Salt and pepper` | unchanged, no flag | unchanged, no flag |
| `Pinch of salt` | unchanged, no flag | unchanged, no flag |
| `1/8 teaspoon garlic powder` | `1/4 teaspoon garlic powder` | *(approx)* `1/8 teaspoon garlic powder` |

Notes on the last rows:
- `1 (28-oz) Can` at 1/2x is half a can. There is no `1/2 can` a cook can buy,
  so the halved package count is flagged rather than rendered.
- `1/8 teaspoon` at 1/2x is 1/16 tsp: not expressible, and there is no smaller
  US-volume rung to demote to. The nearest expressible value is 1/8, so the
  amount is presented unchanged and marked approximate (FR-020) — the spec's
  "amounts too small to express" edge case.
