---

description: "Task list for Recipe Scaling"
---

# Tasks: Recipe Scaling

**Input**: Design documents from `specs/001-recipe-scaling/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Test tasks ARE included. The spec's success criteria are written as
library-wide mechanical properties ("across every ingredient line in the sample
library"), research decision D12 designs the three-layer test approach, and
`quickstart.md`'s Definition of Done requires all three suites to pass. This is
not speculative TDD — it is the stated acceptance mechanism.

**Organization**: Tasks are grouped by user story. Each story phase ends at a
checkpoint that is deployable and independently testable on the device.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Every task names its exact file path

## Path Conventions

Device runtime: `extensions/RecipeViewer/lib/`, `extensions/RecipeViewer/bin/`.
Tests: `tests/`. Fixtures: `tests/fixtures/`. Memories: `.agents/memories/`.
Paths are repo-relative, per plan.md's Project Structure.

## Critical constraints (apply to every runtime task)

- POSIX `sh` only on device; **never** `base#value` arithmetic — it is a fatal
  parse error under the device's `dash` and has already shipped one crash.
  Keep all arithmetic inside `awk`.
- Data files are parsed as records, never sourced as shell.
- Each `fbink`/`eips` invocation costs ~100-200 ms. Never add a drawing call
  per row.
- `tools/compile_paprika.py` and schema 4 must remain untouched.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test corpus and harness in place before any runtime code is written

- [X] T001 [P] Create `tests/fixtures/scaling-corpus.tsv` holding the unique ingredient lines of the sample library, one per row, as `kind<TAB>text` (`item` or `section-header`); source them with `awk -F'\t' '$1=="INGREDIENT" {print $2 "\t" $3}' build/fake-kindle/extensions/RecipeViewer/library/*.recipe | sort -u`, and commit the file with LF endings so the sweep runs in a clean clone where `build/` is gitignored
- [X] T002 [P] Create `tests/test_scaling.sh` skeleton (bash, `set -euo pipefail`) mirroring `tests/test_runtime.sh`'s conventions: source `extensions/RecipeViewer/lib/scale.sh`, provide `assert_eq`/`assert_scaled`/failure counter, and dispatch `--only units` / `--only corpus` / no-arg (both)
- [X] T003 [P] Add scaling fixture cases to `tests/fixtures/library/0002.recipe`: one plain scalable ingredient, one range, one package line, one no-amount line, plus an `EQUIPMENT` section header with a cookware item — and update the `RV_INGREDIENT_ROWS`/layout-offset assertions in `tests/test_runtime.sh` that the added records shift
- [X] T004 [P] Add a `dash -n` syntax gate covering all four runtime scripts to `tests/test_runtime.sh` (skipped with a printed notice when `dash` is absent), per quickstart.md's device-shell gate

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Stand up the whole scale pipeline end to end with **zero change to
any ingredient text**. The badge cycles, the label changes, the ingredient
layout is rebuilt from a scaled record file — and every line still reads
exactly as written. This isolates all plumbing risk from all algorithm risk.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Add the scale ladder and badge geometry constants to `extensions/RecipeViewer/lib/core.sh`: `RV_SCALE_NUMS`/`RV_SCALE_DENS`/`RV_SCALE_LABELS` (space-separated, order `1x, 1 1/2x, 2x, 3x, 1/2x` per contracts/scale-ladder.md), `RV_SCALE_COUNT=5`, `RV_SCALE_BADGE_X=590`, `RV_SCALE_BADGE_Y=4`, `RV_SCALE_BADGE_W=162`, `RV_SCALE_BADGE_H=58`
- [X] T006 Add `RV_SCALE_INDEX=0` to `rv_reset_session` in `extensions/RecipeViewer/lib/core.sh`, and add `rv_scale_select` (sets `RV_SCALE_NUM`/`RV_SCALE_DEN`/`RV_SCALE_LABEL` from an index) and `rv_scale_cycle` (`index = (index + 1) % RV_SCALE_COUNT`)
- [X] T007 Create `extensions/RecipeViewer/lib/scale.sh` with the file header comment and an `rv_scale_ingredients <recipe-file> <num> <den> <output-file>` that emits every `INGREDIENT` record through unchanged in the 6-column format of `contracts/scaled-ingredient-record.md` (column 5 empty, column 6 empty), returning non-zero without writing a partial file on failure
- [X] T008 Source `lib/scale.sh` after `lib/core.sh` in `extensions/RecipeViewer/bin/recipe_viewer.sh`, and add `$RV_TMP/ingredients.scaled` to the `rv_cleanup` removal list
- [X] T009 Implement the exact-rational primitives inside the `rv_scale_ingredients` awk program in `extensions/RecipeViewer/lib/scale.sh`: `gcd`, `reduce`, `rat_mul`, `rat_cmp` (cross-multiplied, never float subtraction), `is_expressible` (reduced denominator in {1,2,3,4,8}), `is_promotable` (in {1,2,4}), `nearest_expressible` (ties to the smaller denominator) — per data-model.md §2
- [X] T010 Implement the conservative scope gate in `extensions/RecipeViewer/lib/scale.sh` so the MVP can never rewrite a line it does not fully understand: a record is a scaling candidate only when its kind is `item`, it is not under a section header matching `equipment`, its text contains no cookware noun (`pan`, `pot`, `skillet`, `dish`, `sheet`, `oven`), it contains no container noun (`can`, `package`, `container`, `jar`, `box`, `bag`, `bottle`, `tub` and plurals), and it contains exactly one run of digits. Every non-candidate is emitted verbatim. US3 widens this gate; until then it is what keeps FR-010/FR-011 satisfied
- [X] T011 Track the current section header while scanning records in the `rv_scale_ingredients` awk pass in `extensions/RecipeViewer/lib/scale.sh` (records arrive in file order), feeding the `equipment` test in T010 — research decision D7
- [X] T012 Change `rv_load_recipe` in `extensions/RecipeViewer/lib/ui.sh` to build the ingredient layout from `$RV_TMP/ingredients.scaled` when `RV_SCALE_INDEX` is non-zero and from the original recipe file when it is zero, falling back to the original file and logging when `rv_scale_ingredients` fails; the instruction layout must keep reading the recipe file directly and unconditionally
- [X] T013 Add `rv_apply_scale` to `extensions/RecipeViewer/lib/scale.sh`: rescale from the **original** recipe file (never from a previous scaled file), rebuild only the ingredient layout, and recompute `RV_INGREDIENT_ROWS`, `RV_INGREDIENT_GAP_ROWS`, and `RV_INGREDIENT_MAX_SCROLL`. It must **not** call `rv_load_recipe` and must not touch `RV_INGREDIENT_CHECKS`, cursors, or `RV_INSTRUCTION_SCROLL`
- [X] T014 Draw the scale badge in `rv_draw_cook` in `extensions/RecipeViewer/lib/ui.sh`: outline at 590,4,162,58 stroke 2, label `RV_SCALE_LABEL` at `RV_TITLE_PT` vertically centred via `rv_pxh`, drawn at every factor including 1x; reduce the cook title truncation from 28 to 22 characters for the narrowed title width
- [X] T015 Add the badge tap branch to `rv_handle_cook_gesture` in `extensions/RecipeViewer/lib/ui.sh`, ordered after the existing back-button branch: `tap` AND `RV_Y2 < RV_TITLE_H` AND `RV_X2 >= RV_SCALE_BADGE_X` → `rv_scale_cycle`, `rv_apply_scale`, `RV_REDRAW=scale`; verify the back button's `RV_X1 < 64` test and this one cannot both fire
- [X] T016 Add `rv_draw_cook_scale_partial` to `extensions/RecipeViewer/lib/ui.sh` refreshing two `GC16` regions — badge (590,4,162,58) and ingredient pane (0, `RV_CONTENT_TOP`, `RV_INGREDIENT_W`, 904) — honouring `rv_partial_allowed` with a full `rv_draw_cook` fallback, and dispatch `RV_REDRAW=scale` to it from the redraw `case` in `extensions/RecipeViewer/bin/recipe_viewer.sh`

**Checkpoint**: The badge cycles through all five labels, the pane rebuilds from
a scaled record file, and every ingredient line is byte-identical to the recipe.
Deployable. Nothing scales yet — that is the point.

---

## Phase 3: User Story 1 — Scale the ingredient list while cooking (Priority: P1) 🎯 MVP

**Goal**: Choosing a scale factor changes every recognized ingredient amount to
the correct scaled value, written as whole numbers and common cooking
fractions — never a decimal, never a fraction outside the closed set.

**Independent Test**: Open a recipe with whole, fraction, mixed, bare-count and
range amounts; cycle to 2x and to 1/2x; confirm every amount is correct and
cookbook-shaped, and that returning to 1x restores the original text exactly.

### Tests for User Story 1

- [X] T017 [P] [US1] Add unit assertions to `tests/test_scaling.sh` for every User Story 1 acceptance scenario and every US1 row of the worked-examples table in `contracts/scaled-ingredient-record.md`: `1 cup whole milk` @2x, `1/2 teaspoon salt` @2x, `1 1/2 cups whole milk` @1/2x, `2 cups all-purpose flour` @1/3x (direct scaler call — 1/3x is not on the UI ladder), `3 green onions, chopped` @2x, `1-2 cups quality chicken stock` @2x, `10 to 12 lasagna noodles` @1/2x, `400g '00' flour` @2x
- [X] T018 [P] [US1] Add the SC-002 corpus assertion to `tests/test_scaling.sh`: sweep every fixture line at every ladder factor and fail on any scaler-written amount containing `.` or a fraction outside `1/2 1/3 2/3 1/4 3/4 1/8 3/8 5/8 7/8` (untouched pass-through text such as a `4.3 oz` package size is exempt)
- [X] T019 [P] [US1] Add the SC-004 and SC-005 corpus assertions to `tests/test_scaling.sh`: applying 1x reproduces every source line byte-for-byte, and 2x→1/2x→3x produces output identical to applying 3x once

### Implementation for User Story 1

- [X] T020 [US1] Implement the leading-amount tokenizer in `extensions/RecipeViewer/lib/scale.sh` for whole numbers, common fractions, and mixed numbers, capturing the exact source character span so all surrounding text can be carried through byte-for-byte (FR-023) — data-model.md §4
- [X] T021 [US1] Extend the tokenizer in `extensions/RecipeViewer/lib/scale.sh` to accept a leading qualifier from the allowlist `heaping`, `scant`, `about`, `pinch of`, `zest of`, `juice of` before the amount, and metric forms with the unit joined to the digits (`400g`, `400ml`) — research decision D5
- [X] T022 [US1] Extend the tokenizer in `extensions/RecipeViewer/lib/scale.sh` to parse ranges written with a hyphen (`1-2 cups`, `4-5 garlic cloves`) or the word `to` (`10 to 12 lasagna noodles`), preserving the literal separator as written (FR-009)
- [X] T023 [US1] Build the unit token table in `extensions/RecipeViewer/lib/scale.sh` mapping each token to canonical name, family, style (`abbrev`/`spelled`) and plural form — **case-sensitive** for single letters (`t`=teaspoon, `T`=tablespoon, `c`/`C`=cup), case-insensitive with optional trailing period otherwise, and bare `ounce`/`oz` resolving to weight while only `fl oz`/`fluid ounce` is volume (research decision D3). Conversion factors are added in US2; this task establishes recognition only
- [X] T024 [US1] Implement the amount renderer in `extensions/RecipeViewer/lib/scale.sh`: a reduced rational becomes a whole number, a common fraction, or a mixed number (`3`, `3/4`, `1 1/2`), and a range renders both endpoints around the preserved separator (FR-015, FR-016)
- [X] T025 [US1] Implement known-unit pluralization in `extensions/RecipeViewer/lib/scale.sh` — plural iff value > 1, original casing preserved, abbreviations never pluralized, and **non-unit nouns never touched** (pluralizing the word after the amount would turn `1 large egg` into `1 larges egg`). Accept and comment the known cosmetic limit: `2 potatoes` at 1/2x renders `1 potatoes` (FR-022)
- [X] T026 [US1] Wire tokenizer → `rat_mul` by the active factor → renderer in `rv_scale_ingredients` in `extensions/RecipeViewer/lib/scale.sh`, scaling the amount **within the unit as written** (no unit change yet) and emitting the rebuilt line with the original unit token verbatim; bare counts scale with no unit at all (FR-008)

**Checkpoint**: US1 is complete and independently deliverable. Amounts scale
correctly and read like a cookbook. Units do not yet move between rungs, so
`3 teaspoons` still reads as `3 teaspoons` — which is correct, just not yet
idiomatic. Lines the scope gate excludes still pass through untouched and
unmarked.

---

## Phase 4: User Story 2 — Amounts land in the unit a cook would actually use (Priority: P2)

**Goal**: A scaled amount is presented in the neighbouring unit of its own
family when that reads more naturally — `3 teaspoons` becomes `1 tablespoon`,
`8 tablespoons` becomes `1/2 cup` — and never in one that reads less naturally.

**Independent Test**: Scale recipes containing teaspoon, tablespoon, cup, ounce,
pound and metric amounts by factors that cross unit boundaries, and confirm each
result lands on the idiomatic rung with metric never converting to US customary.

### Tests for User Story 2

- [X] T027 [P] [US2] Add unit assertions to `tests/test_scaling.sh` for every User Story 2 acceptance scenario: `1 teaspoon garlic powder` @3x → `1 tablespoon`, `4 tablespoons butter` @2x → `1/2 cup`, `1/3 cup pine nuts` @1/2x → `2 2/3 tablespoons`, `8 ounces elbow macaroni` @2x → `1 pound`, `400g '00' flour` @2x → `800g` and still metric (SC-003)
- [X] T028 [P] [US2] Add the promotion-rule guard assertions to `tests/test_scaling.sh` — the counter-examples that shaped research decision D4 and that a naive reading of FR-017 gets wrong: `1 teaspoon` @2x must stay `2 teaspoons` and never become `2/3 tablespoon`; `2 tablespoons` must never become `1/8 cup`; `8 ounces` @1/2x must stay `4 ounces` and not become `1/4 pound`

### Implementation for User Story 2

- [X] T029 [US2] Add integer conversion factors to the unit table in `extensions/RecipeViewer/lib/scale.sh` for all five families per data-model.md §3 (US volume in teaspoons: 1/3/6/48/96/192/768; US weight in ounces: 1/16; metric volume in ml: 1/1000; metric weight in g: 1/1000; count as a single rung)
- [X] T030 [US2] Implement family-scoped conversion in `extensions/RecipeViewer/lib/scale.sh` — convert the scaled rational to family base units and back to a candidate rung, exactly, with no cross-family path existing at all so FR-019 cannot be violated by a later change
- [X] T031 [US2] Implement the promotion rule in `extensions/RecipeViewer/lib/scale.sh`: walk up the ladder and take the largest rung where the amount is at least **half** that rung **and** `is_promotable` (denominator in {1,2,4}) holds. Comment that {1,2,4} rather than {1,2,3,4,8} is the deliberate reconciliation of FR-017 with FR-018, and is the design's single tunable knob (research decision D4)
- [X] T032 [US2] Implement the demotion rule in `extensions/RecipeViewer/lib/scale.sh`: when the amount is not `is_expressible` in its current rung, step down one rung at a time and take the first rung where it is, stopping at the family's smallest rung (`1/6 cup` → `2 2/3 tablespoons`)
- [X] T033 [US2] Implement changed-unit spelling in `extensions/RecipeViewer/lib/scale.sh`: when promotion or demotion changes the rung, emit the canonical name of the new unit in the **style of the original token** — abbreviated source yields abbreviated target, spelled-out yields spelled-out — then apply T025's pluralization (FR-021)
- [X] T034 [US2] Apply the shared-unit rule for ranges in `extensions/RecipeViewer/lib/scale.sh`: choose the display rung from the **upper** endpoint and render both endpoints in it, so a range never reads `1 cup - 2 cups` or straddles two rungs

**Checkpoint**: US1 and US2 both work. Scaled amounts are correct *and*
idiomatic. Still no markers and still a conservative scope gate.

---

## Phase 5: User Story 3 — Know what is scaled and what is not (Priority: P3)

**Goal**: The cook can see the active factor at a glance and can tell which
lines the app declined to scale, so no line is ever silently left behind.

**Independent Test**: Open a recipe containing package sizes, stated
equivalents, equipment and no-amount lines; apply a factor; confirm the factor
is on screen, every line is either correctly scaled or visibly marked, and no
line is silently untouched.

### Tests for User Story 3

- [X] T035 [P] [US3] Add classification assertions to `tests/test_scaling.sh` for every flag trigger in research decision D6 and data-model.md §5: `1 cup chopped onion (1 large)`, `5 ounces baby spinach (or 8 cups chopped spinach)`, `1 dried bay leaf or 2 fresh`, `1/4 cup DeLallo extra virgin olive oil , plus 1 tablespoon`, and the cauliflower `enough for 6 cups florets` line — each flagged with column 3 byte-identical to its source (FR-025)
- [X] T036 [P] [US3] Add the SC-006 and SC-007 corpus assertions to `tests/test_scaling.sh`: no package size (`28-oz`, `4.3 oz`, `15-ounce`, `14 1/2-ounce`) differs at any factor, and every corpus line resolves to exactly one of `scaled`/`approx`/`unchanged`/`flagged` with none unclassified
- [X] T037 [P] [US3] Add FR-013/FR-014 assertions to `tests/test_scaling.sh`: `Salt and pepper`, `Pinch of salt`, `Fresh thyme`, `salt, to taste` and every `section-header` record are unchanged **and unflagged** — a marker on a line with nothing to scale is a defect, not a safe default
- [X] T038 [P] [US3] Add a golden display-log assertion to `tests/test_runtime.sh` that a flagged ingredient row renders as `! <text>` inside its existing single `rv_text` call, with **no additional** `rect` or `text` command emitted for the marker

### Implementation for User Story 3

- [X] T039 [US3] Implement the package/container rule in `extensions/RecipeViewer/lib/scale.sh`, replacing that half of T010's gate: when a container noun is present, scale **only** the leading count and carry every other number through unchanged (`1 (28-oz) Can Diced Tomatoes` @2x → `2 (28-oz) Cans Diced Tomatoes`), pluralizing the container noun; flag rather than render when the scaled count is not a whole number, since half a can is not something a cook can buy (FR-010)
- [X] T040 [US3] Implement parenthesized-equivalent detection in `extensions/RecipeViewer/lib/scale.sh`: a group matching optional `about` + amount + known unit is an `equivalent` and scales in **its own** family (`1 cup (236 ml)` @2x → `2 cups (472 ml)`; `8 ounces ... (about 2 cups)` @2x → `1 pound ... (about 4 cups)`), taking FR-012's first branch
- [X] T041 [US3] Implement the flag triggers in `extensions/RecipeViewer/lib/scale.sh`, replacing the rest of T010's single-digit-run gate: a parenthesized group containing a digit that does not parse cleanly, ` or ` followed by an amount, `plus` followed by an amount, or an unparenthesized trailing restatement (`enough for`, `about`) → emit the source text verbatim with column 6 = `flag` (FR-012 second branch, FR-024, FR-025)
- [X] T042 [US3] Implement the FR-020 approximation path in `extensions/RecipeViewer/lib/scale.sh`: when no rung in the family expresses the amount exactly, render `nearest_expressible` in the best rung and set column 6 = `approx` (`1/8 teaspoon` @1/2x stays `1/8 teaspoon`, marked approximate — the spec's "amounts too small to express" edge case)
- [X] T043 [US3] Add layout column 9 to `rv_build_layout` in `extensions/RecipeViewer/lib/ui.sh` per `contracts/layout-row.md`: map scaled-record column 6 to `~`/`!`/empty, emit it on an item's **first wrapped row only**, and always empty for instruction layouts and at 1x
- [X] T044 [US3] Widen `rv_draw_pane`'s `IFS` `read` in `extensions/RecipeViewer/lib/ui.sh` to a ninth variable and prefix the row text with `<marker> ` when set — inside the existing `rv_text` call, never as an extra draw. The marker must **not** enter the column 5 measured width, so strikethrough and link-underline geometry stay aligned to the ingredient text
- [X] T045 [US3] Update the synthetic 30-row layout fixture in `tests/test_runtime.sh` to emit nine fields, or the widened `read` in T044 will silently shift its text column (called out in `contracts/layout-row.md`)

**Checkpoint**: All of US1-US3 work. Every line in the library is scaled,
marked approximate, left alone, or flagged — never silently skipped.

---

## Phase 6: User Story 4 — Scaling does not disturb cooking progress (Priority: P3)

**Goal**: Changing the scale mid-cook keeps checked ingredients checked and
keeps both panes where the cook was reading.

**Independent Test**: Check several ingredients, scroll both panes, change the
scale, and confirm the checks survive and both panes still show the same region.

### Tests for User Story 4

- [X] T046 [P] [US4] Add assertions to `tests/test_runtime.sh` that four checked ingredients remain checked across a scale change and that `RV_INSTRUCTION_SCROLL` is unmodified (FR-026)
- [X] T047 [P] [US4] Add an assertion to `tests/test_runtime.sh` that the ingredient pane still shows the same **record** after a scale change that rewraps lines and shifts row indices — the property row-index carry-over would fail (FR-027)
- [X] T048 [P] [US4] Add assertions to `tests/test_runtime.sh` that `RV_SCALE_INDEX` returns to 0 when a different recipe is opened from the list, when a recipe link is followed or unwound, and when the recipe is ended from the confirm screen (FR-006)
- [X] T049 [P] [US4] Add an assertion to `tests/test_runtime.sh` that `$RV_TMP/instructions.layout` is byte-identical before and after cycling the full ladder, and that no instruction-pane redraw appears in the display log for a scale change (SC-010, FR-030)

### Implementation for User Story 4

- [X] T050 [US4] Implement scroll anchoring in `rv_apply_scale` in `extensions/RecipeViewer/lib/scale.sh`: before rescaling, resolve the ingredient **record index** at the current scroll position; after rebuilding, set `RV_INGREDIENT_SCROLL` to that record's first wrapped row (`$4 == 1`) and clamp to the recomputed `RV_INGREDIENT_MAX_SCROLL` — data-model.md §8
- [X] T051 [US4] Reset `RV_SCALE_INDEX` to 0 in `rv_load_recipe` in `extensions/RecipeViewer/lib/ui.sh` so opening, linking to, or unwinding to any recipe starts at its original amounts, and confirm `rv_abandon`'s existing `rv_reset_session` call already covers ending a recipe

**Checkpoint**: All four user stories complete. Feature is functionally done.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T052 Sync the golden geometry assertions in `tests/test_runtime.sh` with every region this feature changed — badge outline and label coordinates, the 22-character cook title truncation, and the two `GC16` regions of `rv_draw_cook_scale_partial` — per the project rule that command-log geometry tests track every region change
- [X] T053 [P] Verify `python -m unittest discover -s tests -p "test_*.py"` still passes untouched, confirming `tools/compile_paprika.py` and schema 4 were not modified
- [X] T054 Run `dash -n` over `extensions/RecipeViewer/lib/scale.sh`, `lib/ui.sh`, `lib/core.sh` and `bin/recipe_viewer.sh` and fix anything it rejects — bash accepts syntax the device's `dash` kills the whole script on
- [X] T055 [P] Document recipe scaling in `README.md`: the badge control, the five factors, what `!` and `~` mean, and that instruction amounts deliberately do not scale
- [X] T056 [P] Write `.agents/memories/recipe-scaling-model.md` recording the durable findings — exact rationals rather than floats, the {1,2,4} promotion set and the `1 teaspoon`→`2/3 tablespoon` counter-example that forced it, case-sensitive `t`/`T`, bare `ounce` as weight, and text markers instead of per-row draws because of FBInk's per-invocation cost — and link it from `.agents/memories/MEMORY.md`
- [X] T057 Run the full local suite per `quickstart.md`: `bash tests/test_scaling.sh`, `bash tests/test_runtime.sh`, `python -m unittest discover -s tests -p "test_*.py"`
- [ ] T058 Offer `tools/deploy.ps1` to the owner and deploy before any on-device claim — an on-device test without a deploy first has already produced a false "no change" result in this project
- [ ] T059 Validate SC-008 on device per quickstart.md scenario 7: on a wrapping-heavy recipe, confirm a scale change feels no slower than an ingredient-pane swipe, check FBInk invocation counts in `debug.log`, and confirm longer scaled lines wrap inside the 300 px pane rather than clipping at the divider
- [ ] T060 Record the on-device result in `.agents/memories/recipe-scaling-model.md`, including whether the {1,2,4} promotion set produced any amount the owner found unidiomatic in real use

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies; T001-T004 are fully parallel
- **Foundational (Phase 2)**: needs Setup — **blocks every user story**
- **US1 (Phase 3)**: needs Foundational
- **US2 (Phase 4)**: needs US1 — extends the same tokenizer and renderer
- **US3 (Phase 5)**: needs US1; **should follow US2** so the equivalent path in T040 can reuse US2's family conversion rather than duplicating it
- **US4 (Phase 6)**: needs Foundational only — genuinely independent of US1-US3, since it operates on record indices and scroll state, not on amount text
- **Polish (Phase 7)**: needs all desired stories

### Cross-story notes

- US2 is a **refinement** of US1's renderer, not a parallel feature. The spec
  says as much: US1 "is usable without it".
- US3 **replaces** the conservative scope gate built in T010. Until US3 lands,
  that gate is what holds FR-010 and FR-011; do not remove it early.
- US4 is the only story that can be built alongside US1 by a second person.

### Within each story

- Tests first within each phase (T017-T019 before T020-T026, and so on)
- Tokenizer before renderer; renderer before unit movement
- Classification before markers; markers before layout plumbing

### Parallel Opportunities

- All of Phase 1 (T001-T004) — four different files
- Test tasks within each story phase: T017-T019, T027-T028, T035-T038, T046-T049
- Polish: T053, T055, T056 touch unrelated files
- **Little else.** Most implementation tasks in Phases 2-5 edit
  `extensions/RecipeViewer/lib/scale.sh` and must be sequential. This is a
  small-surface feature in a small codebase, not a fan-out.

---

## Parallel Example: Phase 1 Setup

```bash
Task: "Create tests/fixtures/scaling-corpus.tsv from the sample library"
Task: "Create tests/test_scaling.sh skeleton with --only dispatch"
Task: "Add scaling fixture cases to tests/fixtures/library/0002.recipe"
Task: "Add a dash -n syntax gate to tests/test_runtime.sh"
```

## Parallel Example: User Story 3 tests

```bash
Task: "Flag-trigger classification assertions in tests/test_scaling.sh"
Task: "SC-006/SC-007 corpus assertions in tests/test_scaling.sh"
Task: "FR-013/FR-014 unchanged-and-unflagged assertions in tests/test_scaling.sh"
Task: "Flagged-row single-rv_text golden assertion in tests/test_runtime.sh"
```

---

## Implementation Strategy

### MVP First

1. Phase 1 Setup
2. Phase 2 Foundational — **stop and deploy here.** The badge cycles and
   nothing scales. If the badge, the partial redraw, or the layout switch is
   wrong, you find out with zero algorithm in play.
3. Phase 3 US1 — **stop and validate.** Amounts scale correctly as fractions.
   This is a genuinely shippable MVP: the spec's own priority rationale says a
   cook-friendly fraction from the first increment is the whole request.

### Incremental Delivery

| Increment | Adds | Cook-visible result |
|---|---|---|
| Foundational | plumbing | A scale badge that cycles and changes nothing |
| + US1 | amount scaling | Correct amounts, cookbook fractions, original units |
| + US2 | unit ladders | `3 teaspoons` now reads `1 tablespoon` |
| + US3 | classification | Packages, equipment and equivalents handled; unscalable lines marked |
| + US4 | progress safety | Scaling mid-cook keeps checks and reading position |

Each increment is deployable and none breaks its predecessor.

### Suggested MVP scope

**Phases 1-3 (T001-T026).** US1 alone satisfies FR-001 through FR-009 and
FR-015/016, plus SC-001, SC-002, SC-004 and SC-005.

---

## Notes

- Every task edits a real file that exists today or is named in plan.md's
  Project Structure — there is no scaffolding step, because the runtime layout
  already exists.
- Commit after each task or logical group.
- Do not add a drawing call per row anywhere in this feature. The device's
  cost model is FBInk process count, not pixels.
- Re-read `.agents/memories/kindle-paperwhite-2-runtime.md` before any on-device
  work in Phase 7.
