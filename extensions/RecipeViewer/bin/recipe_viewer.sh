#!/bin/sh

RV_APP_ROOT=${RV_APP_ROOT:-/mnt/us/extensions/RecipeViewer}
RV_LIBRARY_ROOT=${RV_LIBRARY_ROOT:-$RV_APP_ROOT/library}
RV_LOG=${RV_LOG:-$RV_APP_ROOT/debug.log}
RV_PARTIAL_REFRESH=${RV_PARTIAL_REFRESH:-1}
RV_PARTIAL_FULL_EVERY=${RV_PARTIAL_FULL_EVERY:-12}
RV_INSTRUCTION_STEP_GAP=${RV_INSTRUCTION_STEP_GAP:-10}
RV_WAKE_GAP_SECONDS=${RV_WAKE_GAP_SECONDS:-4}
RV_TOUCH_ROTATION=${RV_TOUCH_ROTATION:-U}
RV_TOUCH_SOURCE=${RV_TOUCH_EVENT_FILE:-/dev/input/event1}
RV_FONT_REGULAR=${RV_FONT_REGULAR:-$RV_APP_ROOT/fonts/AtkinsonHyperlegible-Regular.ttf}
RV_FONT_BOLD=${RV_FONT_BOLD:-$RV_APP_ROOT/fonts/AtkinsonHyperlegible-Bold.ttf}
RV_TMP=${RV_TMP:-/tmp/recipe-viewer.$$}

. "$RV_APP_ROOT/lib/core.sh" || exit 1
. "$RV_APP_ROOT/lib/touch.sh" || exit 1
. "$RV_APP_ROOT/lib/ui.sh" || exit 1

mkdir -p "$RV_TMP" || exit 1
rv_cleanup()
{
    case "$RV_TMP" in
        */recipe-viewer.*)
            rm -f "$RV_TMP/recipes.tsv" "$RV_TMP/touch-events.bin" \
                "$RV_TMP/recipes.filtered.tsv" "$RV_TMP/ingredients.layout" \
                "$RV_TMP/instructions.layout"
            rmdir "$RV_TMP" 2>/dev/null
            ;;
    esac
}
rv_shutdown()
{
    rv_cleanup
}
trap 'rv_shutdown' 0
trap 'exit 1' 1 2 15
: >> "$RV_LOG" || exit 1
# The Kindle's script-book launcher displays uncaptured stdout/stderr on the
# framebuffer. FBInk is intentionally verbose, so capture every child process
# before the first dependency check or draw to keep diagnostics off-screen.
exec >> "$RV_LOG" 2>&1
rv_log "=== launch app_root=$RV_APP_ROOT library_root=$RV_LIBRARY_ROOT ==="

if ! rv_check_dependencies; then
    rv_error_screen "$RV_ERROR"
    exit 1
fi

RV_SCREEN=list
RV_LIST_SCROLL=0
RV_REPLAY_CONSUMED=0
RV_SEARCH_QUERY=
rv_reset_session
rv_filter_recipes
RV_SCREEN=list
rv_draw_list

# Runs until the back button on the recipe list requests an exit; there is
# no idle timeout, so the app only closes when the reader asks it to.
RV_TICK=$(date +%s 2>/dev/null || echo 0)
while :; do
    RV_TICK_BEFORE=$RV_TICK
    RV_CAPTURED=0
    rv_capture_gesture && RV_CAPTURED=1
    RV_TICK=$(date +%s 2>/dev/null || echo 0)
    # The Kindle's suspend/resume leaves the e-ink panel blank/stale, and this
    # app has no other way to learn it happened, so a wall-clock jump across
    # one ~1s poll cycle stands in for a resume notification.
    if rv_detect_resume "$RV_TICK_BEFORE" "$RV_TICK" "$RV_WAKE_GAP_SECONDS"; then
        rv_log "resume detected after sleep; forcing full refresh"
        case "$RV_SCREEN" in
            list) rv_draw_list ;;
            search) rv_draw_search ;;
            cook) rv_draw_cook ;;
            confirm) rv_draw_confirm ;;
        esac
        continue
    fi
    if [ "$RV_CAPTURED" -eq 1 ]; then
        RV_SCREEN_BEFORE=$RV_SCREEN
        RV_REDRAW=none
        RV_REDRAW_WAVEFORM=DU
        case "$RV_SCREEN" in
            list) rv_handle_list_gesture ;;
            search) rv_handle_search_gesture ;;
            cook) rv_handle_cook_gesture ;;
            confirm) rv_handle_confirm_gesture ;;
        esac
        if [ "$RV_SCREEN" = exit ]; then
            break
        fi
        if [ "$RV_SCREEN" != "$RV_SCREEN_BEFORE" ] || [ "$RV_REDRAW" = full ]; then
            case "$RV_SCREEN" in
                list) rv_draw_list ;;
                search) rv_draw_search ;;
                cook) rv_draw_cook ;;
                confirm) rv_draw_confirm ;;
            esac
        else
            case "$RV_REDRAW" in
                list) rv_draw_list_partial ;;
                search) rv_draw_search_partial ;;
                ingredients|instructions) rv_draw_cook_pane_partial "$RV_REDRAW" "$RV_REDRAW_WAVEFORM" ;;
            esac
        fi
    fi
done
rv_log "exit requested from recipe list; returning to the Kindle Home screen"
exit 0
