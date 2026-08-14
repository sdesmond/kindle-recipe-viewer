#!/bin/sh
printf '%s' "$1" >> "$RV_DISPLAY_LOG"
shift
for RV_ARGUMENT do
    printf '\t%s' "$RV_ARGUMENT" >> "$RV_DISPLAY_LOG"
done
printf '\n' >> "$RV_DISPLAY_LOG"
[ -z "${RV_DISPLAY_DIAGNOSTIC:-}" ] || printf '%s\n' "$RV_DISPLAY_DIAGNOSTIC" >&2
