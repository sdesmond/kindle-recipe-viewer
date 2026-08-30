# Implementation Plan: Recipe Scaling

**Branch**: `main` (spec directory `specs/001-recipe-scaling`) | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-recipe-scaling/spec.md`

## Summary

Let a cook multiply an open recipe's ingredient amounts by one of five fixed
factors (1/2x, 1x, 1 1/2x, 2x, 3x) without leaving the cook screen, rendering
every scaled amount as a whole number or a common cooking fraction in the unit
a cook would actually use.

Technical approach: scaling runs **entirely on the device at runtime**, as one
additional POSIX `awk` pass inserted ahead of the existing layout-wrapping
pass. The compiled record format, its schema version 4, and
`tools/compile_paprika.py` are untouched. Amounts are carried as exact
integer numerator/denominator rationals, never floats, so "is this amount
expressible as a common cooking fraction?" is an exact test rather than a
tolerance, and repeated scale changes are provably path-independent
(SC-005). The active factor lives in a title-bar badge that is also the
control: tapping it cycles the ladder, satisfying "one interaction, without
navigating away" (SC-001). Lines the parser cannot fully interpret are left
in their original wording and marked, never partially rewritten.

## Technical Context

**Language/Version**: POSIX `sh` (device `/bin/sh` behaves as `dash`) and
POSIX `awk` for the device runtime; Python 3 host-side (unchanged by this
feature); Bash 4+ for the test harness.

**Primary Dependencies**: On device — `awk`, `sed`, `cut`, `wc`, FBInk (from
KOReader, at `/mnt/us/koreader/fbink`), firmware `eips`. No new dependency is
introduced. `awk` is already load-bearing on device
(`rv_build_layout`, `rv_layout_hit`, `rv_filter_recipes`, `rv_uid_ordinal`),
so relying on it for scaling adds no new runtime risk.

**Storage**: Read-only compiled library of TSV record files under
`$RV_LIBRARY_ROOT` (schema 4, unchanged). Per-session derived files under
`$RV_TMP`. Nothing is persisted: the scale factor is session state, discarded
when the recipe ends (FR-006).

**Testing**: `tests/test_runtime.sh` (shell functions sourced directly, golden
display-command log assertions via `tests/helpers/display_logger.sh`), plus a
new `tests/test_scaling.sh` for the scaler's unit behaviour and a corpus sweep
that mechanically checks SC-002/004/005/006/007 over every ingredient line in
the sample library. `tests/test_compile_paprika.py` is unaffected.

**Target Platform**: Kindle Paperwhite 2, firmware 5.12.2.2, 758x1024 at
212 DPI. No Python, no BusyBox on device.

**Project Type**: Single embedded shell application with a host-side compiler.

**Performance Goals**: A scale change must feel no slower than an ingredient
pane scroll does today (SC-008). The documented floor is set by FBInk process
count, not computation: each `fbink`/`eips` invocation costs ~100-200 ms
because it re-detects the panel and reloads the TTF font, and a partial pane
scroll already costs ~0.5-0.6 s. The scaling pass adds exactly **one** `awk`
fork per scale change; the redraw adds ~3 FBInk calls over a pane scroll (a
second clear/refresh region pair for the badge). Budget: scale change within
~1.3x the cost of a pane scroll.

**Constraints**: Device runtime stays POSIX `sh`; never `base#value`
arithmetic (a fatal parse error under `dash` — it took down a shipped build
once); data files are parsed as records and never sourced; every drawing,
visible-row, and hit-test path must share `RV_CONTENT_BOTTOM`; command-log
geometry tests must stay in sync with every region change. Ingredient pane is
300 px wide, so scaled text that grows ("1 tablespoon" -> "2 2/3
tablespoons") must be allowed to re-wrap rather than being truncated.

**Scale/Scope**: 19 recipes / ~200 ingredient lines in the sample library;
~30 ingredient lines per recipe worst case. Five scale factors. One new
runtime module (`lib/scale.sh`), touching four existing files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` is still the unmodified scaffold — every
principle is a `[PRINCIPLE_N_NAME]` placeholder, and no version or
ratification date is set. **There are therefore no ratified constitutional
gates to evaluate, and none can fail.** This is recorded rather than silently
skipped; if the project later ratifies a constitution, this plan should be
re-checked against it.

In its place, the binding project rules come from `AGENTS.MD` and
`.agents/memories/kindle-paperwhite-2-runtime.md`. Treated as de-facto gates:

| Rule (source) | Status | How this design satisfies it |
|---|---|---|
| Device runtime must remain POSIX `sh`; no Python, no BusyBox on device (`AGENTS.MD`) | PASS | Scaling is POSIX `sh` + POSIX `awk`. No host-side runtime component. |
| No `base#value` arithmetic; verify new shell syntax under `dash` before deploying (runtime memory) | PASS | Design introduces no new shell arithmetic syntax; all arithmetic lives inside `awk`. A `dash` syntax check is an explicit task. |
| Data files are parsed as records, never sourced (`AGENTS.MD`, runtime memory) | PASS | The scaled ingredient file is a TSV record file read by `awk` and `IFS`-split `read`, exactly like the existing layout files. |
| Host-side compilation stays separate from the deployed runtime (`AGENTS.MD`) | PASS | `tools/compile_paprika.py` and schema 4 are untouched; this is confirmed by the spec's own Assumptions and Out of Scope sections. |
| Keep command-log geometry tests in sync with every region change (runtime memory) | PASS | New badge geometry and the new partial-refresh region get golden assertions in `tests/test_runtime.sh`. |
| Shared `RV_CONTENT_BOTTOM` across drawing, visible-row math, and hit testing (runtime memory) | PASS | The badge sits in the title bar above `RV_CONTENT_TOP`; pane geometry is unchanged. |
| Record durable hardware findings in `.agents/memories/` and link them from `MEMORY.md` (`AGENTS.MD`) | PASS | A new memory for the scaling model is a delivery task, linked from `MEMORY.md`. |
| Offer `tools/deploy.ps1` after editing runtime code (`feedback_offer_deploy_after_change`) | PASS | Deployment offer is an explicit closing task. |

**Post-Phase-1 re-check**: unchanged. The Phase 1 design adds one runtime
module, one record format (documented in `contracts/`), and one layout column;
it introduces no new dependency, no new arithmetic syntax, no schema change,
and no host-side runtime code. No entry in Complexity Tracking is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-recipe-scaling/
├── plan.md              # This file
├── spec.md              # Feature specification (input)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── scaled-ingredient-record.md   # rv_scale_ingredients output format
│   ├── layout-row.md                 # extended layout row (adds column 9)
│   └── scale-ladder.md               # factor set, labels, cycle order, badge
└── tasks.md             # Phase 2 output ($speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
extensions/RecipeViewer/
├── bin/
│   └── recipe_viewer.sh     # MODIFIED: source lib/scale.sh; RV_REDRAW=scale; cleanup
└── lib/
    ├── core.sh              # MODIFIED: scale ladder + badge geometry constants,
    │                        #           RV_SCALE_INDEX reset in rv_reset_session
    ├── scale.sh             # NEW: amount parsing, rational arithmetic, unit
    │                        #      normalization, rendering, scroll anchoring
    ├── touch.sh             # unchanged
    └── ui.sh                # MODIFIED: badge draw + hit test, flag marker in
                             #           rv_build_layout, scale-change partial redraw

tools/
├── compile_paprika.py       # unchanged (schema stays at 4)
└── deploy.ps1               # unchanged

tests/
├── fixtures/
│   ├── library/             # MODIFIED: fixture recipe gains scaling cases
│   └── scaling-corpus.tsv   # NEW: committed corpus of real ingredient lines
├── helpers/display_logger.sh# unchanged
├── test_compile_paprika.py  # unchanged
├── test_runtime.sh          # MODIFIED: badge geometry, gesture, redraw golden tests
└── test_scaling.sh          # NEW: scaler unit tests + SC-002..SC-007 corpus sweep

.agents/memories/
├── MEMORY.md                # MODIFIED: link the new memory
└── recipe-scaling-model.md  # NEW: durable design findings
```

**Structure Decision**: The existing single-application layout is kept. Scaling
lands as one new sourced library, `extensions/RecipeViewer/lib/scale.sh`,
matching how `core.sh` / `touch.sh` / `ui.sh` already divide responsibility
(state and data, input decoding, drawing and reducers). Putting it in its own
file — rather than growing `ui.sh`, already the largest module at 847 lines —
keeps the amount grammar independently testable by sourcing one file, which is
what makes the corpus sweep in `tests/test_scaling.sh` cheap to write.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify.
