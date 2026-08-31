# Quickstart: Validating Recipe Scaling

How to prove the feature works end to end. Each scenario states what it
validates, how to run it, and what a pass looks like. Details of formats and
rules live in [`data-model.md`](./data-model.md) and
[`contracts/`](./contracts/) — this file does not repeat them.

## Prerequisites

- Bash 4+, `awk`, and a POSIX `sh` on the host (the repo's existing shell test
  harness already assumes these).
- `dash` available for the syntax gate below. On Windows this is the one step
  that needs WSL or a Linux/macOS host; the runtime memory records a shipped
  crash caused by skipping it.
- Python 3 for the unchanged compiler tests.
- **Optional**: a compiled sample library at
  `build/fake-kindle/extensions/RecipeViewer/library/`. The corpus sweep runs
  against the committed fixture with or without it, and additionally sweeps the
  generated library when it is present.
- **Optional**: a Kindle Paperwhite 2 for scenario 7.

## Run everything

```bash
bash tests/test_scaling.sh          # scaler units + corpus sweep (new)
bash tests/test_runtime.sh          # runtime, geometry, gestures (extended)
python -m unittest discover -s tests -p "test_*.py"   # compiler, must be untouched
```

Expected: three clean passes, the last one identical to before this feature —
the compiler and schema 4 are deliberately not modified.

---

## Scenario 1 — Amounts scale and read like a cookbook (US1, FR-007/015/016)

**Validates**: SC-002. Every acceptance scenario of user story 1.

```bash
bash tests/test_scaling.sh --only units
```

Pass when each named case produces its stated output, including:
`1 cup whole milk` at 2x → `2 cups whole milk`; `1 1/2 cups whole milk` at
1/2x → `3/4 cup whole milk`; `2 cups all-purpose flour` at 1/3x → note that
1/3x is **not** on the ladder (FR-029), so this spec example is exercised as a
direct scaler call rather than through the UI; `3 green onions, chopped` at 2x
→ `6 green onions, chopped`; `1-2 cups quality chicken stock` at 2x →
`2-4 cups quality chicken stock`.

Fail signature to watch for: any output containing `.` inside an amount the
scaler wrote, or a fraction outside `1/2 1/3 2/3 1/4 3/4 1/8 3/8 5/8 7/8`.

## Scenario 2 — Units land where a cook expects (US2, FR-017/018/019)

**Validates**: SC-003.

```bash
bash tests/test_scaling.sh --only units
```

Pass requires all of: `1 teaspoon garlic powder` at 3x → `1 tablespoon`;
`4 tablespoons butter` at 2x → `1/2 cup`; `1/3 cup pine nuts` at 1/2x →
`2 2/3 tablespoons`; `8 ounces elbow macaroni` at 2x → `1 pound`; `400g '00'
flour` at 2x → `800g` and still metric.

The two guard cases matter as much as the promotions: `1 teaspoon` at 2x must
stay `2 teaspoons` (not `2/3 tablespoon`), and `2 tablespoons` must never
become `1/8 cup`. These are the counter-examples that shaped the promotion
rule — see research decision D4.

## Scenario 3 — Nothing is scaled that should not be (US3, FR-010/011/013/014)

**Validates**: SC-006, SC-007.

```bash
bash tests/test_scaling.sh --only corpus
```

The sweep runs every line of `tests/fixtures/scaling-corpus.tsv` through all
five factors and asserts, per line, that it is classified `scaled`, `approx`,
`unchanged`, or `flagged` — never silently left alone while its neighbours
change. Pass when the report ends with zero unclassified lines and zero
altered package sizes (`28-oz`, `4.3 oz`, `15-ounce`, `14 1/2-ounce` must be
byte-identical at every factor).

Spot-check by eye in the sweep's report: `5 Quart Sauce Pan` unchanged and
unflagged, `Salt and pepper` unchanged and unflagged,
`1 cup chopped onion (1 large)` flagged, and the cauliflower line flagged.

## Scenario 4 — Round-tripping and repeated changes are exact (FR-003/004)

**Validates**: SC-004, SC-005.

```bash
bash tests/test_scaling.sh --only corpus
```

Two mechanical properties across the whole corpus:
- applying `1x` reproduces the source text byte-for-byte, per line;
- the sequence 2x → 1/2x → 3x produces output identical to applying 3x once.

Pass when both report zero differing lines. A failure here means scaling is
compounding from a previous result instead of from the original.

## Scenario 5 — Instructions never move (FR-030)

**Validates**: SC-010.

```bash
bash tests/test_runtime.sh
```

The runtime test loads a fixture recipe, cycles the scale through the full
ladder, and compares `$RV_TMP/instructions.layout` before and after. Pass when
the file is byte-identical at every factor and the instruction pane's redraw
never appears in the display log for a scale change.

## Scenario 6 — Changing scale does not disturb the cook (US4, FR-005/026/027)

**Validates**: SC-001, SC-009.

```bash
bash tests/test_runtime.sh
```

Assertions to look for in the output:
- the badge is drawn in the title bar at 590,4,162,58 on every `rv_draw_cook`,
  and its label matches the active factor;
- a tap at `x >= 590, y < 66` advances the ladder, while a tap at `x < 64`
  still opens the back/confirm path — the two title-bar targets must not
  overlap;
- four checked ingredients are still checked after a scale change
  (`RV_INGREDIENT_CHECKS` unchanged);
- the ingredient scroll lands on the same *record* it was on before, even
  though rewrapping moved the row indices;
- the instruction scroll is untouched;
- opening a different recipe resets the badge to `1x`.

## Scenario 7 — On-device behaviour (SC-008)

Host tests cannot measure the real e-ink cost — the runtime memory is explicit
that the draw phase, not computation, dominates, and that its numbers only
came from instrumenting the real device.

```powershell
.\tools\deploy.ps1 -KindleRoot E:\ -ClearLog
```

Then on the Kindle: open a recipe with wrapping ingredient lines (the baked
turkey meatballs recipe is the known stress case), tap the badge to reach 2x,
and confirm by feel and by `debug.log` timings that a scale change is no
slower than an ingredient-pane swipe. Also confirm the scaled pane's longer
lines wrap inside 300 px rather than being clipped at the divider.

If a scale change feels materially slower than a swipe, the first thing to
check is FBInk invocation count in `debug.log`, not the `awk` pass.

## Gate — device shell compatibility

Run before any deploy, on any new or changed shell syntax:

```bash
dash -n extensions/RecipeViewer/lib/scale.sh
dash -n extensions/RecipeViewer/lib/ui.sh
dash -n extensions/RecipeViewer/lib/core.sh
dash -n extensions/RecipeViewer/bin/recipe_viewer.sh
```

Pass is silence. This codebase has already shipped one fatal crash from
`$((16#ff))` — accepted by bash, a parse error that kills the whole script
under the Kindle's `dash`. The design keeps all arithmetic inside `awk`
specifically to keep this surface small; the check still runs.

---

## Definition of done

| # | Check | Source |
|---|---|---|
| 1 | `tests/test_scaling.sh` passes, units and corpus | SC-002/003/004/005/006/007 |
| 2 | `tests/test_runtime.sh` passes, including new badge geometry goldens | SC-001/009/010 |
| 3 | `python -m unittest discover -s tests -p "test_*.py"` passes unchanged | schema 4 untouched |
| 4 | `dash -n` clean on all four runtime scripts | project rule |
| 5 | On-device pass of scenario 7 | SC-008 |
| 6 | Scaling design recorded in `.agents/memories/recipe-scaling-model.md` and linked from `MEMORY.md` | `AGENTS.MD` |
| 7 | `tools/deploy.ps1` offered to the owner after the runtime change | `feedback_offer_deploy_after_change` |
