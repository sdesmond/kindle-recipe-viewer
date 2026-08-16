#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
export RV_APP_ROOT="$ROOT/extensions/RecipeViewer"
export RV_LIBRARY_ROOT="$ROOT/tests/fixtures/library"
export RV_LOG="$TMP_ROOT/debug.log"
export RV_TMP="$TMP_ROOT/recipe-viewer.test"
export RV_FONT_REGULAR="$RV_APP_ROOT/fonts/AtkinsonHyperlegible-Regular.ttf"
export RV_FONT_BOLD="$RV_APP_ROOT/fonts/AtkinsonHyperlegible-Bold.ttf"
export RV_DISPLAY_COMMAND="$ROOT/tests/helpers/display_logger.sh"
export RV_DISPLAY_LOG="$TMP_ROOT/display.log"
export RV_TOUCH_SOURCE="$ROOT/tests/fixtures/library/manifest.tsv"
mkdir -p "$RV_TMP"
: > "$RV_LOG"
: > "$RV_DISPLAY_LOG"

. "$RV_APP_ROOT/lib/core.sh"
. "$RV_APP_ROOT/lib/touch.sh"
. "$RV_APP_ROOT/lib/ui.sh"

rv_reset_session

failures=0
assert_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "FAIL: ${3:-assert_eq}: expected [$2], got [$1]" >&2
        failures=$((failures + 1))
    fi
}
assert_contains() {
    if ! grep -Fq -- "$2" "$1"; then
        echo "FAIL: ${3:-assert_contains}: missing [$2] in $1" >&2
        failures=$((failures + 1))
    fi
}
assert_not_contains() {
    if grep -Fq -- "$2" "$1"; then
        echo "FAIL: ${3:-assert_not_contains}: unexpected [$2] in $1" >&2
        failures=$((failures + 1))
    fi
}

# Manifest loading parses records rather than sourcing data.
rv_manifest_load
assert_eq "$RV_RECIPE_COUNT" 2 "manifest count"
rv_recipe_field 2
assert_eq "$RV_RECIPE_TITLE" "Zesty Soup" "manifest title"
RV_SEARCH_QUERY=
RV_LIST_SCROLL=0
rv_filter_recipes
assert_eq "$RV_FILTERED_COUNT" 2 "empty search includes all recipes"
RV_SEARCH_QUERY='sOuP'
rv_filter_recipes
assert_eq "$RV_FILTERED_COUNT" 1 "search is case insensitive"
assert_eq "$(cut -f1 "$RV_FILTERED_LIST")" 2 "filter retains manifest ordinal"
RV_SEARCH_QUERY='no such recipe'
rv_filter_recipes
assert_eq "$RV_FILTERED_COUNT" 0 "search can return no matches"
RV_SEARCH_QUERY=
rv_filter_recipes

# Navigation clamps.
rv_clamp -4 0 10; assert_eq "$RV_CLAMPED" 0 "lower clamp"
rv_clamp 40 0 10; assert_eq "$RV_CLAMPED" 10 "upper clamp"

# Resume detection distinguishes a normal ~1s poll cycle from the wall-clock
# jump the Kindle's suspend/resume leaves behind mid-cycle.
rv_detect_resume 100 101 5 && { echo "FAIL: normal poll gap treated as a resume" >&2; failures=$((failures + 1)); }
rv_detect_resume 100 106 5 || { echo "FAIL: large wall-clock gap not detected as a resume" >&2; failures=$((failures + 1)); }
rv_detect_resume 0 106 5 && { echo "FAIL: invalid before-timestamp still triggered a resume" >&2; failures=$((failures + 1)); }

# Gesture classification.
rv_classify_gesture 100 200 105 205 900; assert_eq "$RV_GESTURE" hold "hold"
rv_classify_gesture 100 500 100 300 200; assert_eq "$RV_GESTURE" swipe-up "swipe up"
rv_classify_gesture 100 200 102 202 100; assert_eq "$RV_GESTURE" tap "tap"

# Little-endian hex-byte-to-decimal conversion, done in pure arithmetic
# (no fork) since it runs up to three times per captured touch record.
rv_hex_le32 64 00 00 00; assert_eq "$RV_HEX32" 100 "hex32 low byte"
rv_hex_le32 ff ff ff ff; assert_eq "$RV_HEX32" 4294967295 "hex32 all bytes set"

# Decode the Kindle's 16-byte, little-endian input_event records.
touch_fixture="$TMP_ROOT/touch.bin"
printf '%b' \
    '\x0a\x00\x00\x00\x00\x00\x00\x00\x03\x00\x35\x00\x64\x00\x00\x00' \
    '\x0a\x00\x00\x00\xe8\x03\x00\x00\x03\x00\x36\x00\xc8\x00\x00\x00' \
    '\x0a\x00\x00\x00\x40\x0d\x03\x00\x03\x00\x36\x00\x50\x00\x00\x00' \
    '\x0a\x00\x00\x00\xe0\x93\x04\x00\x03\x00\x39\x00\xff\xff\xff\xff' \
    > "$touch_fixture"
rv_decode_touch_file "$touch_fixture"
assert_eq "$RV_X1,$RV_Y1" "100,200" "touch start decode"
assert_eq "$RV_X2,$RV_Y2" "100,80" "touch end decode"
assert_eq "$RV_DURATION_MS" 300 "touch duration decode"
RV_TOUCH_ROTATION=L
rv_decode_touch_file "$touch_fixture"
assert_eq "$RV_X1,$RV_Y1" "200,657" "landscape touch start transform"
assert_eq "$RV_X2,$RV_Y2" "80,657" "landscape touch end transform"
RV_TOUCH_ROTATION=U

# Recipe layout and positional duplicate checks.
rv_load_recipe 2
assert_eq "$RV_INGREDIENT_ROWS" 5 "ingredient rows"
assert_eq "$(sed -n '2p' "$RV_TMP/instructions.layout" | cut -f3)" "Stir the Ragu Base into the water." "instruction wrap boundary"
assert_eq "$(sed -n '2p' "$RV_TMP/instructions.layout" | cut -f4)" 1 "instruction first-line marker"
assert_eq "$(sed -n '3p' "$RV_TMP/instructions.layout" | cut -f4)" 0 "instruction continuation marker"
rv_toggle_check 2
rv_checked_has 2 || { echo "FAIL: positional check absent" >&2; failures=$((failures + 1)); }
rv_checked_has 3 && { echo "FAIL: duplicate text shared a check" >&2; failures=$((failures + 1)); }

# Header hit ignores taps; item hit sets pane-local cursor/check.
RV_REDRAW=none; RV_GESTURE=tap; RV_X1=50; RV_Y2=$RV_CONTENT_TOP
rv_handle_cook_gesture
assert_eq "$RV_INGREDIENT_CURSOR" -1 "header tap ignored"
RV_Y2=$((RV_CONTENT_TOP + RV_INGREDIENT_LINE_H))
rv_handle_cook_gesture
assert_eq "$RV_INGREDIENT_CURSOR" 2 "ingredient row hit"
assert_eq "$RV_REDRAW,$RV_REDRAW_WAVEFORM" "ingredients,DU" "ingredient tap refresh intent"

# A linked ingredient (fixture 0002.recipe record 5, "1/2 tsp salt" pinned to
# fixture-a i.e. Apple Pie) has no competing tap action, so unlike an
# instruction link the whole row counts, even a tap past the visible text.
RV_ROW5_Y=$((RV_CONTENT_TOP + 4 * RV_INGREDIENT_LINE_H + RV_INGREDIENT_ITEM_GAP))
rv_layout_hit "$RV_TMP/ingredients.layout" 250 "$RV_ROW5_Y" 0 "$RV_INGREDIENT_LINE_H" ingredients 10 "$RV_INGREDIENT_ITEM_GAP"
assert_eq "$RV_HIT_RECORD,$RV_HIT_KIND,$RV_HIT_LINK" "5,item,fixture-a" "ingredient link hit is not x-gated"
RV_REDRAW=none; RV_GESTURE=tap; RV_X1=250; RV_X2=250; RV_Y2=$RV_ROW5_Y
rv_handle_cook_gesture
assert_eq "$RV_SELECTED_ORDINAL" 1 "tapping a linked ingredient navigates to its target recipe"
assert_eq "$RV_RECORD_TITLE" "Apple Pie" "navigated recipe is loaded"
assert_eq "$RV_NAV_STACK" 2 "navigating via an ingredient link remembers the originating ordinal"
RV_NAV_STACK=
rv_load_recipe 2
rv_checked_has 5 && { echo "FAIL: linked ingredient should never gain a check" >&2; failures=$((failures + 1)); }

# Instruction hit testing accounts for the small gap between steps.
RV_LINK_TEXT_X=$((RV_INSTRUCTION_X + 16))
rv_layout_hit "$RV_TMP/instructions.layout" 400 230 0 "$RV_INSTRUCTION_LINE_H" instructions "$RV_LINK_TEXT_X" "$RV_INSTRUCTION_STEP_GAP"
assert_eq "$RV_HIT_KIND" "" "instruction gap ignores tap"
rv_layout_hit "$RV_TMP/instructions.layout" 400 240 0 "$RV_INSTRUCTION_LINE_H" instructions "$RV_LINK_TEXT_X" "$RV_INSTRUCTION_STEP_GAP"
assert_eq "$RV_HIT_RECORD,$RV_HIT_KIND" "3,item" "instruction after-gap hit"
assert_eq "$RV_HIT_LINK" "" "non-linked instruction has no link target"

# Only the resolved phrase within a linked step is tappable (fixture
# 0002.recipe record 2 links the phrase "Ragu Base" to fixture-a, i.e. Apple
# Pie); tapping the same step elsewhere behaves like a plain instruction tap.
RV_LINK_Y=$((RV_CONTENT_TOP + RV_INSTRUCTION_LINE_H))
rv_layout_hit "$RV_TMP/instructions.layout" 340 "$RV_LINK_Y" 0 "$RV_INSTRUCTION_LINE_H" instructions "$RV_LINK_TEXT_X" "$RV_INSTRUCTION_STEP_GAP"
assert_eq "$RV_HIT_RECORD,$RV_HIT_KIND,$RV_HIT_LINK" "2,item," "tap on the step but off the phrase has no link"
rv_layout_hit "$RV_TMP/instructions.layout" 500 "$RV_LINK_Y" 0 "$RV_INSTRUCTION_LINE_H" instructions "$RV_LINK_TEXT_X" "$RV_INSTRUCTION_STEP_GAP"
assert_eq "$RV_HIT_RECORD,$RV_HIT_KIND,$RV_HIT_LINK" "2,item,fixture-a" "tap on the phrase exposes the target uid"
rv_uid_ordinal fixture-a
assert_eq "$RV_UID_ORDINAL" 1 "link uid resolves to its manifest ordinal"

# Tapping the same step off the phrase still just highlights it as usual.
RV_REDRAW=none; RV_GESTURE=tap; RV_X1=500; RV_X2=340; RV_Y2=$RV_LINK_Y
rv_handle_cook_gesture
assert_eq "$RV_INSTRUCTION_CURSOR" 2 "off-phrase tap on a linked step sets cursor instead of navigating"
assert_eq "$RV_SCREEN" cook "off-phrase tap stays on the same recipe"

# Tapping the phrase itself navigates and remembers where we came from.
RV_REDRAW=none; RV_INSTRUCTION_CURSOR=-1; RV_X1=500; RV_X2=500; RV_Y2=$RV_LINK_Y
rv_handle_cook_gesture
assert_eq "$RV_SELECTED_ORDINAL" 1 "tapping the linked phrase navigates to its target recipe"
assert_eq "$RV_RECORD_TITLE" "Apple Pie" "navigated recipe is loaded"
assert_eq "$RV_REDRAW" full "linked navigation requests a full redraw"
assert_eq "$RV_NAV_STACK" 2 "navigating via a link remembers the originating ordinal"

# The back button (top-left title bar) returns to the recipe the link came from.
RV_REDRAW=none; RV_GESTURE=tap; RV_X1=10; RV_Y2=20
rv_handle_cook_gesture
assert_eq "$RV_SELECTED_ORDINAL" 2 "back button returns to the originating recipe"
assert_eq "$RV_RECORD_TITLE" "Zesty Soup" "back navigation reloads the originating recipe"
assert_eq "$RV_REDRAW" full "back navigation requests a full redraw"
assert_eq "$RV_NAV_STACK" "" "back navigation empties the stack once exhausted"

# Opening a recipe fresh from the list clears any stale back-navigation stack.
RV_NAV_STACK=99
RV_GESTURE=tap; RV_Y2=$((RV_LIST_TOP + RV_LIST_ROW_H + 10))
rv_handle_list_gesture
assert_eq "$RV_NAV_STACK" "" "opening a recipe from the list clears the back stack"

rv_load_recipe 2

# Pane scrolling remains independent and clamps.
RV_INGREDIENT_MAX_SCROLL=20; RV_INSTRUCTION_MAX_SCROLL=30
RV_INGREDIENT_SCROLL=0; RV_INSTRUCTION_SCROLL=0
RV_REDRAW=none; RV_GESTURE=swipe-up; RV_X1=100; RV_Y2=400
rv_handle_cook_gesture
assert_eq "$RV_INGREDIENT_SCROLL" 5 "ingredient scroll"
assert_eq "$RV_INSTRUCTION_SCROLL" 0 "instruction scroll independence"
assert_eq "$RV_REDRAW,$RV_REDRAW_WAVEFORM" "ingredients,GC16" "ingredient scroll refresh intent"
RV_X1=500
rv_handle_cook_gesture
assert_eq "$RV_INSTRUCTION_SCROLL" 5 "instruction scroll"
assert_eq "$RV_REDRAW,$RV_REDRAW_WAVEFORM" "instructions,GC16" "instruction scroll refresh intent"

# The back button is always present; at the root of the nav stack (no link
# history) it takes over END RECIPE's old job and still asks first. Cancel
# preserves progress and confirmation clears it.
assert_eq "$RV_NAV_STACK" "" "root recipe has no back-nav history"
RV_GESTURE=tap; RV_X1=10; RV_Y2=20; RV_INGREDIENT_CHECKS=',2,'
rv_handle_cook_gesture
assert_eq "$RV_SCREEN" confirm "back button at the root opens end confirmation"
assert_eq "$RV_INGREDIENT_CHECKS" ',2,' "confirmation preserves checks"
RV_X2=$RV_CONFIRM_CANCEL_X; RV_Y2=$((RV_CONFIRM_BUTTON_Y + 20))
rv_handle_confirm_gesture
assert_eq "$RV_SCREEN" cook "cancel returns to recipe"
assert_eq "$RV_INGREDIENT_CHECKS" ',2,' "cancel preserves checks"
RV_GESTURE=tap; RV_X1=10; RV_Y2=20
rv_handle_cook_gesture
RV_X2=$RV_CONFIRM_END_X; RV_Y2=$((RV_CONFIRM_BUTTON_Y + 20))
rv_handle_confirm_gesture
assert_eq "$RV_SCREEN" list "confirmed end returns to list"
assert_eq "$RV_INGREDIENT_CHECKS" ',' "confirmed end clears checks"

# Golden geometry, calculated 212-DPI advances, and title truncation.
rv_load_recipe 2
rv_toggle_check 2
RV_INGREDIENT_CURSOR=2
: > "$RV_DISPLAY_LOG"
rv_draw_cook
assert_contains "$RV_DISPLAY_LOG" $'rect\t300\t66\t2\t948' "pane geometry"
assert_contains "$RV_DISPLAY_LOG" $'rect\t0\t1014\t758\t2' "content-bottom rule geometry"
assert_not_contains "$RV_DISPLAY_LOG" $'END RECIPE' "END RECIPE bar is gone; the back button replaced it"
assert_contains "$RV_DISPLAY_LOG" $'rect\t6\t4\t56\t2' "back button box is always drawn"
assert_contains "$RV_DISPLAY_LOG" $'text\t24\t5\t19\tbold\t<' "back button arrow is vertically centered"
assert_eq "$(rv_pxh "$RV_INGREDIENT_PT" "$RV_INGREDIENT_LEADING")" 34 "ingredient line height"
assert_eq "$(rv_pxh "$RV_INSTRUCTION_PT" "$RV_INSTRUCTION_LEADING")" 39 "instruction line height"
rv_truncate "1234567890" 8; assert_eq "$RV_TRUNCATED" "12345..." "title truncation"
assert_not_contains "$RV_DISPLAY_LOG" $'text\t10\t144\t13\tbold\tX' "checked ingredient no longer uses margin X"
assert_contains "$RV_DISPLAY_LOG" $'text\t10\t144\t13\tregular\t1 cup water' "ingredient flush-left placement"
assert_contains "$RV_DISPLAY_LOG" $'rect\t10\t164\t140\t2' "ingredient strikethrough placement"
assert_contains "$RV_DISPLAY_LOG" $'rect\t10\t298\t136\t2' "linked ingredient underlines the whole row"
assert_contains "$RV_DISPLAY_LOG" $'rect\t417\t185\t131\t2' "linked instruction underline covers only the phrase"
assert_not_contains "$RV_DISPLAY_LOG" $'rect\t318\t185\t412\t2' "underline no longer spans the whole step"
assert_not_contains "$RV_DISPLAY_LOG" $'rect\t3\t149\t3\t37' "ingredient cursor gutter removed"
assert_contains "$RV_DISPLAY_LOG" $'text\t318\t237\t13\tregular\tSimmer for 10 minutes.' "instruction step gap"
if awk -F '\t' '$1 == "text" && ($2 == 10 || $2 == 318) && $3 >= 1014 { found=1 } END { exit !found }' "$RV_DISPLAY_LOG"; then
    echo "FAIL: body text crossed the content bottom boundary" >&2
    failures=$((failures + 1))
fi

# The list uses larger type and 64px touch rows.
: > "$RV_DISPLAY_LOG"
RV_LIST_SCROLL=0
rv_draw_list
assert_contains "$RV_DISPLAY_LOG" $'text\t15\t136\t17\tregular\tApple Pie' "large recipe list type"
assert_contains "$RV_DISPLAY_LOG" $'text\t25\t78\t15\tregular\tSearch recipes...' "search bar placeholder"
assert_contains "$RV_DISPLAY_LOG" $'rect\t6\t4\t56\t2' "list back button box is drawn"
assert_contains "$RV_DISPLAY_LOG" $'text\t24\t5\t19\tbold\t<' "list back button arrow is vertically centered"
RV_GESTURE=tap; RV_Y2=$((RV_LIST_TOP + RV_LIST_ROW_H + 10))
rv_handle_list_gesture
assert_eq "$RV_SELECTED_ORDINAL" 2 "large list row hit"

# The list's back button has no recipe to unwind to, so it exits the app.
RV_SCREEN=list; RV_GESTURE=tap; RV_X1=10; RV_Y2=20
rv_handle_list_gesture
assert_eq "$RV_SCREEN" exit "list back button requests app exit"

# The search bar opens a touch keyboard, filters immediately, and maps results
# back to their original manifest ordinal.
RV_SCREEN=list; RV_GESTURE=tap; RV_Y2=$((RV_SEARCH_BAR_Y + 10))
rv_handle_list_gesture
assert_eq "$RV_SCREEN" search "search bar opens keyboard"
RV_X2=130; RV_Y2=$((RV_KEYBOARD_TOP + 200)); RV_GESTURE=tap
rv_handle_search_gesture
assert_eq "$RV_SEARCH_QUERY" z "touch keyboard letter"
assert_eq "$RV_FILTERED_COUNT" 1 "keyboard filters immediately"
RV_X2=100; RV_Y2=$((RV_SEARCH_RESULTS_TOP + 10))
rv_handle_search_gesture
assert_eq "$RV_SCREEN" cook "filtered result opens recipe"
assert_eq "$RV_SELECTED_ORDINAL" 2 "filtered result ordinal"

# Search rendering has large keys and updates without a flashing full refresh.
: > "$RV_DISPLAY_LOG"
RV_SCREEN=search
rv_draw_search
assert_contains "$RV_DISPLAY_LOG" $'rect\t9\t500\t70\t2' "search keyboard key"
assert_contains "$RV_DISPLAY_LOG" $'text\t620\t837\t14\tbold\tDONE' "search done control"
: > "$RV_DISPLAY_LOG"
RV_PARTIAL_COUNT=0
rv_draw_search_partial
assert_contains "$RV_DISPLAY_LOG" $'refresh-region\t0\t0\t758\t500\tGC16' "search partial refresh"
assert_not_contains "$RV_DISPLAY_LOG" $'refresh\t0\t0\t758\t1024' "search typing avoids full refresh"

# The confirmation screen provides two large, independently hittable actions.
: > "$RV_DISPLAY_LOG"
rv_draw_confirm
assert_contains "$RV_DISPLAY_LOG" $'text\t70\t225\t21\tbold\tEnd this recipe?' "confirmation heading"
assert_contains "$RV_DISPLAY_LOG" $'rect\t60\t650\t300\t3' "cancel button"
assert_contains "$RV_DISPLAY_LOG" $'rect\t398\t650\t300\t3' "end button"

# Same-screen actions clear and refresh only the affected pane without flashing.
: > "$RV_DISPLAY_LOG"
RV_PARTIAL_COUNT=0
rv_draw_cook_pane_partial ingredients DU
assert_contains "$RV_DISPLAY_LOG" $'clear-region\t0\t110\t300\t904' "ingredient partial clear"
assert_contains "$RV_DISPLAY_LOG" $'refresh-region\t0\t110\t300\t904\tDU' "ingredient partial refresh"
assert_not_contains "$RV_DISPLAY_LOG" $'refresh\t0\t0\t758\t1024' "ingredient partial avoids full refresh"

: > "$RV_DISPLAY_LOG"
rv_draw_cook_pane_partial instructions GC16
assert_contains "$RV_DISPLAY_LOG" $'clear-region\t302\t110\t456\t904' "instruction partial clear"
assert_contains "$RV_DISPLAY_LOG" $'refresh-region\t302\t110\t456\t904\tGC16' "instruction partial refresh"

# Periodic cleanup falls back to a full flashing refresh.
: > "$RV_DISPLAY_LOG"
RV_PARTIAL_COUNT=$RV_PARTIAL_FULL_EVERY
rv_draw_cook_pane_partial ingredients DU
assert_contains "$RV_DISPLAY_LOG" $'refresh\t0\t0\t758\t1024' "partial cleanup full refresh"
assert_eq "$RV_PARTIAL_COUNT" 0 "full refresh resets partial count"

# Dependency failures are actionable.
saved_regular=$RV_FONT_REGULAR
RV_FONT_REGULAR="$TMP_ROOT/missing.ttf"
if rv_check_dependencies; then
    echo "FAIL: missing font dependency succeeded" >&2
    failures=$((failures + 1))
else
    [[ "$RV_ERROR" == regular\ font\ missing:* ]] || { echo "FAIL: non-actionable dependency error: $RV_ERROR" >&2; failures=$((failures + 1)); }
fi
RV_FONT_REGULAR=$saved_regular

saved_display=$RV_DISPLAY_COMMAND
RV_DISPLAY_COMMAND="$TMP_ROOT/missing-display"
if rv_check_dependencies; then
    echo "FAIL: missing display override succeeded" >&2
    failures=$((failures + 1))
else
    [[ "$RV_ERROR" == display\ override\ is\ not\ executable:* ]] || { echo "FAIL: non-actionable display error: $RV_ERROR" >&2; failures=$((failures + 1)); }
fi
RV_DISPLAY_COMMAND=$saved_display

# Manifest mismatch fails closed.
bad_library="$TMP_ROOT/bad-library"
mkdir -p "$bad_library"
printf 'SCHEMA\t1\nCOUNT\t1\n' > "$bad_library/manifest.tsv"
saved_library=$RV_LIBRARY_ROOT
RV_LIBRARY_ROOT=$bad_library
if rv_manifest_load; then
    echo "FAIL: malformed manifest succeeded" >&2
    failures=$((failures + 1))
fi
RV_LIBRARY_ROOT=$saved_library

# End-to-end host launch consumes an overridden touch capture. There is no
# idle timeout, so the fixture taps the list screen's back button (top-left,
# X<64, Y<RV_TITLE_H) to make the app exit on its own.
exit_touch_fixture="$TMP_ROOT/touch-exit.bin"
printf '%b' \
    '\x0a\x00\x00\x00\x00\x00\x00\x00\x03\x00\x35\x00\x14\x00\x00\x00' \
    '\x0a\x00\x00\x00\x00\x00\x00\x00\x03\x00\x36\x00\x14\x00\x00\x00' \
    '\x0a\x00\x00\x00\xa0\x86\x01\x00\x03\x00\x39\x00\xff\xff\xff\xff' \
    > "$exit_touch_fixture"
integration_tmp="$TMP_ROOT/recipe-viewer.integration"
RV_TOUCH_EVENT_FILE="$exit_touch_fixture" RV_TOUCH_ROTATION=U RV_TMP="$integration_tmp" \
    RV_DISPLAY_DIAGNOSTIC="mock display diagnostic" \
    timeout 10 /usr/bin/sh "$RV_APP_ROOT/bin/recipe_viewer.sh"
assert_contains "$RV_LOG" "=== launch" "integration launch log"
assert_contains "$RV_LOG" "gesture kind=tap" "integration gesture log"
assert_contains "$RV_LOG" "exit requested from recipe list" "integration back-button exit"
assert_contains "$RV_LOG" "returning to the Kindle Home screen" "integration exit log"
assert_contains "$RV_LOG" "mock display diagnostic" "display diagnostics redirected"

if (( failures > 0 )); then
    echo "$failures runtime test(s) failed" >&2
    exit 1
fi
echo "runtime shell tests passed"
