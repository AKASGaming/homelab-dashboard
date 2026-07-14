#!/usr/bin/env bash
# =============================================================================
# logs.sh - System, kernel, and Docker log viewer module
# =============================================================================

[[ -n "${_LOGS_SH_LOADED:-}" ]] && return 0
_LOGS_SH_LOADED=1

logs_module_menu() {
    local items=(
        "Journal"
        "Kernel"
        "Docker"
        "Search"
        "Follow Journal"
        "Back"
    )
    local index=0

    while true; do
        local lines=()
        local i
        for ((i = 0; i < ${#items[@]}; i++)); do
            if (( i == index )); then
                lines+=("$(ui_color "${COLOR_MENU_ACTIVE}" "> ${items[$i]}")")
            else
                lines+=("  ${items[$i]}")
            fi
        done
        ui_draw_subscreen "Logs" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return 0 ;;
            q|Q) UI_RUNNING=0; return 0 ;;
            r|R) continue ;;
            ''|$'\n'|$'\r')
                case "${index}" in
                    0) logs_show_journal ;;
                    1) logs_show_kernel ;;
                    2) logs_show_docker ;;
                    3) logs_search ;;
                    4) logs_follow_journal ;;
                    5) return 0 ;;
                esac
                ;;
        esac
    done
}

logs_build_lines() {
    local title="$1"
    local content="$2"
    local lines=()
    lines+=("$(ui_section_header "${title}")")
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 100)")
    done <<< "${content}"
    echo "${lines[@]}"
}

logs_show_scrollable() {
    local title="$1"
    local content="$2"
    local lines=()
    lines+=("$(ui_section_header "${title}")")
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 100)")
    done <<< "${content}"

    local offset=0
    while true; do
        ui_draw_scrollable_subscreen "Logs - ${title}" "${offset}" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((offset > 0)) && ((offset--)) || true ;;
            $'\x1b[B'|j|J) ((offset < ${#lines[@]} - 1)) && ((offset++)) || true ;;
            b|B|$'\x1b') return ;;
            q|Q) return ;;
        esac
    done
}

logs_show_journal() {
    local content
    content=$(journalctl -n "${JOURNAL_LINES:-50}" --no-pager 2>/dev/null || echo "journalctl unavailable")
    logs_show_scrollable "Journal" "${content}"
}

logs_show_kernel() {
    local content
    content=$(journalctl -k -n "${KERNEL_LOG_LINES:-50}" --no-pager 2>/dev/null || dmesg 2>/dev/null | tail -"${KERNEL_LOG_LINES:-50}" || echo "kernel logs unavailable")
    logs_show_scrollable "Kernel" "${content}"
}

logs_show_docker() {
    if [[ ! -f "${CACHE_DIR}/docker.json" ]] || ! command -v jq >/dev/null 2>&1; then
        ui_message "Logs" "Docker cache unavailable"
        return
    fi

    local names=()
    mapfile -t names < <(jq -r '.containers[]?.name' "${CACHE_DIR}/docker.json" 2>/dev/null)
    if (( ${#names[@]} == 0 )); then
        ui_message "Logs" "No containers in cache"
        return
    fi

    ui_select_from_list "Select Container" "${names[@]}" || return
    local container="${REPLY}"
    local content
    content=$(ui_run_timeout 30 docker logs --tail "${DOCKER_LOG_LINES:-100}" "${container}" 2>&1 || echo "Failed to fetch logs")
    logs_show_scrollable "Docker - ${container}" "${content}"
}

logs_search() {
    ui_text_input "Search term:" "" || return
    local term="${REPLY}"
    [[ -z "${term}" ]] && return

    local content
    content=$(journalctl --no-pager 2>/dev/null | grep -i "${term}" | tail -50 || echo "No matches for '${term}'")
    logs_show_scrollable "Search: ${term}" "${content}"
}

logs_follow_journal() {
    local width="${UI_COLS}"
    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "Following Journal (any key to stop)")" $((width - 4)))"
    ui_draw_separator "${width}"

    journalctl -f -n 5 --no-pager 2>/dev/null &
    local jpid=$!

    ui_read_key >/dev/null
    kill "${jpid}" 2>/dev/null || true
}
