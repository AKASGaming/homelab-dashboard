#!/usr/bin/env bash
# =============================================================================
# settings.sh - Dashboard settings and configuration module
# =============================================================================

[[ -n "${_SETTINGS_SH_LOADED:-}" ]] && return 0
_SETTINGS_SH_LOADED=1

settings_module_menu() {
    local items=(
        "Theme Selector"
        "Edit Config"
        "Refresh Cache"
        "Reload Cache Daemon"
        "Version Info"
        "Back"
    )
    local index=0
    local draw_mode="full"

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
        ui_draw_subscreen "${draw_mode}" "Settings" "${lines[@]}"
        ui_read_key >/dev/null
        draw_mode="nav"
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return 0 ;;
            q|Q) UI_RUNNING=0; return 0 ;;
            r|R) draw_mode="full"; continue ;;
            $'\r'|$'\n')
                draw_mode="full"
                case "${index}" in
                    0) settings_theme_selector ;;
                    1) settings_edit_config ;;
                    2) settings_refresh_cache ;;
                    3) settings_reload_daemon ;;
                    4) settings_version_info ;;
                    5) return 0 ;;
                esac
                ;;
        esac
    done
}

settings_list_themes() {
    local themes=()
    local f name
    for f in "${INSTALL_DIR}"/themes/*.theme; do
        [[ -f "${f}" ]] || continue
        name=$(basename "${f}" .theme)
        themes+=("${name}")
    done
    echo "${themes[@]}"
}

settings_theme_selector() {
    local themes
    read -ra themes <<< "$(settings_list_themes)"

    if (( ${#themes[@]} == 0 )); then
        ui_message "Settings" "No themes found"
        return
    fi

    ui_select_from_list "Select Theme" "${themes[@]}" || return
    local selected="${REPLY}"

    if [[ -f "${INSTALL_DIR}/config/config.conf" ]]; then
        if grep -q '^THEME=' "${INSTALL_DIR}/config/config.conf"; then
            sed -i "s/^THEME=.*/THEME=\"${selected}\"/" "${INSTALL_DIR}/config/config.conf"
        else
            echo "THEME=\"${selected}\"" >> "${INSTALL_DIR}/config/config.conf"
        fi
        THEME="${selected}"
        ui_load_theme
        ui_message "Settings" "Theme set to ${selected}"
    fi
}

settings_edit_config() {
    local config="${INSTALL_DIR}/config/config.conf"
    local editor="${EDITOR:-nano}"

    ui_cleanup
    if command -v "${editor}" >/dev/null 2>&1; then
        "${editor}" "${config}"
    elif command -v vi >/dev/null 2>&1; then
        vi "${config}"
    else
        ui_message "Settings" "No editor found. Set EDITOR env var."
        return
    fi
    ui_save_screen
    ui_load_config "${config}"
    ui_load_theme
}

settings_refresh_cache() {
    ui_message "Settings" "Refreshing cache..."
    "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
    wait $! 2>/dev/null || true
    ui_message "Settings" "Cache refresh complete"
}

settings_reload_daemon() {
    local service="${CACHE_SERVICE_NAME:-homelab-dashboard-cache}"
    if ui_confirm "Reload cache daemon service '${service}'?"; then
        systemctl restart "${service}" 2>/dev/null || {
            ui_message "Settings" "Failed to restart service"
            return
        }
        ui_message "Settings" "Cache daemon reloaded"
    fi
}

settings_version_info() {
    local lines=()
    lines+=("$(ui_section_header "Version Information")")
    lines+=("$(ui_kv_line "Dashboard" "$(ui_get_version)")")
    lines+=("$(ui_kv_line "Install Dir" "${INSTALL_DIR}")")
    lines+=("$(ui_kv_line "Theme" "${THEME:-default}")")
    lines+=("$(ui_kv_line "Cache Interval" "${CACHE_INTERVAL:-30}s")")
    lines+=("")

    if [[ -f "${CACHE_DIR}/daemon_status.json" ]]; then
        local last_cycle pid
        last_cycle=$(ui_cache_json daemon_status.json .last_cycle)
        pid=$(ui_cache_json daemon_status.json .pid)
        lines+=("$(ui_kv_line "Daemon PID" "${pid}")")
        lines+=("$(ui_kv_line "Last Cycle" "$(date -d @${last_cycle} 2>/dev/null || echo ${last_cycle})")")
    fi

    lines+=("")
    lines+=("$(ui_color "${COLOR_DIM}" "TheaterNAS Control Center")")
    lines+=("$(ui_color "${COLOR_DIM}" "https://github.com/AKASGaming/homelab-dashboard")")

    ui_draw_subscreen "Settings - Version" "${lines[@]}"
    ui_read_key >/dev/null
}
