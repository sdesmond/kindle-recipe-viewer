# Kindle Recipe Viewer — Agent Instructions

This repository targets a Kindle Paperwhite 2 running firmware 5.12.2.2.
The device runtime must remain POSIX `sh`; the Kindle has neither Python nor
BusyBox. Keep host-side compilation and deployment separate from the deployed
runtime.

Before changing the Kindle runtime, display, touch handling, or deployment,
read [`.agents/memories/MEMORY.md`](.agents/memories/MEMORY.md) and the runtime
memory it links. Record new durable hardware findings there rather than
duplicating them in this file.

Record durable hardware findings in `.agents/memories/` and link every memory
from `.agents/memories/MEMORY.md`.

