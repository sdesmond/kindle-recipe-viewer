---
name: feedback_offer_deploy_after_change
description: Always offer to deploy to the physical Kindle right after a runtime code change, rather than waiting to be asked.
metadata:
  type: feedback
---

After any change to `extensions/RecipeViewer/` or `documents/RecipeViewer.sh`,
proactively offer to run `tools/deploy.ps1 -KindleRoot <path>` (with the
Kindle plugged in via USB) rather than just describing the change and moving
on.

**Why:** The owner tested two runtime fixes on-device and saw no behavior
change; the actual cause was that the edits were only ever applied to the
working tree and never deployed — see the 2026-08-26 entry in
[[kindle-paperwhite-2-runtime]]. The owner's own diagnosis: "you should
always offer to deploy after a change."

**How to apply:** At the end of any turn that edits the Kindle
runtime/deployment code, ask whether the device is plugged in and offer to
run the deploy script (or walk through it) before considering the task done.
Don't assume a described fix is "live" on the device until it's actually been
deployed and the app restarted.
