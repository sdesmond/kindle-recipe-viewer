#!/bin/sh
RV_BOOT_LOG=/mnt/us/extensions/RecipeViewer/debug.log
printf '%s launcher entered\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" >> "$RV_BOOT_LOG" 2>/dev/null
exec /bin/sh /mnt/us/extensions/RecipeViewer/bin/recipe_viewer.sh >> "$RV_BOOT_LOG" 2>&1
