---
name: kindle-paperwhite-2-runtime
description: Paperwhite 2 device paths, geometry, touch format, and measured fbink line height.
type: project
date: 2026-08-13
---

# Kindle Paperwhite 2 runtime

The target is a 758×1024 Kindle Paperwhite 2 at 212 DPI, firmware 5.12.2.2.
Do not use `com.lab126.winmgr orientationLock` from the script-book process on
this device: the hardware trial produced a white screen followed by a framework
restart. Keep the stable portrait startup until landscape can be implemented
and validated entirely through the framebuffer path.
Library scripts live under `/mnt/us/documents`; the application lives under
`/mnt/us/extensions/RecipeViewer`. KOReader provides FBInk at
`/mnt/us/koreader/fbink`; firmware provides `eips`. The `cyttsp4_mt` touch
device is `/dev/input/event1` and emits 16-byte, little-endian Linux
`input_event` records with coordinates mapped 1:1 to screen pixels.

FBInk's measured rendered height is `point_size * 212 / 72`. Never advance a
vertical cursor with a guessed pixel constant: calculate it with that formula
and add the role's explicit spacing buffer.

As of 2026-08-14, the runtime has a hardware-trial hybrid refresh policy:
same-screen checks and cursors clear/redraw one pane and request a non-flashing
`DU` region refresh; scrolling requests `GC16`; list/recipe transitions and
every twelfth same-screen update remain full flashing refreshes. This policy is
covered by host command-log tests but is not hardware-accepted until the owner
confirms erasure quality and absence of stale pixels on the PW2. Set
`RV_PARTIAL_REFRESH=0` for the prior full-refresh-only behavior.

The Kindle has POSIX shell tools but no Python or BusyBox. Data files must be
parsed as records and must never be sourced as shell code.
