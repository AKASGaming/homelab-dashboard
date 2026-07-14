#!/usr/bin/env bash
# =============================================================================
# quickactions.sh - Quick system and container actions with confirmations
# =============================================================================

[[ -n "${_QUICKACTIONS_SH_LOADED:-}" ]] && return 0
_QUICKACTIONS_SH_LOADED=1

quickactions_module_menu() {
    local items=(
        "Restart Containers"
        "Restart Docker"
        "Restart Networking"
        "Restart Tailscale"
        "Restart Pi-hole"
        "Restart Plex"
        "Reboot System"
        "Shutdown System"
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
        ui_draw_subscreen "Quick Actions" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return 0 ;;
            q|Q) UI_RUNNING=0; return 0 ;;
            ''|$'\n'|$'\r')
                case "${index}" in
                    0) quickactions_restart_containers ;;
                    1) quickactions_restart_docker ;;
                    2) quickactions_restart_networking ;;
                    3) quickactions_restart_tailscale ;;
                    4) quickactions_restart_pihole ;;
                    5) quickactions_restart_plex ;;
                    6) quickactions_reboot ;;
                    7) quickactions_shutdown ;;
                    8) return 0 ;;
                esac
                ;;
        esac
    done
}

quickactions_restart_containers() {
    local containers
    IFS=',' read -ra containers <<< "${QUICK_ACTION_CONTAINERS:-pihole,plex,tailscale}"

    local items=("${containers[@]}" "All Quick Action Containers" "Back")
    ui_select_from_list "Restart Container" "${items[@]}" || return

    if [[ "${REPLY}" == "Back" ]]; then
        return
    elif [[ "${REPLY}" == "All Quick Action Containers" ]]; then
        if ui_confirm "Restart all quick action containers?"; then
            for c in "${containers[@]}"; do
                c=$(echo "${c}" | tr -d ' ')
                [[ -z "${c}" ]] && continue
                docker restart "${c}" >/dev/null 2>&1 &
            done
            ui_message "Quick Actions" "Restart initiated for all containers"
        fi
    else
        if ui_confirm "Restart container '${REPLY}'?"; then
            docker restart "${REPLY}" >/dev/null 2>&1 &
            ui_message "Quick Actions" "Restart initiated for ${REPLY}"
        fi
    fi
    "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
}

quickactions_restart_docker() {
    if ui_confirm "Restart Docker daemon? All containers will be affected."; then
        systemctl restart docker >/dev/null 2>&1 &
        ui_message "Quick Actions" "Docker restart initiated"
    fi
}

quickactions_restart_networking() {
    if ui_confirm "Restart networking (systemd-networkd/NetworkManager)?"; then
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
            systemctl restart NetworkManager >/dev/null 2>&1 &
        elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
            systemctl restart systemd-networkd >/dev/null 2>&1 &
        else
            ui_message "Quick Actions" "No supported network manager found"
            return
        fi
        ui_message "Quick Actions" "Networking restart initiated"
    fi
}

quickactions_restart_tailscale() {
    local container="${TAILSCALE_CONTAINER:-tailscale}"
    if ui_confirm "Restart Tailscale container '${container}'?"; then
        docker restart "${container}" >/dev/null 2>&1 &
        ui_message "Quick Actions" "Tailscale restart initiated"
        "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
    fi
}

quickactions_restart_pihole() {
    local container="${PIHOLE_CONTAINER:-pihole}"
    if ui_confirm "Restart Pi-hole container '${container}'?"; then
        docker restart "${container}" >/dev/null 2>&1 &
        ui_message "Quick Actions" "Pi-hole restart initiated"
        "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
    fi
}

quickactions_restart_plex() {
    local container="${PLEX_CONTAINER:-plex}"
    if ui_confirm "Restart Plex container '${container}'?"; then
        docker restart "${container}" >/dev/null 2>&1 &
        ui_message "Quick Actions" "Plex restart initiated"
        "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
    fi
}

quickactions_reboot() {
    if ui_confirm "Reboot the system?"; then
        ui_cleanup
        reboot
    fi
}

quickactions_shutdown() {
    if ui_confirm "Shutdown the system?"; then
        if ui_confirm "Are you absolutely sure?"; then
            ui_cleanup
            shutdown -h now
        fi
    fi
}
