#!/bin/sh
# Shared state, data loading, logging, and navigation helpers.

RV_SCREEN_W=758
RV_SCREEN_H=1024
RV_DPI=212
RV_TITLE_H=66
RV_INGREDIENT_W=300
RV_DIVIDER_W=2
RV_INSTRUCTION_X=302
RV_INSTRUCTION_W=456
RV_END_Y=966
RV_END_H=58
RV_CONTENT_TOP=110
RV_CONTENT_BOTTOM=958
RV_TITLE_PT=19
RV_LIST_PT=17
RV_PANE_HEADER_PT=13
RV_END_PT=13
RV_INGREDIENT_PT=13
RV_INSTRUCTION_PT=13
RV_INGREDIENT_LEADING=1
RV_INSTRUCTION_LEADING=1
RV_FONT_WIDTH_PERCENT=${RV_FONT_WIDTH_PERCENT:-135}
RV_LIST_ROW_H=64
RV_SEARCH_BAR_Y=66
RV_SEARCH_BAR_H=64
RV_LIST_TOP=130
RV_LIST_VISIBLE=13
RV_SEARCH_FIELD_X=10
RV_SEARCH_FIELD_Y=10
RV_SEARCH_FIELD_W=738
RV_SEARCH_FIELD_H=56
RV_SEARCH_RESULTS_TOP=80
RV_SEARCH_RESULTS_VISIBLE=6
RV_KEYBOARD_TOP=500
RV_KEY_H=85
RV_KEY_W=70
RV_KEY_GAP=5
RV_SEARCH_CONTROL_Y=805
RV_SEARCH_CONTROL_H=110
RV_CONFIRM_BUTTON_Y=650
RV_CONFIRM_BUTTON_H=140
RV_CONFIRM_CANCEL_X=60
RV_CONFIRM_END_X=398
RV_CONFIRM_BUTTON_W=300
RV_TOUCH_NATIVE_W=758
RV_TOUCH_NATIVE_H=1024
RV_TOUCH_ROTATION=${RV_TOUCH_ROTATION:-U}
RV_LANDSCAPE_ORIENTATION=${RV_LANDSCAPE_ORIENTATION:-L}
RV_INSTRUCTION_STEP_GAP=${RV_INSTRUCTION_STEP_GAP:-10}
RV_PARTIAL_REFRESH=${RV_PARTIAL_REFRESH:-1}
RV_PARTIAL_FULL_EVERY=${RV_PARTIAL_FULL_EVERY:-12}

rv_log()
{
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$*" >> "$RV_LOG"
}

rv_pxh()
{
    # fbink's measured advance on this 212-DPI panel, plus explicit spacing.
    printf '%s\n' "$((($1 * RV_DPI) / 72 + $2))"
}

rv_clamp()
{
    RV_CLAMPED=$1
    [ "$RV_CLAMPED" -lt "$2" ] && RV_CLAMPED=$2
    [ "$RV_CLAMPED" -gt "$3" ] && RV_CLAMPED=$3
    return 0
}

rv_truncate()
{
    RV_TRUNCATED=$(printf '%s' "$1" | cut -c "1-$2")
    RV_ORIGINAL_LENGTH=$(printf '%s' "$1" | wc -c | tr -d ' ')
    if [ "$RV_ORIGINAL_LENGTH" -gt "$2" ]; then
        RV_KEEP=$(( $2 - 3 ))
        RV_TRUNCATED="$(printf '%s' "$1" | cut -c "1-$RV_KEEP")..."
    fi
}

rv_manifest_load()
{
    RV_MANIFEST="$RV_LIBRARY_ROOT/manifest.tsv"
    RV_RECIPE_LIST="$RV_TMP/recipes.tsv"
    : > "$RV_RECIPE_LIST"
    [ -r "$RV_MANIFEST" ] || { RV_ERROR="library manifest missing: $RV_MANIFEST"; return 1; }
    RV_SCHEMA=
    RV_DECLARED_COUNT=
    RV_ACTUAL_COUNT=0
    RV_TAB=$(printf '\t')
    while IFS="$RV_TAB" read -r RV_TYPE RV_A RV_B RV_C RV_EXTRA; do
        case "$RV_TYPE" in
            SCHEMA) RV_SCHEMA=$RV_A ;;
            COUNT) RV_DECLARED_COUNT=$RV_A ;;
            RECIPE)
                [ -n "$RV_A" ] && [ -n "$RV_B" ] && [ -n "$RV_C" ] || {
                    RV_ERROR="malformed RECIPE manifest record"; return 1;
                }
                case "$RV_A" in */*|*\\*|..*) RV_ERROR="unsafe recipe filename: $RV_A"; return 1 ;; esac
                [ -r "$RV_LIBRARY_ROOT/$RV_A" ] || {
                    RV_ERROR="recipe file missing: $RV_A"; return 1;
                }
                printf '%s\t%s\t%s\n' "$RV_A" "$RV_B" "$RV_C" >> "$RV_RECIPE_LIST"
                RV_ACTUAL_COUNT=$((RV_ACTUAL_COUNT + 1))
                ;;
            '') ;;
            *) RV_ERROR="unknown manifest record: $RV_TYPE"; return 1 ;;
        esac
    done < "$RV_MANIFEST"
    [ "$RV_SCHEMA" = "1" ] || { RV_ERROR="unsupported library schema: ${RV_SCHEMA:-missing}"; return 1; }
    case "$RV_DECLARED_COUNT" in ''|*[!0-9]*) RV_ERROR="invalid library recipe count"; return 1 ;; esac
    [ "$RV_DECLARED_COUNT" -gt 0 ] || { RV_ERROR="library is empty"; return 1; }
    [ "$RV_DECLARED_COUNT" -eq "$RV_ACTUAL_COUNT" ] || {
        RV_ERROR="manifest count mismatch: declared=$RV_DECLARED_COUNT actual=$RV_ACTUAL_COUNT"; return 1;
    }
    RV_RECIPE_COUNT=$RV_ACTUAL_COUNT
    rv_log "library schema=$RV_SCHEMA recipes=$RV_RECIPE_COUNT"
}

rv_recipe_field()
{
    # $1=ordinal, result fields are read from parsed records, never evaluated.
    RV_RECIPE_ENTRY=$(sed -n "${1}p" "$RV_RECIPE_LIST")
    RV_RECIPE_FILE=$(printf '%s\n' "$RV_RECIPE_ENTRY" | cut -f1)
    RV_RECIPE_UID=$(printf '%s\n' "$RV_RECIPE_ENTRY" | cut -f2)
    RV_RECIPE_TITLE=$(printf '%s\n' "$RV_RECIPE_ENTRY" | cut -f3-)
}

rv_checked_has()
{
    case "$RV_INGREDIENT_CHECKS" in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

rv_toggle_check()
{
    RV_INDEX=$1
    if rv_checked_has "$RV_INDEX"; then
        RV_INGREDIENT_CHECKS=$(printf '%s' "$RV_INGREDIENT_CHECKS" | sed "s/,$RV_INDEX,/,/")
    else
        RV_INGREDIENT_CHECKS="${RV_INGREDIENT_CHECKS}${RV_INDEX},"
    fi
}

rv_reset_session()
{
    RV_INGREDIENT_CHECKS=,
    RV_INGREDIENT_CURSOR=-1
    RV_INSTRUCTION_CURSOR=-1
    RV_INGREDIENT_SCROLL=0
    RV_INSTRUCTION_SCROLL=0
    RV_SELECTED_ORDINAL=0
}

rv_abandon()
{
    rv_log "abandon uid=${RV_RECIPE_UID:-none}"
    rv_reset_session
    RV_SCREEN=list
}

rv_enter_landscape()
{
    RV_ORIENTATION_CHANGED=0
    RV_ORIENTATION_PREVIOUS=U
    if [ -n "${RV_DISPLAY_COMMAND:-}" ] || [ "${RV_SKIP_ORIENTATION:-0}" = 1 ]; then
        rv_log "orientation simulated target=$RV_LANDSCAPE_ORIENTATION touch_rotation=$RV_TOUCH_ROTATION geometry=${RV_SCREEN_W}x${RV_SCREEN_H}"
        return 0
    fi

    RV_LIPC_SET=${RV_LIPC_SET_COMMAND:-$(command -v lipc-set-prop 2>/dev/null)}
    RV_LIPC_GET=${RV_LIPC_GET_COMMAND:-$(command -v lipc-get-prop 2>/dev/null)}
    [ -n "$RV_LIPC_SET" ] && [ -x "$RV_LIPC_SET" ] || {
        RV_ERROR="landscape unavailable: lipc-set-prop was not found"
        return 1
    }
    if [ -n "$RV_LIPC_GET" ] && [ -x "$RV_LIPC_GET" ]; then
        RV_ORIENTATION_READ=$($RV_LIPC_GET com.lab126.winmgr orientationLock 2>/dev/null | tr -d '\r\n')
        case "$RV_ORIENTATION_READ" in
            U|D|L|R) RV_ORIENTATION_PREVIOUS=$RV_ORIENTATION_READ ;;
            *)
                RV_ORIENTATION_READ=$($RV_LIPC_GET com.lab126.winmgr accelerometer 2>/dev/null | tr -d '\r\n')
                case "$RV_ORIENTATION_READ" in U|D|L|R) RV_ORIENTATION_PREVIOUS=$RV_ORIENTATION_READ ;; esac
                ;;
        esac
    fi
    if ! "$RV_LIPC_SET" com.lab126.winmgr orientationLock "$RV_LANDSCAPE_ORIENTATION"; then
        RV_ERROR="landscape unavailable: Kindle orientation lock failed"
        return 1
    fi
    RV_ORIENTATION_CHANGED=1
    sleep "${RV_ORIENTATION_SETTLE_SECONDS:-1}"
    rv_log "orientation previous=$RV_ORIENTATION_PREVIOUS target=$RV_LANDSCAPE_ORIENTATION touch_rotation=$RV_TOUCH_ROTATION geometry=${RV_SCREEN_W}x${RV_SCREEN_H}"
}

rv_restore_orientation()
{
    [ "${RV_ORIENTATION_CHANGED:-0}" = 1 ] || return 0
    if "$RV_LIPC_SET" com.lab126.winmgr orientationLock "$RV_ORIENTATION_PREVIOUS"; then
        rv_log "orientation restored=$RV_ORIENTATION_PREVIOUS"
    else
        rv_log "failure orientation restore=$RV_ORIENTATION_PREVIOUS"
    fi
    RV_ORIENTATION_CHANGED=0
}

rv_check_dependencies()
{
    RV_ERROR=
    if [ -n "${RV_DISPLAY_COMMAND:-}" ]; then
        [ -x "$RV_DISPLAY_COMMAND" ] || { RV_ERROR="display override is not executable: $RV_DISPLAY_COMMAND"; return 1; }
    else
        RV_FBINK=${RV_FBINK_COMMAND:-/mnt/us/koreader/fbink}
        if [ -n "${RV_EIPS_COMMAND:-}" ]; then
            RV_EIPS=$RV_EIPS_COMMAND
        elif command -v eips >/dev/null 2>&1; then
            RV_EIPS=$(command -v eips)
        elif [ -x /usr/bin/eips ]; then
            RV_EIPS=/usr/bin/eips
        else
            RV_ERROR="eips missing: firmware display command was not found"; return 1
        fi
        [ -x "$RV_EIPS" ] || { RV_ERROR="eips is not executable: $RV_EIPS"; return 1; }
        [ -x "$RV_FBINK" ] || { RV_ERROR="FBInk missing: install KOReader or set RV_FBINK_COMMAND"; return 1; }
    fi
    [ -r "$RV_FONT_REGULAR" ] || { RV_ERROR="regular font missing: $RV_FONT_REGULAR"; return 1; }
    [ -r "$RV_FONT_BOLD" ] || { RV_ERROR="bold font missing: $RV_FONT_BOLD"; return 1; }
    [ -r "$RV_TOUCH_SOURCE" ] || { RV_ERROR="touch device missing or unreadable: $RV_TOUCH_SOURCE"; return 1; }
    rv_manifest_load || return 1
    rv_log "dependencies display=${RV_DISPLAY_COMMAND:-native} fbink=${RV_FBINK:-override} eips=${RV_EIPS:-override} touch=$RV_TOUCH_SOURCE"
}
