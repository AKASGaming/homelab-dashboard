#!/usr/bin/env bash
# =============================================================================
# media.sh - Pi-hole v6 and Plex media services module
# =============================================================================

[[ -n "${_MEDIA_SH_LOADED:-}" ]] && return 0
_MEDIA_SH_LOADED=1

media_module_menu() {
    local items=(
        "Overview"
        "Pi-hole Status"
        "Pi-hole Stats"
        "Pi-hole Logs"
        "Plex Status"
        "Plex Sessions"
        "Plex Logs"
        "Back"
    )

    while true; do
        ui_numbered_menu "Media" "${items[@]}"
        case "${UI_MENU_RESULT}" in
            back) return 0 ;;
            refresh) continue ;;
            quit) UI_RUNNING=0; return 0 ;;
            select)
                case "${UI_MENU_INDEX}" in
                    0) media_show_overview ;;
                    1) media_show_pihole_status ;;
                    2) media_show_pihole_stats ;;
                    3) media_show_pihole_logs ;;
                    4) media_show_plex_status ;;
                    5) media_show_plex_sessions ;;
                    6) media_show_plex_logs ;;
                    7) return 0 ;;
                esac
                ;;
        esac
    done
}

media_show_overview() {
    local lines=()
    lines+=("$(ui_section_header "Media Services")")

    local pihole_running plex_running
    pihole_running=$(ui_cache_json media.json '.pihole.running')
    plex_running=$(ui_cache_json media.json '.plex.running')

    lines+=("$(ui_color "${COLOR_LABEL}" "Pi-hole ")$(ui_status_icon "$([[ "${pihole_running}" == "true" ]] && echo ok || echo err)") $(ui_color "${COLOR_VALUE}" "${PIHOLE_CONTAINER:-pihole}")")
    lines+=("$(ui_color "${COLOR_LABEL}" "Plex ")$(ui_status_icon "$([[ "${plex_running}" == "true" ]] && echo ok || echo err)") $(ui_color "${COLOR_VALUE}" "${PLEX_CONTAINER:-plex}")")
    lines+=("")
    lines+=("$(ui_kv_line "Pi-hole Queries" "$(ui_cache_json media.json '.pihole.queries_total')")")
    lines+=("$(ui_kv_line "Pi-hole Blocked" "$(ui_cache_json media.json '.pihole.queries_blocked')")")
    lines+=("$(ui_kv_line "Plex Sessions" "$(ui_cache_json media.json '.plex.sessions')")")

    ui_info_screen "Media - Overview" "${lines[@]}"
}

media_show_pihole_status() {
    local lines=()
    lines+=("$(ui_section_header "Pi-hole Status")")
    lines+=("$(ui_kv_line "Container" "${PIHOLE_CONTAINER:-pihole}")")
    lines+=("$(ui_kv_line "API URL" "${PIHOLE_API_URL:-http://127.0.0.1}:${PIHOLE_API_PORT:-80}")")

    local running status
    running=$(ui_cache_json media.json '.pihole.running')
    status=$(ui_cache_json media.json '.pihole.status')

    if [[ "${running}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ Container running")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ Container not running")")
    fi
    lines+=("$(ui_kv_line "API Status" "${status}")")

    ui_info_screen "Media - Pi-hole Status" "${lines[@]}"
}

media_show_pihole_stats() {
    local lines=()
    lines+=("$(ui_section_header "Pi-hole v6 Stats")")

    if [[ -f "${CACHE_DIR}/media.json" ]] && command -v jq >/dev/null 2>&1; then
        local summary
        summary=$(jq -r '.pihole.summary' "${CACHE_DIR}/media.json" 2>/dev/null)
        if [[ "${summary}" != "{}" && "${summary}" != "null" ]]; then
            lines+=("$(ui_kv_line "Total Queries" "$(jq -r '.pihole.queries_total' "${CACHE_DIR}/media.json")")")
            lines+=("$(ui_kv_line "Blocked" "$(jq -r '.pihole.queries_blocked' "${CACHE_DIR}/media.json")")")
            jq -r '.pihole.summary | to_entries[] | "\(.key): \(.value)"' "${CACHE_DIR}/media.json" 2>/dev/null | head -15 | while IFS= read -r line; do
                lines+=("$(ui_truncate "${line}" 70)")
            done
        else
            lines+=("$(ui_color "${COLOR_DIM}" "No Pi-hole API data. Check PIHOLE_API_PASSWORD in config.")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "Stats cache unavailable")")
    fi

    ui_info_screen "Media - Pi-hole Stats" "${lines[@]}"
}

media_show_pihole_logs() {
    local lines=()
    lines+=("$(ui_section_header "Pi-hole Logs (cached)")")

    local logs
    logs=$(ui_cache_json media.json '.pihole.logs_raw')
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 90)")
    done <<< "${logs}"

    local offset=0
    while true; do
        ui_draw_scrollable_subscreen "Media - Pi-hole Logs" "${offset}" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((offset > 0)) && ((offset--)) || true ;;
            $'\x1b[B'|j|J) ((offset < ${#lines[@]} - 1)) && ((offset++)) || true ;;
            $'\r'|$'\n'|b|B|$'\x1b'|q|Q) return ;;
            r|R)
                if command -v docker >/dev/null 2>&1; then
                    logs=$(ui_run_timeout 15 docker logs --tail 30 "${PIHOLE_CONTAINER:-pihole}" 2>&1)
                    lines=()
                    lines+=("$(ui_section_header "Pi-hole Logs (live)")")
                    while IFS= read -r line; do
                        lines+=("$(ui_truncate "${line}" 90)")
                    done <<< "${logs}"
                fi
                ;;
        esac
    done
}

media_show_plex_status() {
    local lines=()
    lines+=("$(ui_section_header "Plex Status")")
    lines+=("$(ui_kv_line "Container" "${PLEX_CONTAINER:-plex}")")
    lines+=("$(ui_kv_line "URL" "${PLEX_URL:-http://127.0.0.1:32400}")")

    local running
    running=$(ui_cache_json media.json '.plex.running')
    if [[ "${running}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ Container running")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ Container not running")")
    fi
    lines+=("$(ui_kv_line "Active Sessions" "$(ui_cache_json media.json '.plex.sessions')")")

    ui_info_screen "Media - Plex Status" "${lines[@]}"
}

media_show_plex_sessions() {
    local lines=()
    lines+=("$(ui_section_header "Plex Sessions / Transcodes")")

    local sessions
    sessions=$(ui_cache_json media.json '.plex.sessions_raw')
    if [[ -n "${sessions}" && "${sessions}" != "[]" ]]; then
        echo "${sessions}" | head -30 | while IFS= read -r line; do
            lines+=("$(ui_truncate "${line}" 80)")
        done
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No active sessions")")
    fi
    lines+=("")
    lines+=("$(ui_kv_line "Session Count" "$(ui_cache_json media.json '.plex.sessions')")")

    ui_info_screen "Media - Plex Sessions" "${lines[@]}"
}

media_show_plex_logs() {
    local lines=()
    lines+=("$(ui_section_header "Plex Logs (cached)")")

    local logs
    logs=$(ui_cache_json media.json '.plex.logs_raw')
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 90)")
    done <<< "${logs}"

    local offset=0
    while true; do
        ui_draw_scrollable_subscreen "Media - Plex Logs" "${offset}" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((offset > 0)) && ((offset--)) || true ;;
            $'\x1b[B'|j|J) ((offset < ${#lines[@]} - 1)) && ((offset++)) || true ;;
            $'\r'|$'\n'|b|B|$'\x1b'|q|Q) return ;;
            r|R)
                if command -v docker >/dev/null 2>&1; then
                    logs=$(ui_run_timeout 15 docker logs --tail 30 "${PLEX_CONTAINER:-plex}" 2>&1)
                    lines=()
                    while IFS= read -r line; do
                        lines+=("$(ui_truncate "${line}" 90)")
                    done <<< "${logs}"
                fi
                ;;
        esac
    done
}
