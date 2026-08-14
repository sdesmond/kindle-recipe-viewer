# Kindle Recipe Viewer — Agent Instructions

This repository targets a Kindle Paperwhite 2 running firmware 5.12.2.2.
The device runtime must remain POSIX `sh`; the Kindle has neither Python nor
BusyBox. Keep host-side compilation and deployment separate from the deployed
runtime.

Do not modify the sibling `kindle-chess-viewer` or `recipe-viewer`
repositories. They are read-only references.

Record durable hardware findings in `.agents/memories/` and link every memory
from `.agents/memories/MEMORY.md`.

