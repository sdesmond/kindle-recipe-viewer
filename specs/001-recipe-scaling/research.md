# Phase 0 Research: Recipe Scaling

All Technical Context unknowns are resolved below. No `NEEDS CLARIFICATION`
remains.

Every decision was checked against the real corpus: the 19 compiled recipes in
`build/fake-kindle/extensions/RecipeViewer/library/`, ~200 unique ingredient
lines. Quoted example lines throughout are verbatim from that corpus.

---

## D1. Where scaling is computed

**Decision**: On the device, at runtime, as one additional POSIX `awk` pass
that rewrites ingredient record text before `rv_build_layout` wraps it.

**Rationale**:
- The spec's Assumptions section states the existing data is sufficient and
  that no change to the Paprika export format, the schema version (4), or the
  compiled library is required. Its Out of Scope section explicitly cites "a
  compiler change, a schema bump, and a full library re-export" as the cost
  that kept servings out. Pre-computing scaled variants at compile time would
  incur exactly that cost, for a feature the spec says does not need it.
- `awk` is already load-bearing on device: `rv_build_layout`,
  `rv_layout_hit`, `rv_filter_recipes`, and `rv_uid_ordinal` all run it in
  shipped code paths. Using it adds no new dependency and no new deployment
  risk.
- Cost is not the constraint. The runtime memory establishes that the draw
  phase dominates everything — every `fbink`/`eips` invocation costs
  ~100-200 ms because it re-detects the panel and reloads the TTF font, and
  even a minimal partial redraw is ~0.5-0.6 s. One extra `awk` fork over ~30
  ingredient lines is immaterial against that floor, which is what makes
  SC-008 reachable.

**Alternatives considered**:
- *Pre-compute all five factors in `tools/compile_paprika.py`* — moves the
  hard parsing to a testable host language, and makes the device runtime a
  column lookup. Rejected: requires a schema bump and full re-export, which
  the spec rules out; also multiplies library size ~5x and makes any parser
  fix require re-exporting rather than redeploying a script.
- *Pure POSIX `sh` arithmetic* — rejected: `sh` is integer-only, so the
  rational and unit-conversion arithmetic would need hand-rolled long
  division, and every ingredient line would cost several subshells. The
  runtime memory documents exactly this class of per-record forking as the
  cause of a previously-shipped latency bug.

---

## D2. Numeric representation

**Decision**: Exact integer rationals — every amount is a
`numerator / denominator` pair of integers carried through parsing, scaling,
and unit conversion. No floating-point value ever reaches a comparison or a
rendering decision.

**Rationale**:
- FR-016 defines a *closed set* of displayable fractions. With rationals,
  "expressible" is the exact predicate `reduced denominator is in {1,2,3,4,8}`.
  With floats it becomes a tolerance comparison, and tolerance is precisely
  what produces the "0.6666666 cup" failure the spec calls out as making the
  feature worse than doing the arithmetic by hand.
- FR-004 and SC-005 demand that repeated scale changes never accumulate
  error and that 2x-then-1/2x-then-3x equals 3x applied once. Scaling always
  from the original text with exact arithmetic makes this true by
  construction, not by luck of rounding.
- Magnitudes are tiny. The largest denominator the corpus can produce is a
  few hundred after unit conversion; `awk`'s doubles represent integers
  exactly far past that, so integer-valued doubles are a safe carrier.

**Alternatives considered**:
- *Doubles with epsilon comparison* — rejected as above; also makes
  SC-002 ("zero fractions outside the common set, across the whole library")
  unprovable rather than merely untested.
- *Fixed-point in twenty-fourths* (LCM of 1,2,3,4,8) — attractive, but
  breaks on unit conversion: 1 tsp = 1/48 cup, and 48 does not divide 24.
  Rationals subsume it without the special case.

---

## D3. Unit families, and the ambiguous unit tokens in this corpus

**Decision**: Five closed families, each an integer-factor ladder over a base
unit. Amounts convert only within their own family (FR-019).

| Family | Ladder (factor in base units) |
|---|---|
| US volume (base: teaspoon) | teaspoon 1, tablespoon 3, fluid ounce 6, cup 48, pint 96, quart 192, gallon 768 |
| US weight (base: ounce) | ounce 1, pound 16 |
| Metric volume (base: millilitre) | millilitre 1, litre 1000 |
| Metric weight (base: gram) | gram 1, kilogram 1000 |
| Count (no unit) | single rung; no promotion or demotion |

Two token ambiguities in this corpus must be resolved deliberately:

1. **`t` vs `T` is case-significant.** The corpus contains both
   `1/4 t dried ginger` (teaspoon) and `1 T sesame oil`, `2 1/2 T soy sauce`
   (tablespoon). Single-letter unit tokens are therefore matched
   **case-sensitively**: `t` = teaspoon, `T` = tablespoon. `c` and `C` both
   mean cup (`1 C onion`, `1/2 C carrot`) with no competing meaning, so those
   stay case-insensitive. Every multi-letter token (`tsp`, `Tbsp.`, `cup`,
   `oz`, `lb.`) is matched case-insensitively.
2. **Bare `ounce`/`oz` is weight, not volume.** Every bare-ounce line in the
   corpus is a weight (`8 ounces whole-milk mozzarella cheese`,
   `16 ounce (2 cups) ricotta cheese`, `12 ounces pasta`). Only an explicit
   `fl oz` / `fluid ounce` enters the US-volume family. This matters: reading
   `8 ounces` as fluid ounces would let it promote into cups and produce a
   wrong amount presented as correct.

**Alternatives considered**: a single unified ladder with a
volume-to-weight bridge (density) — rejected outright by FR-019 and by the
fact that density is ingredient-specific and unavailable in the record format.

---

## D4. When to change the unit (FR-017 / FR-018)

FR-017 as literally written — "promote when the result is at least half of
the larger unit and is expressible" — does not survive contact with the
corpus. Counter-example: `1 teaspoon` at 2x is 2 tsp, which is at least half a
tablespoon (1.5 tsp) and 2/3 is expressible, so the literal rule yields
"2/3 tablespoon" where every cookbook writes "2 teaspoons". FR-018 forbids
rewriting into a unit that reads less naturally, so the two requirements have
to be reconciled by a stricter promotion test.

**Decision**: Promote to the next larger unit only when **both** hold:
1. the amount is at least half of that larger unit (FR-017's stated
   threshold), **and**
2. the amount expressed in the larger unit is exactly expressible with a
   reduced denominator in **{1, 2, 4}** — halves and quarters only, not
   thirds and not eighths.

Repeat up the ladder and take the largest qualifying unit. Demotion is the
mirror: if the amount is not exactly expressible (denominator in {1,2,3,4,8})
in its current unit, step **down** one rung at a time and take the first unit
where it is.

Validation against every unit case the spec names, plus the counter-examples:

| Input | Scale | Result | Why |
|---|---|---|---|
| 1 teaspoon | 3x | **1 tablespoon** | 3 tsp = 1 tbsp, denominator 1 → promote (FR-017 ex.) |
| 1 teaspoon | 2x | **2 teaspoons** | 2/3 tbsp has denominator 3 → blocked (fixes the counter-example) |
| 4 tablespoons | 2x | **1/2 cup** | 24 tsp = 1/2 cup, denominator 2 → promote (FR-017 ex.) |
| 2 tablespoons | 1x | **2 tablespoons** | 1/8 cup has denominator 8 → blocked (FR-018's own example) |
| 1/3 cup | 1/2x | **2 2/3 tablespoons** | 1/6 cup not expressible → demote; 8/3 tbsp is → stop (FR-017 ex.) |
| 8 ounces | 2x | **1 pound** | 16 oz = 1 lb, denominator 1 → promote (US story 2, scenario 4) |
| 8 ounces | 1/2x | **4 ounces** | 4 oz < half a pound → threshold blocks promotion |
| 400g | 2x | **800g** | 800/1000 kg = 4/5, not expressible → stays metric grams (FR-019) |

**Alternatives considered**:
- *Promote purely on "simplest denominator wins"* — rejected: 8 tbsp
  (denominator 1) would beat 1/2 cup (denominator 2), contradicting the
  spec's named case.
- *Promote whenever the amount reaches one full larger unit* — rejected:
  8 tablespoons is only half a cup and would never become "1/2 cup".
- *Widen the promotion set to {1,2,3,4,8}* — rejected: reintroduces
  "2/3 tablespoon" and "1/8 cup", the two forms FR-018 exists to prevent.

The {1,2,4} promotion set is the single tunable knob in this design and is
called out as such in the data model, since it is the one rule most likely to
need adjustment once a cook uses it against a wider library.

---

## D5. Which parts of a line are scaled

**Decision**: A line is scaled only if the parser can account for **every**
numeric quantity in it. Concretely, exactly three things are scaled:

1. the **leading amount** (optionally preceded by one of a short allowlist of
   qualifiers: `heaping`, `scant`, `about`, `pinch of`, `zest of`, `juice of`),
2. a **parenthesized equivalent** anywhere in the line that parses cleanly as
   an optional `about` plus an amount plus a known unit — `(236 ml)`,
   `(450 grams)`, `(2 cups)`, `(12 ounces)`, `(60-70 g)`, `(about 2 cups)`,
3. the **leading count only**, when the line is a package or container
   (FR-010), leaving the package size untouched.

Everything else that is not an amount is carried through byte-for-byte
(FR-023).

**Rationale**: FR-012 offers two acceptable outcomes for a line that states a
quantity twice — scale both consistently, or scale neither and flag. Flagging
every line with a parenthesized equivalent would flag ~20 of ~200 corpus
lines, including very ordinary ones (`1 cup (236 ml) whole milk`,
`1 lb (450 grams) spaghetti`, `2 tbsp. (30 g) unsalted butter`), which is a
poor result for the most common shape in the corpus. Taking FR-012's first
branch for the well-formed case and its second branch for everything else
gets the common case right without ever risking a half-rewritten line
(FR-025).

Bare mid-line numbers need no special handling and get none: because only the
leading amount and qualifying parenthesized groups are touched, `93% lean`,
`80% lean`, and any temperature or time in an ingredient note are untouched
automatically, satisfying FR-011 without a percentage rule.

---

## D6. When a line is flagged instead of scaled

**Decision**: A line is flagged (left in its exact original wording, marked
for manual attention) when it contains a scalable leading amount **and** any
of:

- a parenthesized group containing a digit that does **not** parse as a clean
  amount + known unit — `(1 large)` in `1 cup chopped onion (1 large)`,
  `(or 8 cups chopped spinach)`, `(or 3 fresh chilis)`;
- ` or ` followed by an amount — `1 dried bay leaf or 2 fresh`,
  `1 15-ounce container ricotta cheese or 2 cups cream-style cottage cheese`;
- `plus` followed by an amount —
  `1/4 cup DeLallo extra virgin olive oil , plus 1 tablespoon`;
- a trailing restatement introduced by `enough for` / `about` outside
  parentheses — `1 small head cauliflower (1 1/2 to 2 pounds), enough for 6
  cups florets` (also the spec's own story-3 example).

A line with **no** scalable amount at all is left unchanged and is **not**
flagged (FR-013): `Salt and pepper`, `Pinch of salt`, `Fresh thyme`,
`salt, to taste`. Section headers are never scaled and never flagged (FR-014).

**Rationale**: This is the direct expression of FR-025 — a line is scaled in
full or not at all. The trigger list is derived from the corpus rather than
invented, so it is testable against a fixed set of known lines rather than
being open-ended.

`plus <amount>` is deliberately flagged rather than scaled even though the
second amount is arguably part of the same total. Only one corpus line has
this shape, and scaling a second independent quantity is a materially
different operation from scaling an equivalent restatement; flagging it is
correct today and can be revisited with evidence.

---

## D7. Equipment and cookware (FR-011)

**Decision**: Track the current ingredient-list section header while scanning
records in order. Items under a header matching `equipment` (case-insensitive)
are never scaled and never flagged. As a second, independent guard, a line
whose noun is cookware (`pan`, `pot`, `skillet`, `dish`, `sheet`, `oven`) is
also left alone.

**Rationale**: The corpus contains a literal `EQUIPMENT` section header
followed by `5 Quart Sauce Pan`. `Quart` is a real unit on the US-volume
ladder, so without section awareness a doubled batch would confidently
announce a 10-quart pan — one of the exact failures FR-011 exists to prevent.
Records already arrive in file order in the same `awk` pass that scales them,
so header tracking costs nothing extra. The cookware noun list is the belt to
the section header's braces, for a library whose author did not use an
EQUIPMENT section.

---

## D8. Presenting "scaled", "approximate", and "needs attention"

**Decision**:
- **Active factor (FR-005, FR-031)**: a bordered badge in the cook screen's
  title bar, right-aligned, always drawn, showing the current label
  (`1/2x`, `1x`, `1 1/2x`, `2x`, `3x`). The title bar sits above both panes,
  so it is visible while reading instructions, which is what FR-031 requires.
- **Flagged line (FR-024)**: a `!` marker prefixed to the item's **first
  wrapped row only**, added by the layout builder, not by the scaler.
- **Approximated amount (FR-020)**: a `~` marker in the same position.

**Rationale**: The obvious alternative — a drawn gutter mark per flagged row,
mirroring the existing instruction cursor rect — costs one extra `rv_rect`,
and therefore one extra FBInk process at ~100-200 ms, *per flagged row*. On a
recipe with five flagged lines that is up to a full second added to every
redraw of the pane, against a documented ~0.5-0.6 s floor. A text marker rides
inside the `rv_text` call the row already makes and costs nothing.

Placing the marker in the layout builder rather than in the scaler keeps the
scaled record text pure — it stays exactly what the cook is meant to read —
so the corpus tests can assert on real ingredient text without stripping
presentation characters first.

**Alternatives considered**:
- *Bold the flagged row* — free (the style argument already exists), but bold
  is how section headers render in the same pane, so a flagged item would read
  as a heading.
- *Append "(scale by hand)"* — rejected: the ingredient pane is 300 px wide;
  this would add a wrapped line to every flagged item.
- *A legend under the "Ingredients" pane header* — will not fit in 300 px at
  13 pt alongside the header text. Noted as a possible follow-up if cooks find
  `!` unclear in use.

---

## D9. How the cook changes the scale

**Decision**: Tapping the title-bar badge advances to the next factor in a
wrapping ladder: `1x -> 1 1/2x -> 2x -> 3x -> 1/2x -> 1x`. The badge is both
the indicator and the control.

**Rationale**: SC-001 requires changing scale "in a single interaction,
without navigating away from the recipe and without losing their place in
it". A tap-to-cycle badge is literally one interaction and never leaves the
cook screen. `1x` is on the ladder, so the original amounts are always at most
four taps away and the cook can never get stranded (FR-003).

The ladder starts at `1 1/2x` rather than `1/2x` because scaling up is the
more common intent, making the most likely next factor one tap away.

**Alternatives considered**:
- *A modal picker screen*, mirroring the existing `rv_draw_confirm` pattern —
  better for jumping directly to any factor and more self-describing, but it
  costs two full-screen refreshes and does navigate away from the recipe, which
  SC-001 rules out. This is the fallback if cycling proves annoying in use.
- *A long-press gesture* — rejected outright: the runtime memory records that
  `rv_classify_gesture`'s `hold` branch requires an 800 ms dwell while the
  capture window is bounded at `RV_TOUCH_POLL_SECONDS` (0.5 s), making `hold`
  unreachable outside a replay fixture. Building an affordance on it would
  ship a dead control.

---

## D10. Redraw strategy for a scale change

**Decision**: A scale change redraws **two partial regions** — the badge box
in the title bar and the ingredient pane — with `GC16`, the same waveform a
pane scroll already uses. The instruction pane is never rebuilt or redrawn.

**Rationale**: SC-008 pegs the budget to "no more slowly than scrolling the
ingredient pane does today", which rules out the simpler full
`rv_draw_cook`. Two partial regions add one extra clear/refresh pair
(~2-3 FBInk calls, ~0.3 s) over a pane scroll, landing inside the budget.
Never touching the instruction layout is also what makes SC-010 (instruction
text byte-identical at every factor) true by construction rather than by
assertion — the instruction layout file is built once at recipe load and is
never regenerated on a scale change.

At `1x` the scaler is bypassed entirely and `rv_build_layout` reads the
original recipe file, so FR-003 and SC-004 (returning to 1x reproduces the
original text exactly) hold trivially rather than depending on round-tripping
the parser.

---

## D11. Preserving progress across a scale change (FR-026, FR-027)

**Decision**:
- **Checks**: keyed by ingredient *record index* (the Nth `INGREDIENT` record),
  which scaling never adds to, removes from, or reorders. Preserved by not
  resetting them: the scale change path must be a new narrow function, **not**
  `rv_load_recipe`, which deliberately clears `RV_INGREDIENT_CHECKS`,
  cursors, and both scroll positions.
- **Reading position**: anchored by record index, not row index. Before
  rescaling, resolve which ingredient record the current scroll position sits
  on; after rebuilding the layout, set the scroll to that record's first
  wrapped row, then clamp.

**Rationale**: Scaled text changes how lines wrap — "1 tablespoon" becoming
"2 2/3 tablespoons" can add a row — so row indices are not stable across a
scale change and a naive scroll carry-over would drift. Record indices are
stable, which is also why the existing check mechanism already works this way
(`rv_toggle_check` stores record indices, and the runtime tests assert that
two ingredients with identical text do not share a check).

---

## D12. Testing approach

**Decision**: Three layers.

1. **Scaler unit tests** (`tests/test_scaling.sh`): source `lib/scale.sh` and
   assert exact output for each rule in D4-D7, including every example the
   spec names and every counter-example found in D4.
2. **Corpus sweep** (same file): run every line of a committed corpus fixture
   through all five factors and assert the success criteria mechanically —
   SC-002 (no decimals, no fraction outside the closed set), SC-004 (1x is
   byte-identical), SC-005 (path independence: 2x then 1/2x then 3x equals 3x),
   SC-006 (no package size altered), SC-007 (every line scaled or flagged, none
   silently untouched).
3. **Integration/geometry tests** (`tests/test_runtime.sh`): badge draw
   coordinates, badge tap dispatch, the scale-change partial refresh regions,
   check and scroll preservation.

**Corpus fixture**: the sample library under `build/` is generated and
gitignored, so a corpus test that depended on it would silently pass as a
no-op in a clean clone. A committed `tests/fixtures/scaling-corpus.tsv` of the
real unique ingredient lines is the primary input; the sweep additionally
runs over the generated library when it happens to be present.

**Rationale**: The success criteria are written as library-wide properties
("across every ingredient line in the sample library"), so they want a sweep,
not a handful of examples. Making the corpus a committed fixture is what makes
the sweep meaningful rather than conditional.

**Also required by project rules**: `dash -c` sanity checks on any new shell
syntax before deploying. The runtime memory records that this codebase has
already shipped one hard crash from `$((16#ff))` — valid in bash, a fatal
parse error in the device's `dash` — so this is a real, evidenced check rather
than a formality. The design keeps all arithmetic inside `awk` specifically to
minimize exposure here.
