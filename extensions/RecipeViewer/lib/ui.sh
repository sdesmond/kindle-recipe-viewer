#!/bin/sh
# Full-refresh drawing, wrapping, hit testing, and screen event reducers.

rv_display()
{
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then
        "$RV_DISPLAY_COMMAND" "$@"
    fi
}

rv_clear()
{
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then rv_display clear 0 0 "$RV_SCREEN_W" "$RV_SCREEN_H"
    else "$RV_EIPS" -c; fi
}

rv_refresh()
{
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then rv_display refresh 0 0 "$RV_SCREEN_W" "$RV_SCREEN_H"
    else "$RV_EIPS" -s "w=$RV_SCREEN_W,h=$RV_SCREEN_H" -f; fi
}

rv_clear_region()
{
    # $1=x $2=y $3=width $4=height. Change framebuffer pixels without refreshing.
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then
        rv_display clear-region "$1" "$2" "$3" "$4"
    else
        "$RV_FBINK" -q -b -k "top=$2,left=$1,width=$3,height=$4"
    fi
}

rv_refresh_region()
{
    # $1=x $2=y $3=width $4=height $5=waveform.
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then
        rv_display refresh-region "$1" "$2" "$3" "$4" "$5"
    else
        "$RV_FBINK" -q -w -s "top=$2,left=$1,width=$3,height=$4" -W "$5"
    fi
}

rv_rect()
{
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then rv_display rect "$1" "$2" "$3" "$4"
    else "$RV_EIPS" -d "l=0,w=$3,h=$4" -x "$1" -y "$2"; fi
}

rv_text()
{
    RV_TEXT_FONT=$RV_FONT_REGULAR
    [ "$4" = bold ] && RV_TEXT_FONT=$RV_FONT_BOLD
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then
        rv_display text "$1" "$2" "$3" "$4" "$5"
    else
        "$RV_FBINK" -b -t "regular=$RV_TEXT_FONT,size=$3,top=$2,left=$1" "$5"
    fi
}

rv_error_screen()
{
    rv_log "failure $1"
    if [ -n "${RV_DISPLAY_COMMAND:-}" ] || { [ -x "${RV_FBINK:-}" ] && [ -x "${RV_EIPS:-}" ]; }; then
        rv_clear
        rv_text 15 20 18 bold "Recipe Viewer error"
        rv_truncate "$1" 46
        rv_text 15 90 12 regular "$RV_TRUNCATED"
        rv_text 15 150 11 regular "See extensions/RecipeViewer/debug.log"
        rv_refresh
    elif [ -x "${RV_EIPS:-}" ]; then
        "$RV_EIPS" -c
        "$RV_EIPS" 2 2 "Recipe Viewer error"
        "$RV_EIPS" 2 4 "$1"
        "$RV_EIPS" 2 6 "See extensions/RecipeViewer/debug.log"
        "$RV_EIPS" -f
    elif [ -x "${RV_FBINK:-}" ] && [ -r "${RV_FONT_REGULAR:-}" ]; then
        "$RV_FBINK" -t "regular=$RV_FONT_REGULAR,size=12,top=20,left=15" "Recipe Viewer error: $1"
    fi
}

rv_build_layout()
{
    # $1 recipe file, $2 record type, $3 max width in 35px-font units, $4 output.
    # Paprika text is normalized to ASCII. These Atkinson Hyperlegible metrics
    # keep wrapping close to the visible pane edge instead of guessing by count.
    awk -F '\t' -v wanted="$2" -v width="$3" '
    function glyph(c) {
        if (c == " ") return 10
        if (index(".,;:", c)) return 7
        if (c == sprintf("%c", 39) || c == "!") return 7
        if (index("ijl", c)) return 9
        if (index("()", c)) return 10
        if (index("ft", c)) return 11
        if (c == "r") return 12
        if (c == "-") return 13
        if (c == "/" || c == "1" || c == "I") return 14
        if (index("svyz", c)) return 16
        if (index("ckx", c)) return 17
        if (c == "a" || c == "J" || c == "7") return 18
        if (index("ehnou", c) || index("FL2", c)) return 19
        if (index("bdgpq", c) || index("ET3", c)) return 20
        if (index("BPRS", c) || index("4569", c)) return 21
        if (index("AKVX", c) || c == "8") return 22
        if (index("CD0", c)) return 23
        if (index("GHNUw", c)) return 24
        if (index("OQ", c)) return 25
        if (c == "&") return 26
        if (c == "M") return 29
        if (index("mW", c)) return 30
        return 18
    }
    function measured(text,    i, total) {
        total = 0
        for (i = 1; i <= length(text); i++) total += glyph(substr(text, i, 1))
        return total
    }
    function emit_row(idx, kind, rowtext, first, link, phrase,    p, row_link, row_prefix, row_phrase_w) {
        # With a phrase given (instruction steps), only that located phrase
        # becomes a tap/underline target, so the rest of the step still reads
        # as plain text. With no phrase (ingredient links, which have no
        # competing tap action to preserve), the whole wrapped row is the
        # target on every row it spans.
        row_link = ""
        row_prefix = ""
        row_phrase_w = ""
        if (phrase != "") {
            p = index(rowtext, phrase)
            if (p > 0) {
                row_link = link
                row_prefix = measured(substr(rowtext, 1, p - 1))
                row_phrase_w = measured(phrase)
            }
        } else if (link != "") {
            row_link = link
            row_prefix = 0
            row_phrase_w = measured(rowtext)
        }
        print idx "\t" kind "\t" rowtext "\t" first "\t" measured(rowtext) "\t" row_link "\t" row_prefix "\t" row_phrase_w
    }
    function emit(idx, kind, text, link, phrase,    rest, pos, last_space, line, first, i, used, c) {
        rest = text
        line = ""
        first = 1
        while (length(rest) > 0) {
            sub(/^[ ]+/, "", rest)
            if (measured(rest) <= width) {
                emit_row(idx, kind, rest, first, link, phrase)
                return
            }
            used = 0
            last_space = 0
            pos = 1
            for (i = 1; i <= length(rest); i++) {
                c = substr(rest, i, 1)
                if (used + glyph(c) > width) { pos = i - 1; break }
                used += glyph(c)
                if (c == " ") last_space = i
                pos = i
            }
            if (last_space > 1) pos = last_space - 1
            if (pos < 1) pos = 1
            line = substr(rest, 1, pos)
            sub(/[ ]+$/, "", line)
            emit_row(idx, kind, line, first, link, phrase)
            first = 0
            rest = substr(rest, pos + 1)
        }
    }
    $1 == wanted { record_index++; emit(record_index, $2, $3, $4, $5) }
    ' "$1" > "$4"
}

rv_load_recipe()
{
    RV_SELECTED_ORDINAL=$1
    rv_recipe_field "$RV_SELECTED_ORDINAL"
    RV_ACTIVE_RECIPE="$RV_LIBRARY_ROOT/$RV_RECIPE_FILE"
    RV_RECORD_TITLE=$(sed -n 's/^TITLE\t//p' "$RV_ACTIVE_RECIPE" | sed -n '1p')
    [ -n "$RV_RECORD_TITLE" ] || { RV_ERROR="recipe title missing: $RV_RECIPE_FILE"; return 1; }
    RV_INGREDIENT_FONT_PX=$(rv_pxh "$RV_INGREDIENT_PT" 0)
    RV_INSTRUCTION_FONT_PX=$(rv_pxh "$RV_INSTRUCTION_PT" 0)
    # FBInk's Kindle rasterizer is measurably narrower than the host-side font
    # metrics. The device-calibrated percentage makes useful lines approach the
    # right margin while retaining a small safety inset.
    RV_INGREDIENT_WRAP=$(((RV_INGREDIENT_W - 20) * 35 * RV_FONT_WIDTH_PERCENT / (RV_INGREDIENT_FONT_PX * 100)))
    RV_INSTRUCTION_WRAP=$(((RV_SCREEN_W - RV_INSTRUCTION_X - 26) * 35 * RV_FONT_WIDTH_PERCENT / (RV_INSTRUCTION_FONT_PX * 100)))
    rv_build_layout "$RV_ACTIVE_RECIPE" INGREDIENT "$RV_INGREDIENT_WRAP" "$RV_TMP/ingredients.layout"
    rv_build_layout "$RV_ACTIVE_RECIPE" INSTRUCTION "$RV_INSTRUCTION_WRAP" "$RV_TMP/instructions.layout"
    RV_INGREDIENT_ROWS=$(wc -l < "$RV_TMP/ingredients.layout" | tr -d ' ')
    RV_INSTRUCTION_ROWS=$(wc -l < "$RV_TMP/instructions.layout" | tr -d ' ')
    RV_INGREDIENT_ITEMS=$(awk -F '\t' '$1 == "INGREDIENT" && $2 == "item" { count++ } END { print count + 0 }' "$RV_ACTIVE_RECIPE")
    RV_INSTRUCTION_ITEMS=$(awk -F '\t' '$1 == "INSTRUCTION" && $2 == "item" { count++ } END { print count + 0 }' "$RV_ACTIVE_RECIPE")
    RV_INGREDIENT_LINE_H=$(rv_pxh "$RV_INGREDIENT_PT" "$RV_INGREDIENT_LEADING")
    RV_INSTRUCTION_LINE_H=$(rv_pxh "$RV_INSTRUCTION_PT" "$RV_INSTRUCTION_LEADING")
    RV_INGREDIENT_VISIBLE=$(((RV_CONTENT_BOTTOM - RV_CONTENT_TOP) / RV_INGREDIENT_LINE_H))
    RV_INSTRUCTION_VISIBLE=$(((RV_CONTENT_BOTTOM - RV_CONTENT_TOP) / RV_INSTRUCTION_LINE_H))
    RV_INGREDIENT_GAP_ROWS=$(((RV_INGREDIENT_ITEMS * RV_INGREDIENT_ITEM_GAP + RV_INGREDIENT_LINE_H - 1) / RV_INGREDIENT_LINE_H))
    RV_INGREDIENT_MAX_SCROLL=$((RV_INGREDIENT_ROWS + RV_INGREDIENT_GAP_ROWS - RV_INGREDIENT_VISIBLE)); [ "$RV_INGREDIENT_MAX_SCROLL" -lt 0 ] && RV_INGREDIENT_MAX_SCROLL=0
    RV_INSTRUCTION_GAP_ROWS=$(((RV_INSTRUCTION_ITEMS * RV_INSTRUCTION_STEP_GAP + RV_INSTRUCTION_LINE_H - 1) / RV_INSTRUCTION_LINE_H))
    RV_INSTRUCTION_MAX_SCROLL=$((RV_INSTRUCTION_ROWS + RV_INSTRUCTION_GAP_ROWS - RV_INSTRUCTION_VISIBLE)); [ "$RV_INSTRUCTION_MAX_SCROLL" -lt 0 ] && RV_INSTRUCTION_MAX_SCROLL=0
    RV_INGREDIENT_CHECKS=,
    RV_INGREDIENT_CURSOR=-1
    RV_INSTRUCTION_CURSOR=-1
    RV_INGREDIENT_SCROLL=0
    RV_INSTRUCTION_SCROLL=0
    RV_PARTIAL_COUNT=0
    RV_SCREEN=cook
    rv_log "selected ordinal=$RV_SELECTED_ORDINAL uid=$RV_RECIPE_UID title=$RV_RECIPE_TITLE ingredient_rows=$RV_INGREDIENT_ROWS instruction_rows=$RV_INSTRUCTION_ROWS wrap_units=$RV_INGREDIENT_WRAP,$RV_INSTRUCTION_WRAP width_percent=$RV_FONT_WIDTH_PERCENT"
}

rv_filter_recipes()
{
    RV_FILTERED_LIST="$RV_TMP/recipes.filtered.tsv"
    awk -F '\t' -v query="$RV_SEARCH_QUERY" '
        BEGIN { query = tolower(query) }
        query == "" || index(tolower($3), query) { print NR "\t" $0 }
    ' "$RV_RECIPE_LIST" > "$RV_FILTERED_LIST"
    RV_FILTERED_COUNT=$(wc -l < "$RV_FILTERED_LIST" | tr -d ' ')
    RV_LIST_MAX=$((RV_FILTERED_COUNT - RV_LIST_VISIBLE))
    [ "$RV_LIST_MAX" -lt 0 ] && RV_LIST_MAX=0
    rv_clamp "${RV_LIST_SCROLL:-0}" 0 "$RV_LIST_MAX"
    RV_LIST_SCROLL=$RV_CLAMPED
    rv_log "filter query=$RV_SEARCH_QUERY matches=$RV_FILTERED_COUNT"
}

rv_draw_search_bar()
{
    rv_draw_outline 10 72 728 50 2
    if [ -n "$RV_SEARCH_QUERY" ]; then
        rv_truncate "$RV_SEARCH_QUERY" 31
        rv_text 25 78 15 regular "$RV_TRUNCATED"
    else
        rv_text 25 78 15 regular "Search recipes..."
    fi
}

rv_render_list_body()
{
    RV_ROW=0
    RV_START=$((RV_LIST_SCROLL + 1))
    RV_END=$((RV_LIST_SCROLL + RV_LIST_VISIBLE))
    while IFS="$RV_TAB" read -r RV_ORDINAL RV_FILE RV_UID RV_TITLE; do
        RV_ROW=$((RV_ROW + 1))
        [ "$RV_ROW" -ge "$RV_START" ] || continue
        [ "$RV_ROW" -le "$RV_END" ] || break
        RV_Y=$((RV_LIST_TOP + (RV_ROW - RV_START) * RV_LIST_ROW_H + 6))
        rv_truncate "$RV_TITLE" 34
        rv_text 15 "$RV_Y" "$RV_LIST_PT" regular "$RV_TRUNCATED"
    done < "$RV_FILTERED_LIST"
    [ "$RV_FILTERED_COUNT" -gt 0 ] || rv_text 25 "$((RV_LIST_TOP + 24))" 15 regular "No matching recipes"
    RV_TRACK_H=$((RV_SCREEN_H - RV_LIST_TOP))
    if [ "$RV_FILTERED_COUNT" -le "$RV_LIST_VISIBLE" ]; then
        RV_THUMB_Y=$RV_LIST_TOP; RV_THUMB_H=$RV_TRACK_H
    else
        RV_THUMB_H=$((RV_TRACK_H * RV_LIST_VISIBLE / RV_FILTERED_COUNT))
        [ "$RV_THUMB_H" -lt 60 ] && RV_THUMB_H=60
        RV_SCROLL_RANGE=$((RV_FILTERED_COUNT - RV_LIST_VISIBLE))
        RV_THUMB_Y=$((RV_LIST_TOP + (RV_TRACK_H - RV_THUMB_H) * RV_LIST_SCROLL / RV_SCROLL_RANGE))
    fi
    rv_rect "$((RV_SCREEN_W - 8))" "$RV_LIST_TOP" 2 "$RV_TRACK_H"
    rv_rect "$((RV_SCREEN_W - 10))" "$RV_THUMB_Y" 6 "$RV_THUMB_H"
}

rv_draw_list()
{
    rv_clear
    # The same top-left back button as the cook screen, but here it exits the
    # app back to the Kindle Home screen since there is no recipe to unwind.
    RV_BACK_X=6; RV_BACK_Y=4; RV_BACK_W=56; RV_BACK_H=58
    rv_draw_outline "$RV_BACK_X" "$RV_BACK_Y" "$RV_BACK_W" "$RV_BACK_H" 2
    RV_BACK_CELL_H=$(rv_pxh "$RV_TITLE_PT" 0)
    RV_BACK_TEXT_Y=$((RV_BACK_Y + (RV_BACK_H - RV_BACK_CELL_H) / 2))
    rv_text "$((RV_BACK_X + 18))" "$RV_BACK_TEXT_Y" "$RV_TITLE_PT" bold "<"
    RV_TITLE_X=$((RV_BACK_X + RV_BACK_W + 8))
    rv_text "$RV_TITLE_X" 6 "$RV_TITLE_PT" bold "Recipes"
    rv_draw_search_bar
    rv_render_list_body
    rv_log "render screen=list query=$RV_SEARCH_QUERY scroll=$RV_LIST_SCROLL matches=$RV_FILTERED_COUNT rail_y=$RV_THUMB_Y rail_h=$RV_THUMB_H"
    rv_refresh
    RV_PARTIAL_COUNT=0
}

rv_draw_pane()
{
    # $1 layout $2 x $3 text-x $4 scroll $5 visible $6 line-height $7 cursor $8 pane
    RV_LAYOUT=$1; RV_PANE_X=$2; RV_TEXT_X=$3; RV_SCROLL=$4; RV_VISIBLE=$5
    RV_LINE_H=$6; RV_CURSOR=$7; RV_PANE=$8
    RV_VISUAL=0
    RV_Y=$RV_CONTENT_TOP
    RV_RENDERED=0
    RV_PREVIOUS_KIND=
    while IFS="$RV_TAB" read -r RV_RECORD_INDEX RV_KIND RV_LINE_TEXT RV_FIRST RV_LINE_UNITS RV_LINK_UID RV_LINK_PREFIX_UNITS RV_LINK_PHRASE_UNITS; do
        RV_VISUAL=$((RV_VISUAL + 1))
        [ "$RV_VISUAL" -gt "$RV_SCROLL" ] || continue
        if [ "$RV_FIRST" = 1 ] && [ "$RV_KIND" = item ] && \
            [ "$RV_PREVIOUS_KIND" = item ] && [ "$RV_RENDERED" -gt 0 ]; then
            RV_ITEM_GAP=$RV_INSTRUCTION_STEP_GAP
            [ "$RV_PANE" = ingredients ] && RV_ITEM_GAP=$RV_INGREDIENT_ITEM_GAP
            RV_Y=$((RV_Y + RV_ITEM_GAP))
        fi
        [ "$((RV_Y + RV_LINE_H))" -le "$RV_CONTENT_BOTTOM" ] || break
        RV_STYLE=regular
        [ "$RV_KIND" = section-header ] && RV_STYLE=bold
        if [ "$RV_PANE" = instructions ] && [ "$RV_KIND" = item ] && [ "$RV_RECORD_INDEX" -eq "$RV_CURSOR" ]; then
            rv_rect "$((RV_PANE_X + 3))" "$RV_Y" 3 "$((RV_LINE_H - 2))"
        fi
        RV_PT=$RV_INSTRUCTION_PT
        [ "$RV_PANE" = ingredients ] && RV_PT=$RV_INGREDIENT_PT
        rv_text "$RV_TEXT_X" "$RV_Y" "$RV_PT" "$RV_STYLE" "$RV_LINE_TEXT"
        if [ "$RV_PANE" = ingredients ] && [ "$RV_KIND" = item ] && rv_checked_has "$RV_RECORD_INDEX"; then
            # Draw after the glyphs so the line remains crisp. RV_LINE_UNITS is
            # measured in the same 35px Atkinson units used by the wrapper;
            # compensate for FBInk's calibrated horizontal rasterization.
            RV_STRIKE_W=$(((RV_LINE_UNITS * RV_INGREDIENT_FONT_PX * 100 + (35 * RV_FONT_WIDTH_PERCENT) - 1) / (35 * RV_FONT_WIDTH_PERCENT)))
            RV_STRIKE_MAX=$((RV_INGREDIENT_W - RV_TEXT_X - 8))
            [ "$RV_STRIKE_W" -gt "$RV_STRIKE_MAX" ] && RV_STRIKE_W=$RV_STRIKE_MAX
            [ "$RV_STRIKE_W" -lt 4 ] && RV_STRIKE_W=4
            RV_STRIKE_Y=$((RV_Y + RV_INGREDIENT_FONT_PX * 11 / 20))
            rv_rect "$RV_TEXT_X" "$RV_STRIKE_Y" "$RV_STRIKE_W" 2
        fi
        if [ "$RV_KIND" = item ] && [ -n "$RV_LINK_UID" ]; then
            # In instructions, only the resolved recipe-link phrase is
            # tappable (see rv_layout_hit), so only that exact span is
            # underlined and the rest of the step still reads as plain text.
            # In ingredients, there's no competing tap action, so the whole
            # row is the target and the whole row gets underlined.
            RV_LINK_FONT_PX=$RV_INSTRUCTION_FONT_PX
            RV_LINK_PANE_W=$RV_INSTRUCTION_W
            if [ "$RV_PANE" = ingredients ]; then
                RV_LINK_FONT_PX=$RV_INGREDIENT_FONT_PX
                RV_LINK_PANE_W=$RV_INGREDIENT_W
            fi
            RV_LINK_PREFIX_PX=$(((RV_LINK_PREFIX_UNITS * RV_LINK_FONT_PX * 100 + (35 * RV_FONT_WIDTH_PERCENT) - 1) / (35 * RV_FONT_WIDTH_PERCENT)))
            RV_LINK_W=$(((RV_LINK_PHRASE_UNITS * RV_LINK_FONT_PX * 100 + (35 * RV_FONT_WIDTH_PERCENT) - 1) / (35 * RV_FONT_WIDTH_PERCENT)))
            RV_LINK_X=$((RV_TEXT_X + RV_LINK_PREFIX_PX))
            RV_LINK_MAX=$((RV_PANE_X + RV_LINK_PANE_W - RV_LINK_X - 8))
            [ "$RV_LINK_W" -gt "$RV_LINK_MAX" ] && RV_LINK_W=$RV_LINK_MAX
            [ "$RV_LINK_W" -lt 4 ] && RV_LINK_W=4
            RV_LINK_Y=$((RV_Y + RV_LINK_FONT_PX - 2))
            rv_rect "$RV_LINK_X" "$RV_LINK_Y" "$RV_LINK_W" 2
        fi
        RV_Y=$((RV_Y + RV_LINE_H))
        RV_PREVIOUS_KIND=$RV_KIND
        RV_RENDERED=$((RV_RENDERED + 1))
    done < "$RV_LAYOUT"
}

rv_draw_cook()
{
    rv_clear
    # The back button always occupies the top-left corner: with link history
    # it steps back one recipe, and at the root it takes over END RECIPE's
    # old job. The box must be at least as tall as a title-weight glyph cell
    # (19pt is ~55px here) or the "<" has nowhere to sit but the bottom edge.
    RV_BACK_X=6; RV_BACK_Y=4; RV_BACK_W=56; RV_BACK_H=58
    rv_draw_outline "$RV_BACK_X" "$RV_BACK_Y" "$RV_BACK_W" "$RV_BACK_H" 2
    RV_BACK_CELL_H=$(rv_pxh "$RV_TITLE_PT" 0)
    RV_BACK_TEXT_Y=$((RV_BACK_Y + (RV_BACK_H - RV_BACK_CELL_H) / 2))
    rv_text "$((RV_BACK_X + 18))" "$RV_BACK_TEXT_Y" "$RV_TITLE_PT" bold "<"
    RV_TITLE_X=$((RV_BACK_X + RV_BACK_W + 8))
    rv_truncate "$RV_RECORD_TITLE" 28
    rv_text "$RV_TITLE_X" 4 "$RV_TITLE_PT" bold "$RV_TRUNCATED"
    rv_rect "$RV_INGREDIENT_W" "$RV_TITLE_H" "$RV_DIVIDER_W" "$((RV_CONTENT_BOTTOM - RV_TITLE_H))"
    rv_text 10 69 "$RV_PANE_HEADER_PT" bold Ingredients
    rv_text "$((RV_INSTRUCTION_X + 10))" 69 "$RV_PANE_HEADER_PT" bold Instructions
    rv_draw_pane "$RV_TMP/ingredients.layout" 0 10 "$RV_INGREDIENT_SCROLL" "$RV_INGREDIENT_VISIBLE" "$RV_INGREDIENT_LINE_H" "$RV_INGREDIENT_CURSOR" ingredients
    rv_draw_pane "$RV_TMP/instructions.layout" "$RV_INSTRUCTION_X" "$((RV_INSTRUCTION_X + 16))" "$RV_INSTRUCTION_SCROLL" "$RV_INSTRUCTION_VISIBLE" "$RV_INSTRUCTION_LINE_H" "$RV_INSTRUCTION_CURSOR" instructions
    rv_rect 0 "$RV_CONTENT_BOTTOM" "$RV_SCREEN_W" 2
    rv_log "render screen=cook title=$RV_RECORD_TITLE geometry=${RV_INGREDIENT_W}+${RV_DIVIDER_W}+${RV_INSTRUCTION_W} ingredient_scroll=$RV_INGREDIENT_SCROLL instruction_scroll=$RV_INSTRUCTION_SCROLL line_heights=$RV_INGREDIENT_LINE_H,$RV_INSTRUCTION_LINE_H"
    rv_refresh
    RV_PARTIAL_COUNT=0
}

rv_draw_outline()
{
    # $1=x $2=y $3=width $4=height $5=stroke
    rv_rect "$1" "$2" "$3" "$5"
    rv_rect "$1" "$(( $2 + $4 - $5 ))" "$3" "$5"
    rv_rect "$1" "$2" "$5" "$4"
    rv_rect "$(( $1 + $3 - $5 ))" "$2" "$5" "$4"
}

rv_draw_confirm()
{
    rv_clear
    rv_draw_outline 35 180 688 680 3
    rv_text 70 225 21 bold "End this recipe?"
    rv_truncate "$RV_RECORD_TITLE" 36
    rv_text 70 310 16 bold "$RV_TRUNCATED"
    rv_text 70 390 14 regular "This clears all checked ingredients"
    rv_text 70 435 14 regular "and returns to the recipe list."
    rv_draw_outline "$RV_CONFIRM_CANCEL_X" "$RV_CONFIRM_BUTTON_Y" "$RV_CONFIRM_BUTTON_W" "$RV_CONFIRM_BUTTON_H" 3
    rv_draw_outline "$RV_CONFIRM_END_X" "$RV_CONFIRM_BUTTON_Y" "$RV_CONFIRM_BUTTON_W" "$RV_CONFIRM_BUTTON_H" 3
    rv_text 155 692 18 bold "CANCEL"
    rv_text 447 692 18 bold "END RECIPE"
    rv_log "render screen=confirm uid=$RV_RECIPE_UID"
    rv_refresh
    RV_PARTIAL_COUNT=0
}

rv_draw_key_row()
{
    RV_KEY_X=$1
    RV_KEY_Y=$2
    shift 2
    for RV_KEY_LABEL do
        rv_draw_outline "$RV_KEY_X" "$RV_KEY_Y" "$RV_KEY_W" "$RV_KEY_H" 2
        rv_text "$((RV_KEY_X + 22))" "$((RV_KEY_Y + 18))" 16 bold "$RV_KEY_LABEL"
        RV_KEY_X=$((RV_KEY_X + RV_KEY_W + RV_KEY_GAP))
    done
}

rv_render_search_results()
{
    rv_draw_outline "$RV_SEARCH_FIELD_X" "$RV_SEARCH_FIELD_Y" "$RV_SEARCH_FIELD_W" "$RV_SEARCH_FIELD_H" 2
    if [ -n "$RV_SEARCH_QUERY" ]; then
        rv_truncate "$RV_SEARCH_QUERY" 31
        rv_text 25 16 15 regular "$RV_TRUNCATED"
    else
        rv_text 25 16 15 regular "Type to filter recipes"
    fi

    RV_ROW=0
    RV_START=$((RV_LIST_SCROLL + 1))
    RV_END=$((RV_LIST_SCROLL + RV_SEARCH_RESULTS_VISIBLE))
    while IFS="$RV_TAB" read -r RV_ORDINAL RV_FILE RV_UID RV_TITLE; do
        RV_ROW=$((RV_ROW + 1))
        [ "$RV_ROW" -ge "$RV_START" ] || continue
        [ "$RV_ROW" -le "$RV_END" ] || break
        RV_Y=$((RV_SEARCH_RESULTS_TOP + (RV_ROW - RV_START) * RV_LIST_ROW_H + 6))
        rv_truncate "$RV_TITLE" 34
        rv_text 15 "$RV_Y" "$RV_LIST_PT" regular "$RV_TRUNCATED"
    done < "$RV_FILTERED_LIST"
    [ "$RV_FILTERED_COUNT" -gt 0 ] || rv_text 25 "$((RV_SEARCH_RESULTS_TOP + 24))" 15 regular "No matching recipes"
}

rv_render_search_screen()
{
    rv_render_search_results
    rv_draw_key_row 9 "$RV_KEYBOARD_TOP" Q W E R T Y U I O P
    rv_draw_key_row 44 "$((RV_KEYBOARD_TOP + 90))" A S D F G H J K L
    rv_draw_key_row 119 "$((RV_KEYBOARD_TOP + 180))" Z X C V B N M
    rv_draw_outline 10 "$RV_SEARCH_CONTROL_Y" 130 "$RV_SEARCH_CONTROL_H" 2
    rv_draw_outline 150 "$RV_SEARCH_CONTROL_Y" 280 "$RV_SEARCH_CONTROL_H" 2
    rv_draw_outline 440 "$RV_SEARCH_CONTROL_Y" 140 "$RV_SEARCH_CONTROL_H" 2
    rv_draw_outline 590 "$RV_SEARCH_CONTROL_Y" 158 "$RV_SEARCH_CONTROL_H" 2
    rv_text 28 837 14 bold "CLEAR"
    rv_text 230 837 14 bold "SPACE"
    rv_text 466 837 14 bold "BACK"
    rv_text 620 837 14 bold "DONE"
}

rv_draw_search()
{
    rv_clear
    rv_render_search_screen
    rv_log "render screen=search query=$RV_SEARCH_QUERY scroll=$RV_LIST_SCROLL matches=$RV_FILTERED_COUNT"
    rv_refresh
    RV_PARTIAL_COUNT=0
}

rv_draw_search_partial()
{
    if ! rv_partial_allowed; then
        rv_draw_search
        return
    fi
    if ! rv_clear_region 0 0 "$RV_SCREEN_W" "$RV_KEYBOARD_TOP"; then
        rv_log "partial clear failed screen=search; falling back to full"
        rv_draw_search
        return
    fi
    rv_render_search_results
    if ! rv_refresh_region 0 0 "$RV_SCREEN_W" "$RV_KEYBOARD_TOP" GC16; then
        rv_log "partial refresh failed screen=search; falling back to full"
        rv_draw_search
        return
    fi
    RV_PARTIAL_COUNT=$((RV_PARTIAL_COUNT + 1))
    rv_log "partial screen=search query=$RV_SEARCH_QUERY matches=$RV_FILTERED_COUNT waveform=GC16 count=$RV_PARTIAL_COUNT"
}

rv_layout_hit()
{
    # $1 layout $2 x $3 y $4 scroll $5 line-height $6 pane $7 text-x $8 gap;
    # sets record, kind, and link (link only when x lands on the resolved
    # phrase, for instructions; whole-row for ingredients).
    RV_HIT_LINE=$(awk -F '\t' -v target_x="$2" -v target_y="$3" -v scroll="$4" \
        -v line_h="$5" -v pane="$6" -v text_x="$7" -v top="$RV_CONTENT_TOP" \
        -v bottom="$RV_CONTENT_BOTTOM" -v gap="$8" \
        -v font_px="$RV_INSTRUCTION_FONT_PX" -v percent="$RV_FONT_WIDTH_PERCENT" '
        function to_px(units) {
            return int((units * font_px * 100 + (35 * percent - 1)) / (35 * percent))
        }
        {
            visual++
            if (visual <= scroll) next
            if (!started) { y = top; started = 1 }
            if ($4 == 1 && $2 == "item" &&
                previous_kind == "item" && rendered > 0) y += gap
            if (y + line_h > bottom) exit
            if (target_y >= y && target_y < y + line_h) {
                link = ""
                if (pane == "instructions") {
                    # Only the located phrase is the tap target, so a tap has
                    # to land within its pixel span.
                    if ($6 != "") {
                        link_x0 = text_x + to_px($7)
                        link_x1 = link_x0 + to_px($8)
                        if (target_x >= link_x0 && target_x < link_x1) link = $6
                    }
                } else {
                    # Ingredient links have no competing tap action, so the
                    # whole row (matched by y alone, same as a check toggle)
                    # is the target.
                    link = $6
                }
                print $1 "\t" $2 "\t" link
                exit
            }
            y += line_h
            previous_kind = $2
            rendered++
        }
    ' "$1")
    RV_HIT_RECORD=$(printf '%s\n' "$RV_HIT_LINE" | cut -f1)
    RV_HIT_KIND=$(printf '%s\n' "$RV_HIT_LINE" | cut -f2)
    RV_HIT_LINK=$(printf '%s\n' "$RV_HIT_LINE" | cut -f3)
}

rv_partial_allowed()
{
    [ "${RV_PARTIAL_REFRESH:-1}" = 1 ] || return 1
    [ "${RV_PARTIAL_COUNT:-0}" -lt "${RV_PARTIAL_FULL_EVERY:-12}" ] || return 1
}

rv_draw_list_partial()
{
    if ! rv_partial_allowed; then
        rv_draw_list
        return
    fi
    RV_REGION_H=$((RV_SCREEN_H - RV_TITLE_H))
    if ! rv_clear_region 0 "$RV_TITLE_H" "$RV_SCREEN_W" "$RV_REGION_H"; then
        rv_log "partial clear failed screen=list; falling back to full"
        rv_draw_list
        return
    fi
    rv_draw_search_bar
    rv_render_list_body
    if ! rv_refresh_region 0 "$RV_TITLE_H" "$RV_SCREEN_W" "$RV_REGION_H" GC16; then
        rv_log "partial refresh failed screen=list; falling back to full"
        rv_draw_list
        return
    fi
    RV_PARTIAL_COUNT=$((RV_PARTIAL_COUNT + 1))
    rv_log "partial screen=list region=0,$RV_TITLE_H,${RV_SCREEN_W}x$RV_REGION_H waveform=GC16 count=$RV_PARTIAL_COUNT"
}

rv_draw_cook_pane_partial()
{
    # $1=ingredients|instructions $2=DU|GC16
    RV_PARTIAL_PANE=$1
    RV_PARTIAL_WAVEFORM=$2
    if ! rv_partial_allowed; then
        rv_draw_cook
        return
    fi
    if [ "$RV_PARTIAL_PANE" = ingredients ]; then
        RV_PARTIAL_X=0
        RV_PARTIAL_W=$RV_INGREDIENT_W
    else
        RV_PARTIAL_X=$RV_INSTRUCTION_X
        RV_PARTIAL_W=$RV_INSTRUCTION_W
    fi
    RV_PARTIAL_H=$((RV_CONTENT_BOTTOM - RV_CONTENT_TOP))
    if ! rv_clear_region "$RV_PARTIAL_X" "$RV_CONTENT_TOP" "$RV_PARTIAL_W" "$RV_PARTIAL_H"; then
        rv_log "partial clear failed pane=$RV_PARTIAL_PANE; falling back to full"
        rv_draw_cook
        return
    fi
    if [ "$RV_PARTIAL_PANE" = ingredients ]; then
        rv_draw_pane "$RV_TMP/ingredients.layout" 0 10 "$RV_INGREDIENT_SCROLL" "$RV_INGREDIENT_VISIBLE" "$RV_INGREDIENT_LINE_H" "$RV_INGREDIENT_CURSOR" ingredients
    else
        rv_draw_pane "$RV_TMP/instructions.layout" "$RV_INSTRUCTION_X" "$((RV_INSTRUCTION_X + 16))" "$RV_INSTRUCTION_SCROLL" "$RV_INSTRUCTION_VISIBLE" "$RV_INSTRUCTION_LINE_H" "$RV_INSTRUCTION_CURSOR" instructions
    fi
    if ! rv_refresh_region "$RV_PARTIAL_X" "$RV_CONTENT_TOP" "$RV_PARTIAL_W" "$RV_PARTIAL_H" "$RV_PARTIAL_WAVEFORM"; then
        rv_log "partial refresh failed pane=$RV_PARTIAL_PANE; falling back to full"
        rv_draw_cook
        return
    fi
    RV_PARTIAL_COUNT=$((RV_PARTIAL_COUNT + 1))
    rv_log "partial screen=cook pane=$RV_PARTIAL_PANE region=$RV_PARTIAL_X,$RV_CONTENT_TOP,${RV_PARTIAL_W}x$RV_PARTIAL_H waveform=$RV_PARTIAL_WAVEFORM count=$RV_PARTIAL_COUNT"
}

rv_handle_list_gesture()
{
    RV_LIST_MAX=$((RV_FILTERED_COUNT - RV_LIST_VISIBLE)); [ "$RV_LIST_MAX" -lt 0 ] && RV_LIST_MAX=0
    # The back button at the recipe list is the top of the navigation stack,
    # so instead of unwinding to a previous recipe it exits the app.
    if [ "$RV_GESTURE" = tap ] && [ "$RV_Y2" -lt "$RV_TITLE_H" ] && [ "$RV_X1" -lt 64 ]; then
        RV_SCREEN=exit
        rv_log "exit requested from recipe list"
        return
    fi
    case "$RV_GESTURE" in
        swipe-up)
            RV_SCROLL_BEFORE=$RV_LIST_SCROLL
            RV_LIST_SCROLL=$((RV_LIST_SCROLL + 5)); rv_clamp "$RV_LIST_SCROLL" 0 "$RV_LIST_MAX"; RV_LIST_SCROLL=$RV_CLAMPED
            [ "$RV_LIST_SCROLL" -eq "$RV_SCROLL_BEFORE" ] || RV_REDRAW=list
            ;;
        swipe-down)
            RV_SCROLL_BEFORE=$RV_LIST_SCROLL
            RV_LIST_SCROLL=$((RV_LIST_SCROLL - 5)); rv_clamp "$RV_LIST_SCROLL" 0 "$RV_LIST_MAX"; RV_LIST_SCROLL=$RV_CLAMPED
            [ "$RV_LIST_SCROLL" -eq "$RV_SCROLL_BEFORE" ] || RV_REDRAW=list
            ;;
        tap)
            if [ "$RV_Y2" -ge "$RV_SEARCH_BAR_Y" ] && [ "$RV_Y2" -lt "$RV_LIST_TOP" ]; then
                RV_SCREEN=search
                RV_REDRAW=full
                rv_log "search opened query=$RV_SEARCH_QUERY"
                return
            fi
            [ "$RV_Y2" -ge "$RV_LIST_TOP" ] || return
            RV_PICK=$((RV_LIST_SCROLL + (RV_Y2 - RV_LIST_TOP) / RV_LIST_ROW_H + 1))
            [ "$RV_PICK" -le "$RV_FILTERED_COUNT" ] || return
            RV_PICK_ENTRY=$(sed -n "${RV_PICK}p" "$RV_FILTERED_LIST")
            RV_PICK_ORDINAL=$(printf '%s\n' "$RV_PICK_ENTRY" | cut -f1)
            RV_NAV_STACK=
            rv_load_recipe "$RV_PICK_ORDINAL" || return 1
            RV_REDRAW=full
            ;;
    esac
}

rv_search_letter_at()
{
    # $1=x $2=y; returns a lowercase letter in RV_SEARCH_KEY.
    RV_SEARCH_KEY=
    RV_KEY_CHARS=
    RV_KEY_START=0
    if [ "$2" -ge "$RV_KEYBOARD_TOP" ] && [ "$2" -lt "$((RV_KEYBOARD_TOP + RV_KEY_H))" ]; then
        RV_KEY_CHARS=qwertyuiop; RV_KEY_START=9
    elif [ "$2" -ge "$((RV_KEYBOARD_TOP + 90))" ] && [ "$2" -lt "$((RV_KEYBOARD_TOP + 90 + RV_KEY_H))" ]; then
        RV_KEY_CHARS=asdfghjkl; RV_KEY_START=44
    elif [ "$2" -ge "$((RV_KEYBOARD_TOP + 180))" ] && [ "$2" -lt "$((RV_KEYBOARD_TOP + 180 + RV_KEY_H))" ]; then
        RV_KEY_CHARS=zxcvbnm; RV_KEY_START=119
    else
        return
    fi
    [ "$1" -ge "$RV_KEY_START" ] || return
    RV_KEY_REL=$(($1 - RV_KEY_START))
    RV_KEY_INDEX=$((RV_KEY_REL / (RV_KEY_W + RV_KEY_GAP)))
    RV_KEY_OFFSET=$((RV_KEY_REL % (RV_KEY_W + RV_KEY_GAP)))
    [ "$RV_KEY_OFFSET" -lt "$RV_KEY_W" ] || return
    [ "$RV_KEY_INDEX" -lt "${#RV_KEY_CHARS}" ] || return
    RV_SEARCH_KEY=$(printf '%s' "$RV_KEY_CHARS" | cut -c "$((RV_KEY_INDEX + 1))")
}

rv_handle_search_gesture()
{
    RV_SEARCH_MAX=$((RV_FILTERED_COUNT - RV_SEARCH_RESULTS_VISIBLE))
    [ "$RV_SEARCH_MAX" -lt 0 ] && RV_SEARCH_MAX=0
    case "$RV_GESTURE" in
        swipe-up|swipe-down)
            [ "$RV_Y2" -lt "$RV_KEYBOARD_TOP" ] || return
            RV_SCROLL_BEFORE=$RV_LIST_SCROLL
            if [ "$RV_GESTURE" = swipe-up ]; then
                RV_LIST_SCROLL=$((RV_LIST_SCROLL + 5))
            else
                RV_LIST_SCROLL=$((RV_LIST_SCROLL - 5))
            fi
            rv_clamp "$RV_LIST_SCROLL" 0 "$RV_SEARCH_MAX"; RV_LIST_SCROLL=$RV_CLAMPED
            [ "$RV_LIST_SCROLL" -eq "$RV_SCROLL_BEFORE" ] || RV_REDRAW=search
            ;;
        tap)
            if [ "$RV_Y2" -ge "$RV_SEARCH_RESULTS_TOP" ] && \
                [ "$RV_Y2" -lt "$((RV_SEARCH_RESULTS_TOP + RV_SEARCH_RESULTS_VISIBLE * RV_LIST_ROW_H))" ]; then
                RV_PICK=$((RV_LIST_SCROLL + (RV_Y2 - RV_SEARCH_RESULTS_TOP) / RV_LIST_ROW_H + 1))
                [ "$RV_PICK" -le "$RV_FILTERED_COUNT" ] || return
                RV_PICK_ENTRY=$(sed -n "${RV_PICK}p" "$RV_FILTERED_LIST")
                RV_PICK_ORDINAL=$(printf '%s\n' "$RV_PICK_ENTRY" | cut -f1)
                RV_NAV_STACK=
                rv_load_recipe "$RV_PICK_ORDINAL" || return 1
                RV_REDRAW=full
                return
            fi

            RV_SEARCH_CHANGED=0
            rv_search_letter_at "$RV_X2" "$RV_Y2"
            if [ -n "$RV_SEARCH_KEY" ]; then
                RV_SEARCH_LENGTH=$(printf '%s' "$RV_SEARCH_QUERY" | wc -c | tr -d ' ')
                if [ "$RV_SEARCH_LENGTH" -lt 31 ]; then
                    RV_SEARCH_QUERY="${RV_SEARCH_QUERY}${RV_SEARCH_KEY}"
                    RV_SEARCH_CHANGED=1
                fi
            elif [ "$RV_Y2" -ge "$RV_SEARCH_CONTROL_Y" ] && \
                [ "$RV_Y2" -lt "$((RV_SEARCH_CONTROL_Y + RV_SEARCH_CONTROL_H))" ]; then
                if [ "$RV_X2" -ge 10 ] && [ "$RV_X2" -lt 140 ]; then
                    RV_SEARCH_QUERY=
                    RV_SEARCH_CHANGED=1
                elif [ "$RV_X2" -ge 150 ] && [ "$RV_X2" -lt 430 ]; then
                    case "$RV_SEARCH_QUERY" in
                        ''|*' ') ;;
                        *) RV_SEARCH_QUERY="$RV_SEARCH_QUERY "; RV_SEARCH_CHANGED=1 ;;
                    esac
                elif [ "$RV_X2" -ge 440 ] && [ "$RV_X2" -lt 580 ]; then
                    [ -n "$RV_SEARCH_QUERY" ] || return
                    RV_SEARCH_QUERY=$(printf '%s' "$RV_SEARCH_QUERY" | sed 's/.$//')
                    RV_SEARCH_CHANGED=1
                elif [ "$RV_X2" -ge 590 ] && [ "$RV_X2" -lt 748 ]; then
                    rv_filter_recipes
                    RV_SCREEN=list
                    RV_REDRAW=full
                    rv_log "search closed query=$RV_SEARCH_QUERY matches=$RV_FILTERED_COUNT"
                    return
                fi
            fi
            if [ "$RV_SEARCH_CHANGED" -eq 1 ]; then
                RV_LIST_SCROLL=0
                rv_filter_recipes
                RV_REDRAW=search
                rv_log "search edited query=$RV_SEARCH_QUERY matches=$RV_FILTERED_COUNT"
            fi
            ;;
    esac
}

rv_handle_cook_gesture()
{
    # The top-left back button is always present: with link history to
    # unwind it steps back one recipe; at the root (nothing to go back to)
    # it takes over END RECIPE's job of asking to return to the list.
    if [ "$RV_GESTURE" = tap ] && [ "$RV_Y2" -lt "$RV_TITLE_H" ] && [ "$RV_X1" -lt 64 ]; then
        if [ -n "$RV_NAV_STACK" ]; then
            rv_nav_pop
            rv_log "back navigated to ordinal=$RV_NAV_POPPED"
            rv_load_recipe "$RV_NAV_POPPED" || return 1
            RV_REDRAW=full
        else
            RV_SCREEN=confirm
            RV_REDRAW=full
            rv_log "end requested uid=$RV_RECIPE_UID"
        fi
        return
    fi
    [ "$RV_Y2" -ge "$RV_CONTENT_TOP" ] && [ "$RV_Y2" -lt "$RV_CONTENT_BOTTOM" ] || return
    if [ "$RV_X1" -lt "$RV_INGREDIENT_W" ]; then
        case "$RV_GESTURE" in
            swipe-up)
                RV_SCROLL_BEFORE=$RV_INGREDIENT_SCROLL
                RV_INGREDIENT_SCROLL=$((RV_INGREDIENT_SCROLL + 5)); rv_clamp "$RV_INGREDIENT_SCROLL" 0 "$RV_INGREDIENT_MAX_SCROLL"; RV_INGREDIENT_SCROLL=$RV_CLAMPED
                if [ "$RV_INGREDIENT_SCROLL" -ne "$RV_SCROLL_BEFORE" ]; then RV_REDRAW=ingredients; RV_REDRAW_WAVEFORM=GC16; fi
                ;;
            swipe-down)
                RV_SCROLL_BEFORE=$RV_INGREDIENT_SCROLL
                RV_INGREDIENT_SCROLL=$((RV_INGREDIENT_SCROLL - 5)); rv_clamp "$RV_INGREDIENT_SCROLL" 0 "$RV_INGREDIENT_MAX_SCROLL"; RV_INGREDIENT_SCROLL=$RV_CLAMPED
                if [ "$RV_INGREDIENT_SCROLL" -ne "$RV_SCROLL_BEFORE" ]; then RV_REDRAW=ingredients; RV_REDRAW_WAVEFORM=GC16; fi
                ;;
            tap)
                rv_layout_hit "$RV_TMP/ingredients.layout" "$RV_X2" "$RV_Y2" "$RV_INGREDIENT_SCROLL" "$RV_INGREDIENT_LINE_H" ingredients 10 "$RV_INGREDIENT_ITEM_GAP"
                if [ "$RV_HIT_KIND" = item ] && [ -n "$RV_HIT_LINK" ]; then
                    rv_uid_ordinal "$RV_HIT_LINK"
                    if [ -n "$RV_UID_ORDINAL" ]; then
                        rv_log "ingredient link followed target_uid=$RV_HIT_LINK ordinal=$RV_UID_ORDINAL"
                        rv_nav_push "$RV_SELECTED_ORDINAL"
                        rv_load_recipe "$RV_UID_ORDINAL" || return 1
                        RV_REDRAW=full
                    else
                        rv_log "ingredient link target missing from library uid=$RV_HIT_LINK"
                        RV_INGREDIENT_CURSOR=$RV_HIT_RECORD; rv_toggle_check "$RV_HIT_RECORD"; RV_REDRAW=ingredients; RV_REDRAW_WAVEFORM=DU
                    fi
                elif [ "$RV_HIT_KIND" = item ]; then
                    RV_INGREDIENT_CURSOR=$RV_HIT_RECORD; rv_toggle_check "$RV_HIT_RECORD"; RV_REDRAW=ingredients; RV_REDRAW_WAVEFORM=DU; rv_log "ingredient tap index=$RV_HIT_RECORD checked=$RV_INGREDIENT_CHECKS"
                fi
                ;;
        esac
    elif [ "$RV_X1" -ge "$RV_INSTRUCTION_X" ]; then
        case "$RV_GESTURE" in
            swipe-up)
                RV_SCROLL_BEFORE=$RV_INSTRUCTION_SCROLL
                RV_INSTRUCTION_SCROLL=$((RV_INSTRUCTION_SCROLL + 5)); rv_clamp "$RV_INSTRUCTION_SCROLL" 0 "$RV_INSTRUCTION_MAX_SCROLL"; RV_INSTRUCTION_SCROLL=$RV_CLAMPED
                if [ "$RV_INSTRUCTION_SCROLL" -ne "$RV_SCROLL_BEFORE" ]; then RV_REDRAW=instructions; RV_REDRAW_WAVEFORM=GC16; fi
                ;;
            swipe-down)
                RV_SCROLL_BEFORE=$RV_INSTRUCTION_SCROLL
                RV_INSTRUCTION_SCROLL=$((RV_INSTRUCTION_SCROLL - 5)); rv_clamp "$RV_INSTRUCTION_SCROLL" 0 "$RV_INSTRUCTION_MAX_SCROLL"; RV_INSTRUCTION_SCROLL=$RV_CLAMPED
                if [ "$RV_INSTRUCTION_SCROLL" -ne "$RV_SCROLL_BEFORE" ]; then RV_REDRAW=instructions; RV_REDRAW_WAVEFORM=GC16; fi
                ;;
            tap)
                rv_layout_hit "$RV_TMP/instructions.layout" "$RV_X2" "$RV_Y2" "$RV_INSTRUCTION_SCROLL" "$RV_INSTRUCTION_LINE_H" instructions "$((RV_INSTRUCTION_X + 16))" "$RV_INSTRUCTION_STEP_GAP"
                if [ "$RV_HIT_KIND" = item ] && [ -n "$RV_HIT_LINK" ]; then
                    rv_uid_ordinal "$RV_HIT_LINK"
                    if [ -n "$RV_UID_ORDINAL" ]; then
                        rv_log "instruction link followed target_uid=$RV_HIT_LINK ordinal=$RV_UID_ORDINAL"
                        rv_nav_push "$RV_SELECTED_ORDINAL"
                        rv_load_recipe "$RV_UID_ORDINAL" || return 1
                        RV_REDRAW=full
                    else
                        rv_log "instruction link target missing from library uid=$RV_HIT_LINK"
                        RV_INSTRUCTION_CURSOR=$RV_HIT_RECORD; RV_REDRAW=instructions; RV_REDRAW_WAVEFORM=DU
                    fi
                elif [ "$RV_HIT_KIND" = item ]; then
                    RV_INSTRUCTION_CURSOR=$RV_HIT_RECORD; RV_REDRAW=instructions; RV_REDRAW_WAVEFORM=DU; rv_log "instruction tap index=$RV_HIT_RECORD"
                fi
                ;;
        esac
    fi
}

rv_handle_confirm_gesture()
{
    [ "$RV_GESTURE" = tap ] || return
    [ "$RV_Y2" -ge "$RV_CONFIRM_BUTTON_Y" ] && \
        [ "$RV_Y2" -lt "$((RV_CONFIRM_BUTTON_Y + RV_CONFIRM_BUTTON_H))" ] || return
    if [ "$RV_X2" -ge "$RV_CONFIRM_CANCEL_X" ] && \
        [ "$RV_X2" -lt "$((RV_CONFIRM_CANCEL_X + RV_CONFIRM_BUTTON_W))" ]; then
        RV_SCREEN=cook
        RV_REDRAW=full
        rv_log "end cancelled uid=$RV_RECIPE_UID"
    elif [ "$RV_X2" -ge "$RV_CONFIRM_END_X" ] && \
        [ "$RV_X2" -lt "$((RV_CONFIRM_END_X + RV_CONFIRM_BUTTON_W))" ]; then
        rv_log "end confirmed uid=$RV_RECIPE_UID"
        rv_abandon
        RV_REDRAW=full
    fi
}
