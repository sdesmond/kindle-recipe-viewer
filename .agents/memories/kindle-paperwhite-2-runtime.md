---
name: kindle-paperwhite-2-runtime
description: Paperwhite 2 device paths, geometry, touch format, and measured fbink line height.
type: project
date: 2026-08-14
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
separate hard content-bottom boundary above the End Recipe bar; visible-row
calculation, drawing, and hit testing must all use the same boundary.

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
