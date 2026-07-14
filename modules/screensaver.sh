#!/usr/bin/env bash
# =============================================================================
# screensaver.sh - Animated ANSI starfield screensaver
# =============================================================================

[[ -n "${_SCREENSAVER_SH_LOADED:-}" ]] && return 0
_SCREENSAVER_SH_LOADED=1

screensaver_run() {
    local star_count="${SCREENSAVER_STAR_COUNT:-80}"
    local width height
    ui_update_size
    width=${UI_COLS}
    height=${UI_ROWS}

    ui_hide_cursor
    ui_clear

    # Star positions and speeds
    local -a star_x star_y star_speed star_char
    local i
    for ((i = 0; i < star_count; i++)); do
        star_x[$i]=$((RANDOM % width))
        star_y[$i]=$((RANDOM % height))
        star_speed[$i]=$((RANDOM % 3 + 1))
        case $((RANDOM % 3)) in
            0) star_char[$i]='·' ;;
            1) star_char[$i]='*' ;;
            2) star_char[$i]='.' ;;
        esac
    done

    local frame=0
    while true; do
        # Check for keypress (non-blocking)
        if read -rsn1 -t 0.05 key 2>/dev/null; then
            break
        fi

        # Double-buffer style: move cursor home, don't full clear (reduces flicker)
        printf '\033[H'

        # Draw title dimly at top
        printf '\033[%sm' "${COLOR_DIM}"
        ui_center "THEATERNAS" "${width}"
        printf '\n'

        # Update and draw stars
        for ((i = 0; i < star_count; i++)); do
            star_y[$i]=$((star_y[$i] + star_speed[$i]))
            if (( star_y[$i] >= height )); then
                star_y[$i]=0
                star_x[$i]=$((RANDOM % width))
                star_speed[$i]=$((RANDOM % 3 + 1))
            fi

            # Brightness based on speed
            local color
            case "${star_speed[$i]}" in
                1) color="${COLOR_DIM}" ;;
                2) color="${COLOR_LABEL}" ;;
                *) color="${COLOR_VALUE}" ;;
            esac

            printf '\033[%d;%dH' $((star_y[$i] + 1)) $((star_x[$i] + 1))
            printf '\033[%sm%s' "${color}" "${star_char[$i]}"
        done

        # Status line at bottom
        printf '\033[%d;1H' "${height}"
        ui_reset_attrs
        printf '\033[%sm' "${COLOR_DIM}"
        local hostname
        hostname=$(ui_cache_json system.json .hostname "TheaterNAS")
        ui_center "Press any key to exit  |  ${hostname}" "${width}"

        ui_reset_attrs
        ((frame++))
        sleep 0.08
    done

    ui_reset_attrs
    ui_show_cursor
}

screensaver_check_idle() {
    local idle_seconds="${SCREENSAVER_IDLE_SECONDS:-300}"
    [[ "${SCREENSAVER_ENABLED:-true}" != "true" ]] && return 1
    # Idle detection is best-effort; screensaver also accessible via 'S' key
    return 1
}
