#!/bin/sh
# Linux input_event decoding and gesture classification.

rv_hex_le32()
{
    # $1..$4 = little-endian hex byte pairs; sets RV_HEX32. Pure arithmetic
    # instead of `printf "%d" "0x..."` in a $(...) subshell: this runs up to
    # three times per captured record, and forking that often was still
    # measurably slow on the Kindle's CPU even after batching the hex dump.
    # `0x` is the portable C-style hex literal; ksh-style `16#` base literals
    # are not guaranteed on the Kindle's actual /bin/sh.
    RV_HEX32=$(( 0x$4$3$2$1 ))
}

rv_decode_touch_file()
{
    RV_TOUCH_FILE=$1
    RV_TOUCH_X=
    RV_TOUCH_Y=
    RV_X1=
    RV_Y1=
    RV_X2=
    RV_Y2=
    RV_START_SEC=
    RV_START_USEC=
    RV_END_SEC=
    RV_END_USEC=
    # One bulk hex dump instead of one `od` process spawn per 16-byte record:
    # a capture window can hold dozens of records, and forking `od` that many
    # times per gesture was the dominant source of input lag on the Kindle's
    # slow CPU. `-w16` keeps each line exactly one input_event record; `-v`
    # stops od from collapsing repeated-looking lines and silently dropping
    # records.
    RV_HEXDUMP=$(od -An -v -w16 -tx1 "$RV_TOUCH_FILE" 2>/dev/null)
    RV_OLD_IFS=$IFS
    IFS='
'
    for RV_EVENT_LINE in $RV_HEXDUMP; do
        IFS=$RV_OLD_IFS
        set -- $RV_EVENT_LINE
        RV_B1=${1:-}; RV_B2=${2:-}; RV_B3=${3:-}; RV_B4=${4:-}
        RV_B5=${5:-}; RV_B6=${6:-}; RV_B7=${7:-}; RV_B8=${8:-}
        RV_B9=${9:-}; shift 9
        RV_B10=${1:-}; RV_B11=${2:-}; RV_B12=${3:-}; RV_B13=${4:-}
        RV_B14=${5:-}; RV_B15=${6:-}; RV_B16=${7:-}
        [ -n "$RV_B16" ] || continue
        rv_hex_le32 "$RV_B1" "$RV_B2" "$RV_B3" "$RV_B4"; RV_SEC=$RV_HEX32
        rv_hex_le32 "$RV_B5" "$RV_B6" "$RV_B7" "$RV_B8"; RV_USEC=$RV_HEX32
        if [ -z "$RV_START_SEC" ]; then
            RV_START_SEC=$RV_SEC
            RV_START_USEC=$RV_USEC
        fi
        RV_END_SEC=$RV_SEC
        RV_END_USEC=$RV_USEC
        RV_TYPE_HEX="$RV_B10$RV_B9"
        RV_CODE_HEX="$RV_B12$RV_B11"
        if [ "$RV_TYPE_HEX" = "0003" ] && [ "$RV_CODE_HEX" = "0035" ]; then
            rv_hex_le32 "$RV_B13" "$RV_B14" "$RV_B15" "$RV_B16"; RV_TOUCH_X=$RV_HEX32
        elif [ "$RV_TYPE_HEX" = "0003" ] && [ "$RV_CODE_HEX" = "0036" ]; then
            rv_hex_le32 "$RV_B13" "$RV_B14" "$RV_B15" "$RV_B16"; RV_TOUCH_Y=$RV_HEX32
        fi
        if [ -n "$RV_TOUCH_X" ] && [ -n "$RV_TOUCH_Y" ]; then
            if [ -z "$RV_X1" ]; then
                RV_X1=$RV_TOUCH_X
                RV_Y1=$RV_TOUCH_Y
            fi
            RV_X2=$RV_TOUCH_X
            RV_Y2=$RV_TOUCH_Y
        fi
    done
    IFS=$RV_OLD_IFS
    [ -n "$RV_X1" ] || return 1
    # Subtract before multiplying so this remains safe on the Kindle's 32-bit shell.
    RV_DURATION_MS=$(((RV_END_SEC - RV_START_SEC) * 1000 + (RV_END_USEC - RV_START_USEC) / 1000))
    [ "$RV_DURATION_MS" -lt 0 ] && RV_DURATION_MS=0
    RV_RAW_X1=$RV_X1; RV_RAW_Y1=$RV_Y1
    RV_RAW_X2=$RV_X2; RV_RAW_Y2=$RV_Y2
    case "$RV_TOUCH_ROTATION" in
        L)
            RV_X1=$RV_RAW_Y1; RV_Y1=$((RV_TOUCH_NATIVE_W - 1 - RV_RAW_X1))
            RV_X2=$RV_RAW_Y2; RV_Y2=$((RV_TOUCH_NATIVE_W - 1 - RV_RAW_X2))
            ;;
        R)
            RV_X1=$((RV_TOUCH_NATIVE_H - 1 - RV_RAW_Y1)); RV_Y1=$RV_RAW_X1
            RV_X2=$((RV_TOUCH_NATIVE_H - 1 - RV_RAW_Y2)); RV_Y2=$RV_RAW_X2
            ;;
        D)
            RV_X1=$((RV_TOUCH_NATIVE_W - 1 - RV_RAW_X1)); RV_Y1=$((RV_TOUCH_NATIVE_H - 1 - RV_RAW_Y1))
            RV_X2=$((RV_TOUCH_NATIVE_W - 1 - RV_RAW_X2)); RV_Y2=$((RV_TOUCH_NATIVE_H - 1 - RV_RAW_Y2))
            ;;
        U) ;;
        *) rv_log "failure invalid touch rotation=$RV_TOUCH_ROTATION"; return 1 ;;
    esac
    rv_log "touch raw=$RV_RAW_X1,$RV_RAW_Y1-$RV_RAW_X2,$RV_RAW_Y2 logical=$RV_X1,$RV_Y1-$RV_X2,$RV_Y2 rotation=$RV_TOUCH_ROTATION duration_ms=$RV_DURATION_MS"
}

rv_classify_gesture()
{
    RV_X1=$1; RV_Y1=$2; RV_X2=$3; RV_Y2=$4; RV_DURATION_MS=$5
    RV_DX=$((RV_X2 - RV_X1)); [ "$RV_DX" -lt 0 ] && RV_DX=$((-RV_DX))
    RV_DY=$((RV_Y2 - RV_Y1)); RV_ABS_DY=$RV_DY; [ "$RV_ABS_DY" -lt 0 ] && RV_ABS_DY=$((-RV_ABS_DY))
    if [ "$RV_DX" -lt 40 ] && [ "$RV_ABS_DY" -lt 40 ] && [ "$RV_DURATION_MS" -ge 800 ]; then
        RV_GESTURE=hold
    elif [ "$RV_ABS_DY" -ge 80 ]; then
        if [ "$RV_DY" -lt 0 ]; then RV_GESTURE=swipe-up; else RV_GESTURE=swipe-down; fi
    else
        RV_GESTURE=tap
    fi
    rv_log "gesture kind=$RV_GESTURE dx=$RV_DX dy=$RV_DY"
}

rv_capture_gesture()
{
    if [ -n "${RV_TOUCH_EVENT_FILE:-}" ]; then
        [ "${RV_REPLAY_CONSUMED:-0}" -eq 0 ] || return 1
        RV_REPLAY_CONSUMED=1
        rv_decode_touch_file "$RV_TOUCH_EVENT_FILE" || return 1
        rv_classify_gesture "$RV_X1" "$RV_Y1" "$RV_X2" "$RV_Y2" "$RV_DURATION_MS"
        return 0
    fi
    RV_CAPTURE="$RV_TMP/touch-events.bin"
    rm -f "$RV_CAPTURE"
    # A quick tap rarely produces RV_TOUCH_CAPTURE_RECORDS worth of data on
    # its own, so `dd` racing a background timeout (instead of always
    # sleeping the full window) is what actually shortens tap latency; the
    # record count mainly lets a fast-moving swipe finish early too, instead
    # of both waiting out RV_TOUCH_POLL_SECONDS regardless of how quickly the
    # data arrived.
    dd if="$RV_TOUCH_SOURCE" of="$RV_CAPTURE" bs=16 count="$RV_TOUCH_CAPTURE_RECORDS" 2>/dev/null &
    RV_DD_PID=$!
    ( sleep "$RV_TOUCH_POLL_SECONDS"; kill "$RV_DD_PID" 2>/dev/null ) &
    RV_TIMEOUT_PID=$!
    wait "$RV_DD_PID" 2>/dev/null
    kill "$RV_TIMEOUT_PID" 2>/dev/null
    wait "$RV_TIMEOUT_PID" 2>/dev/null
    rv_decode_touch_file "$RV_CAPTURE" || return 1
    rv_classify_gesture "$RV_X1" "$RV_Y1" "$RV_X2" "$RV_Y2" "$RV_DURATION_MS"
}
