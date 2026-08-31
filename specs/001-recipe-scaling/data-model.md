# Phase 1 Data Model: Recipe Scaling

Entities are given as they exist in the runtime: shell variables, TSV record
columns, and `awk`-local structures. Nothing here is persisted to the device.

---

## 1. Scale Factor

The multiplier applied to the open recipe. Session-scoped; one value at a time,
drawn from a closed ladder (FR-002, FR-029).

| Field | Carrier | Notes |
|---|---|---|
| index | `RV_SCALE_INDEX` | 0-based position in the ladder |
| numerator | `RV_SCALE_NUM` | integer |
| denominator | `RV_SCALE_DEN` | integer, never 0 |
| label | `RV_SCALE_LABEL` | text drawn in the badge |

**Ladder** (cycle order, wrapping — D9):

| index | num/den | label | is original |
|---|---|---|---|
| 0 | 1/1 | `1x` | yes |
| 1 | 3/2 | `1 1/2x` | |
| 2 | 2/1 | `2x` | |
| 3 | 3/1 | `3x` | |
| 4 | 1/2 | `1/2x` | |

**Rules**
- Reset to index 0 by `rv_reset_session` and by `rv_load_recipe`, so opening a
  different recipe or ending the current one returns to the original amounts
  (FR-006, story 4 scenario 3).
- Index 0 is a bypass, not a computation: the layout is built from the original
  recipe file, guaranteeing exact original text (FR-003, SC-004).
- Never persisted (spec Assumptions; Out of Scope).

**State transitions**: the only transition is `index -> (index + 1) mod 5`,
triggered by a badge tap. There is no other way to reach a scale factor.

---

## 2. Rational Value

The internal representation of every amount (D2). Exists only inside the `awk`
scaling pass; never crosses a process boundary as a decimal.

| Field | Type | Notes |
|---|---|---|
| num | integer | may be 0; never negative in valid input |
| den | integer | always > 0; kept reduced by `gcd` after every operation |

**Operations**
- `multiply(a, b)` — `num = a.num * b.num`, `den = a.den * b.den`, then reduce.
- `reduce(v)` — divide both by `gcd`.
- `compare(a, b)` — cross-multiply; never subtract-and-test-a-float.
- `is_expressible(v)` — true when the reduced `den` is in **{1, 2, 3, 4, 8}**.
  It guides cookbook-natural unit selection; it does not authorize rounding.
- `is_promotable(v)` — true when the reduced `den` is in **{1, 2, 4}**.
  This narrower set is the promotion gate (D4) and is the design's single
  tunable knob.
- When no common-fraction unit form exists, the renderer preserves the exact
  reduced rational (for example, `1 1/6 ounces`) rather than choosing a
  nearby amount.

**Validation**
- `den == 0` is a parse failure, not a value: the line is flagged.
- A parsed value must be > 0. A leading `0` amount is treated as unparseable.

---

## 3. Unit

A token in the ingredient text that names a measure.

| Field | Carrier | Notes |
|---|---|---|
| token | the literal source text | preserved verbatim when the unit does not change (FR-021) |
| canonical | family rung id | e.g. `us_volume:tablespoon` |
| family | one of 5 | `us_volume`, `us_weight`, `metric_volume`, `metric_weight`, `count` |
| factor | integer | rung value in the family's base unit |
| style | `abbrev` \| `spelled` | decides how a *changed* unit is written |
| plural form | derived | spelled-out units only |

**Ladders** (D3):

| Family | Rungs, base-unit factor |
|---|---|
| `us_volume` (base teaspoon) | teaspoon 1, tablespoon 3, fluid ounce 6, cup 48, pint 96, quart 192, gallon 768 |
| `us_weight` (base ounce) | ounce 1, pound 16 |
| `metric_volume` (base millilitre) | millilitre 1, litre 1000 |
| `metric_weight` (base gram) | gram 1, kilogram 1000 |
| `count` | single rung, factor 1 |

**Token matching rules**
- Single-letter tokens are **case-sensitive**: `t` = teaspoon,
  `T` = tablespoon, `c`/`C` = cup. Driven by real corpus lines
  (`1/4 t dried ginger` vs `1 T sesame oil`).
- All multi-letter tokens are case-insensitive, with or without a trailing
  period: `tsp`, `tsp.`, `Tbsp.`, `TBS`, `oz`, `lb.`, `lbs`, `Cup`, `Cups`.
- Bare `ounce`/`oz` is **weight**. Only `fl oz` / `fluid ounce` is volume.
- An unrecognized token is not a unit: the amount belongs to the `count`
  family and the token is ordinary text carried through unchanged.

**Style and pluralization (FR-021, FR-022)**
- Unit unchanged → emit the original token verbatim, adjusting only its
  plural suffix when the token is spelled out.
- Unit changed (promotion/demotion) → emit the canonical spelling of the new
  rung, matching the original's style: an abbreviated source yields an
  abbreviated target, a spelled-out source yields a spelled-out target.
- Plural iff value > 1 (`1 1/2 cups`, `1/2 cup`, `2 cups`, `1 cup`).
  Abbreviations are not pluralized.
- **Only known unit words are pluralized.** A following non-unit noun is never
  touched, because `1 large egg` at 2x would otherwise pluralize the adjective
  `large`. This is FR-022's own "where the recipe's own wording makes that
  adjustment unambiguous" clause. Known consequence, accepted: `2 potatoes` at
  1/2x renders `1 potatoes`. Cosmetic, never a wrong quantity.

---

## 4. Measured Amount

One quantity located within an ingredient line.

| Field | Type | Notes |
|---|---|---|
| low | Rational | the value, or the lower endpoint of a range |
| high | Rational \| none | upper endpoint when the amount is a range (FR-009) |
| unit | Unit | may be the `count` rung |
| role | enum | see below |
| span | (start, end) offsets | the exact source characters this amount occupies |
| separator | text | for ranges: the literal `-` or ` to ` as written |

**Roles** (only the first two are ever scaled):

| Role | Meaning | Scaled? |
|---|---|---|
| `quantity` | the amount of the ingredient to use | yes |
| `equivalent` | the same quantity restated in another unit, in parentheses | yes, in its own family |
| `package` | the size the ingredient is sold in (`28-oz`, `4.3 oz`, `15-ounce`) | **never** (FR-010) |
| `non-quantity` | percentage, equipment size, time, temperature | **never** (FR-011) |

**Accepted written forms** (FR-007, FR-009), all present in the corpus:

| Form | Example |
|---|---|
| whole | `2 cups all-purpose flour` |
| common fraction | `1/2 teaspoon salt` |
| mixed number | `1 1/2 cups whole milk` |
| bare count, no unit | `3 green onions, chopped` |
| parenthetical bare-count equivalent | `1/2 c. celery (about 2 stalks)`, `1/2 c. pepper (about 1/2 of a large pepper)`, `1/2 cup (1 stick) butter` |
| alternative expression | `1/4 tsp garlic powder or 2 cloves`; every concrete quantity in every choice scales independently. Relative ratios such as `1 part + 1 part` stay unchanged. |
| compound amount | `1/2 cup plus 2 tablespoons`; every concrete ingredient amount scales, while temperatures, dimensions, percentages, and per-item labels remain unchanged. |
| hyphen range | `1-2 cups quality chicken stock` |
| word range | `10 to 12 lasagna noodles` |
| metric, unit joined to digits | `400g '00' flour`, `400ml warm water` |
| leading qualifier | `Heaping 1/4 cup tomato paste`, `Zest of 1/2 lemon` |

**Range rule**: both endpoints scale, and both are rendered in **one** shared
unit — the unit chosen for the upper endpoint — so a range never reads
`1 cup - 2 cups` or mixes rungs.

---

## 5. Ingredient Line Classification

The outcome of interpreting one `INGREDIENT` record. Exactly one of:

| Classification | Emitted text | Marker | Requirement |
|---|---|---|---|
| `scaled` | rewritten amounts, all other text byte-identical | none | FR-007, FR-023 |
| `approx` | rewritten, with an amount rounded to the nearest expressible value | `~` | FR-020 |
| `unchanged` | original text | none | FR-013 (nothing to scale — never flagged) |
| `flagged` | original text | `!` | FR-024, FR-025 |

**Flag triggers** (D6) — a line with a scalable leading amount that also has
any of:
- a parenthesized group containing a digit that does not parse as a clean
  amount + known unit, supported `about` bare-count equivalent, or defined
  stick count (`(1 large)`, `(or 8 cups chopped spinach)`);
- an `or` expression that contains an amount the parser cannot interpret;
- `plus` followed by an amount (`... olive oil , plus 1 tablespoon`);
- an unparenthesized trailing restatement (`..., enough for 6 cups florets`).

**Never-scale, never-flag**: `section-header` records (FR-014); items under an
`EQUIPMENT` section header; lines whose noun is cookware (D7); lines with no
amount at all (`Salt and pepper`, `Pinch of salt`, `salt, to taste`).

**Package rule** (FR-010): when the line contains a container noun — `can`,
`cans`, `package`, `packages`, `container`, `containers`, `jar`, `box`, `bag`,
`bottle`, `tub` (and plurals) — only the leading count scales; every other
number in the line keeps its written value. The count can be fractional:
`1 (28-oz) Can Diced Tomatoes` at 1.5x becomes `1 1/2 (28-oz) Cans Diced
Tomatoes`.

---

## 6. Scaled Ingredient Record

The scaler's output file, `$RV_TMP/ingredients.scaled`. Same shape as the
`INGREDIENT` records in a `.recipe` file so `rv_build_layout` consumes it
unchanged, plus one appended column. Full column definitions live in
[`contracts/scaled-ingredient-record.md`](./contracts/scaled-ingredient-record.md).

| Col | Name | Notes |
|---|---|---|
| 1 | `INGREDIENT` | literal record type |
| 2 | kind | `item` or `section-header`, copied through |
| 3 | text | scaled display text, or the original when unchanged/flagged |
| 4 | link uid | copied through unchanged — scaling never affects links |
| 5 | *(reserved, always empty)* | `rv_build_layout` reads column 5 as a link phrase; it must stay empty for ingredients |
| 6 | flag | empty, `approx`, or `flag` |

Record order and count are identical to the source, which is what keeps
ingredient checks valid across a scale change (FR-026).

---

## 7. Layout Row (extended)

`rv_build_layout`'s existing 8-column output gains a 9th column carrying the
classification marker, applied to an item's **first wrapped row only**. Full
definition in [`contracts/layout-row.md`](./contracts/layout-row.md).

| Col | Name | Change |
|---|---|---|
| 1-8 | record index, kind, text, first, measured width, link uid, link prefix width, link phrase width | unchanged |
| 9 | marker | **new**: empty, `~`, or `!` |

Consumers to update: `rv_draw_pane`'s `read` (add the ninth variable, prepend
the marker when non-empty) and `rv_layout_hit`'s `awk` (ignores column 9, but
its field count is asserted by the golden tests).

---

## 8. Session Scroll Anchor

Transient, used only across a scale change (FR-027, D11).

| Field | Carrier | Notes |
|---|---|---|
| anchor record | `RV_SCALE_ANCHOR_RECORD` | ingredient record index at the top of the pane before rescaling |
| resulting scroll | `RV_INGREDIENT_SCROLL` | first wrapped row of that record in the new layout, clamped to `RV_INGREDIENT_MAX_SCROLL` |

Derived, never stored across recipes, and recomputed on every scale change.
Row indices are deliberately **not** carried across, because rewrapping changes
them.

---

## 9. Relationships

```text
Scale Factor (1 per session)
    │ applied to
    ▼
Ingredient Record (N per recipe, order and count fixed)
    │ interpreted as
    ▼
Measured Amount (0..M per record, each with a role)
    │ role=quantity|equivalent → scaled via Rational × Scale Factor
    │ then re-homed on a Unit ladder within its own family
    ▼
Ingredient Line Classification (exactly 1 per record)
    │ rendered into
    ▼
Scaled Ingredient Record  ──rv_build_layout──▶  Layout Row (1..K per record)
                                                    │
                                                    ▼
                                              drawn by rv_draw_pane

Ingredient Check (keyed by record index) ── unaffected by any of the above
Instruction Record ──────────────────────── never enters this pipeline (FR-030)
```

**Invariants**
1. Record count and order are identical before and after scaling — this is what
   makes checks (FR-026) survive.
2. Scaling always reads the **original** recipe file, never a previously scaled
   file (FR-004, SC-005).
3. The instruction layout is built once per recipe load and is never rebuilt on
   a scale change (FR-030, SC-010).
4. At factor `1x` the scaler does not run at all (FR-003, SC-004).
