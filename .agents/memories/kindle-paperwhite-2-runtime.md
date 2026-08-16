---
name: kindle-paperwhite-2-runtime
description: Paperwhite 2 device paths, geometry, touch format, and measured fbink line height.
type: project
date: 2026-08-16
---

# Kindle Paperwhite 2 runtime

The target is a 758×1024 Kindle Paperwhite 2 at 212 DPI, firmware 5.12.2.2.
`com.lab126.winmgr orientationLock` is confirmed UNUSABLE for this app across
two separate hardware trials, for two different reasons — do not retry it
again without a fundamentally different mechanism:
- Trial 1: calling it produced a white screen followed by a framework restart.
- Trial 2 (2026-08-14): it did not crash, but it also did not rotate the
  framebuffer. `eips`/`fbink` kept writing directly to the physical panel's
  native 758×1024 portrait pixel addressing regardless of the lock value —
  `orientationLock` evidently only affects the Kindle's own reader-shell UI,
  not the raw framebuffer these low-level tools address directly. The app had
  been changed to draw a 1024×758-logical cook screen (wider panes) on the
  assumption the panel would rotate; instead every draw coordinate past
  x≈758 wrapped/overlapped onto the still-758-wide portrait framebuffer,
  producing garbled, unusable text. This confirms real landscape rotation is
  not achievable through this app's toolchain (`eips`/`fbink`, no rotation
  flags of their own; see FBInk's CLI reference) — only `fbdepth`-level kernel
  framebuffer rotation could plausibly do it, which is a distinct, likely
  even riskier, kernel ioctl operation this app has never attempted. The
  landscape attempt (`rv_enter_landscape` call site in `rv_load_recipe`,
  landscape-sized cook/confirm geometry) was reverted back to the working
  portrait side-by-side layout the same day. The dead `rv_enter_landscape`/
  `rv_restore_orientation` scaffolding remains in `core.sh` for reference but
  must not be wired back up again.
Library scripts live under `/mnt/us/documents`; the application lives under
`/mnt/us/extensions/RecipeViewer`. KOReader provides FBInk at
`/mnt/us/koreader/fbink`; firmware provides `eips`. The `cyttsp4_mt` touch
device is `/dev/input/event1` and emits 16-byte, little-endian Linux
`input_event` records with coordinates mapped 1:1 to screen pixels.

The script-book launcher can send uncaptured stdout and stderr directly to the
framebuffer. Redirect both streams to the append-only `debug.log` before the
first dependency probe or drawing command; otherwise FBInk diagnostics appear
as screen content. The document launcher also redirects the application as a
second guard.

FBInk's measured rendered height is `point_size * 212 / 72`. Never advance a
vertical cursor with a guessed pixel constant: calculate it with that formula
and add the role's explicit spacing buffer. On this device, FBInk rasterizes
Atkinson Hyperlegible horizontally narrower than host font metrics predict.
The measured wrapper calibration is `RV_FONT_WIDTH_PERCENT=135`. Preserve a
shared hard content-bottom boundary (`RV_CONTENT_BOTTOM` in `core.sh`, 1014 as
of 2026-08-16 — a small margin above the 1024px panel edge now that there is
no bottom button bar); visible-row calculation, drawing, and hit testing must
all use the same boundary.

As of 2026-08-14, the runtime has a hardware-trial hybrid refresh policy:
first clear the exact affected framebuffer rectangle without refreshing, draw
its complete replacement, then refresh it. Ingredient toggles request `DU`;
pane/list scrolling and live search results request `GC16`. List, recipe, and
confirmation transitions remain full refreshes, as does every twelfth partial
update to clean the panel. Search edits redraw only the upper results region,
leaving the on-screen keyboard intact. Keep the command-log geometry tests in
sync with every region change. Set `RV_PARTIAL_REFRESH=0` to diagnose device
artifacts with the prior full-refresh-only behavior.

Deploy with an explicit Kindle root, verify source and destination SHA-256
hashes, and ask the owner to eject manually after verification. Do not treat
the white USB transition as application output, and do not auto-eject while
iterating because it obscures whether the application has launched. Generated
libraries and device logs remain ignored. Kindle scripts and record files must
retain LF endings; `.gitattributes` enforces this for fresh clones.

The Kindle has POSIX shell tools but no Python or BusyBox. Data files must be
parsed as records and must never be sourced as shell code.

As of 2026-08-16: waking the device from sleep leaves the e-ink panel
blank/stale (only whatever the reader draws next, via a normal partial
refresh, becomes visible) because Kindle suspend/resume gives this app no
notification it happened. There is no confirmed lipc/powerd event hook for a
raw script-book process to subscribe to, so the runtime instead treats a
wall-clock jump across one ~1s touch-poll cycle as a resume signal (see
`rv_detect_resume` in `core.sh`, wired into the main loop in
`bin/recipe_viewer.sh`): normal suspend freezes the whole process, so real
elapsed time jumps far past one poll cycle only when the device was asleep.
On that signal the loop forces a full flashing redraw of the current screen
and discards whatever gesture the same cycle captured (likely just the wake
tap/button, not an in-app action). `RV_WAKE_GAP_SECONDS` (default 4) tunes
the threshold.

As of 2026-08-16: touch input felt sluggish, especially typing on the search
keyboard, because `rv_decode_touch_file` (`touch.sh`) forked a real `od`
subprocess per captured 16-byte `input_event` record — a single ~300ms tap
can contain dozens of records, and the Kindle's CPU makes each fork/exec
comparatively expensive. Fixed by dumping the whole capture with one `od -w16`
call and iterating its lines in-shell instead. The remaining per-record
subshells (`rv_hex_le32`, called up to three times per record via `$(...)`)
were still measurable, so it was rewritten to set `RV_HEX32` via pure
arithmetic instead of `printf | subshell` (see the follow-up entry below for
why that arithmetic must use `0x`, not `16#`). Together these cut a
synthetic 60-sample decode from ~4s to ~0.09s in local testing (not on-device,
but the fork elimination is the same regardless of CPU speed). This alone
was not enough — the owner reported the search keyboard was still very slow
even after this fix and the dash crash fix below. The remaining, dominant
cost turned out to be architectural, not CPU: `rv_capture_gesture` always
slept the full poll window before decoding, regardless of how quickly (or
whether) touch data arrived, so every tap incurred close to the full window
as pure dead latency. Fixed by racing `dd` (bounded by
`RV_TOUCH_CAPTURE_RECORDS`, default 48, so it can also return early once a
fast-moving swipe is already producing records) against a background
`sleep "$RV_TOUCH_POLL_SECONDS"` watcher that only kills it if nothing
arrives — confirmed under dash that a fast source returns via the count in
~60ms while an idle source still gets cleanly killed at the timeout. Default
poll window dropped from the original 1s to `RV_TOUCH_POLL_SECONDS=0.5`.
`rv_classify_gesture`'s "hold" gesture (800ms dwell) is classified but never
dispatched anywhere in `ui.sh`, so shortening the window has no effect on
anything actually wired up — the real tradeoff is swipe completeness (a
window cut short mid-drag could under-report `dy` and misclassify a scroll
as a tap), which the record-count early-exit mitigates but does not
eliminate. If swipes start feeling unreliable, raise
`RV_TOUCH_POLL_SECONDS` back up rather than assuming decoding regressed.

Even after all of the above, the owner still saw ~1s per search-keyboard
keystroke. Instrumented `bin/recipe_viewer.sh` with a temporary perf trace
(capture/dispatch/draw phases, timed via `/proc/uptime` — this device's
`date` does not support `%N`, it prints the literal string) and confirmed
with real on-device numbers: capture ~0.55s (working as designed), dispatch
~0.03s (negligible), **draw 0.5–1.5s** — draw is the actual bottleneck, not
touch handling. Root cause: every `rv_text`/`rv_rect` call spawns a brand
new `fbink`/`eips` process, and every single `fbink` invocation re-detects
the panel hardware and reloads the TTF font from disk from scratch (visible
directly in `debug.log` as a full "[FBInk] Detected a Kindle PaperWhite
2... Font loaded..." preamble on every call) — roughly 100-200ms of fixed
cost *per invocation*, confirmed by both the raw log and by dividing
draw-phase duration by fbink-call count across several samples. This holds
even for the smallest possible **partial** redraw (clear-region + one text
line + refresh-region is already 3+ fbink calls, ~0.5-0.6s), so "draw less"
only helps at the margin — the floor is set by how many separate fbink
processes a screen update needs, not by how much content changes.
Researched fixes via FBInk's own CLI reference
(https://github.com/NiLuJe/FBInk/blob/master/CLI.md): it supports drawing
multiple same-style/size lines in one invocation (would reduce the search
results' per-row calls, but the exact auto-advance spacing between lines
isn't documented precisely enough to trust matching this app's exact
`RV_LIST_ROW_H`/hit-test geometry without on-device verification — get it
wrong and drawn text drifts from its tap zone, a real bug); it also has a
daemon mode (`-d`, stays resident via `/tmp/fbink-fifo`, eliminating the
reload cost entirely) but the daemon only accepts plain sequential text
lines with no per-message x/y/font/size control, so it doesn't fit this
app's precise-positioning rendering model without a much larger rework.
Given tonight already cost one broken deploy from an unverified assumption
(the `16#` crash above), asked the owner rather than guessing again; they
chose to stop at the current ~0.5-0.6s/keystroke rather than risk the
line-batching approach. If revisiting: line-batching for the search results
list (same style/size, consecutive rows) is the most promising remaining
lever, but prototype and verify row spacing on-device before trusting it,
and the golden `tests/test_runtime.sh` geometry assertions will need
updating either way.

The first version of that `rv_hex_le32` rewrite used ksh-style `$((16#ff))`
base-literal arithmetic and shipped a hard crash on every recipe open (any
touch decode). The Kindle's `/bin/sh` behaves like `dash`, confirmed on a
local dash: `$((16#ff))` is not just wrong there, it's a fatal arithmetic
*parse* error that kills the whole running script immediately (nothing after
it executes; exit code 2) — not a soft per-statement failure the way a bad
`[ ]` test would be. `$((0x$hex))` (C-style hex literal) evaluates correctly
and is safe. Lesson: never use `base#value` arithmetic syntax in this
codebase's shell scripts, and when adding *any* new arithmetic/expansion
syntax that isn't already proven elsewhere in the repo, sanity-check it under
`dash -c '...'` before deploying — bash on the dev machine will happily
accept shell syntax the Kindle's actual interpreter rejects outright.
