#!/usr/bin/env bash
# =============================================================================
# docker.sh - Docker management module (cache-only, never hangs)
# =============================================================================

[[ -n "${_DOCKER_SH_LOADED:-}" ]] && return 0
_DOCKER_SH_LOADED=1

docker_module_menu() {
    local items=(
        "Overview"
        "Containers"
        "Networks"
        "Volumes"
        "Images"
        "Resource Usage"
        "Restart Container"
        "Restart Docker"
        "View Logs"
        "daemon.json"
        "GPU Runtime"
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
        ui_draw_subscreen "${draw_mode}" "Docker" "${lines[@]}"
        ui_read_key >/dev/null
        draw_mode="nav"
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return 0 ;;
            q|Q) UI_RUNNING=0; return 0 ;;
            r|R) draw_mode="full"; continue ;;
            ''|$'\n'|$'\r')
                draw_mode="full"
                case "${index}" in
                    0) docker_show_overview ;;
                    1) docker_show_containers ;;
                    2) docker_show_networks ;;
                    3) docker_show_volumes ;;
                    4) docker_show_images ;;
                    5) docker_show_stats ;;
                    6) docker_restart_container ;;
                    7) docker_restart_daemon ;;
                    8) docker_view_logs ;;
                    9) docker_show_daemon_json ;;
                    10) docker_show_gpu_runtime ;;
                    11) return 0 ;;
                esac
                ;;
        esac
    done
}

docker_show_overview() {
    local lines=()
    local daemon running stopped version
    daemon=$(ui_cache_json docker.json .daemon_running)
    running=$(ui_cache_json docker.json .running_count)
    stopped=$(ui_cache_json docker.json .stopped_count)
    version=$(ui_cache_json docker.json '.info.server_version')

    lines+=("$(ui_section_header "Docker Overview")")
    if [[ "${daemon}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ Docker daemon running")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ Docker daemon not responding")")
        lines+=("$(ui_color "${COLOR_DIM}" "Data from cache — daemon may still be starting")")
    fi
    lines+=("")
    lines+=("$(ui_kv_line "Version" "${version}")")
    lines+=("$(ui_kv_line "Running" "${running}")")
    lines+=("$(ui_kv_line "Stopped" "${stopped}")")
    lines+=("$(ui_kv_line "Total" "$(ui_cache_json docker.json .container_count)")")
    lines+=("")
    lines+=("$(ui_cache_stale_indicator docker.json)")

    ui_draw_subscreen "Docker - Overview" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_containers() {
    local lines=()
    lines+=("$(ui_section_header "Containers (cached)")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local count
        count=$(jq '.containers | length' "${CACHE_DIR}/docker.json" 2>/dev/null || echo 0)
        local i
        for ((i = 0; i < count && i < 20; i++)); do
            local name status state health
            name=$(jq -r ".containers[${i}].name" "${CACHE_DIR}/docker.json")
            status=$(jq -r ".containers[${i}].status" "${CACHE_DIR}/docker.json")
            state=$(jq -r ".containers[${i}].state" "${CACHE_DIR}/docker.json")
            health=$(jq -r ".containers[${i}].health" "${CACHE_DIR}/docker.json")
            local icon
            if [[ "${state}" == "running" ]]; then
                icon=$(ui_color "${COLOR_STATUS_OK}" "●")
            else
                icon=$(ui_color "${COLOR_STATUS_ERR}" "○")
            fi
            lines+=("${icon} $(ui_truncate "${name}" 25) $(ui_color "${COLOR_DIM}" "${status}")")
            if [[ "${health}" != "none" && "${health}" != "null" ]]; then
                lines+=("  $(ui_color "${COLOR_DIM}" "Health: ${health}")")
            fi
        done
        if (( count > 20 )); then
            lines+=("$(ui_color "${COLOR_DIM}" "... and $((count - 20)) more")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No container cache available")")
    fi

    ui_draw_subscreen "Docker - Containers" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_networks() {
    local lines=()
    lines+=("$(ui_section_header "Networks")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local net_lines line
        mapfile -t net_lines < <(jq -r '.networks[]? | "\(.Name // .name // "unknown")  \(.Driver // .driver // "")"' "${CACHE_DIR}/docker.json" 2>/dev/null | head -20)
        for line in "${net_lines[@]}"; do
            lines+=("${line}")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No network data")"); fi

    ui_draw_subscreen "Docker - Networks" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_volumes() {
    local lines=()
    lines+=("$(ui_section_header "Volumes")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local vol_lines line
        mapfile -t vol_lines < <(jq -r '.volumes[]? | "\(.Name // .name // "unknown")  \(.Driver // .driver // "")"' "${CACHE_DIR}/docker.json" 2>/dev/null | head -20)
        for line in "${vol_lines[@]}"; do
            lines+=("${line}")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No volume data")"); fi

    ui_draw_subscreen "Docker - Volumes" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_images() {
    local lines=()
    lines+=("$(ui_section_header "Images")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local img_lines line
        mapfile -t img_lines < <(jq -r '.images[]? | "\(.Repository // .repository // "?"):\(.Tag // .tag // "?")  \(.Size // .size // "")"' "${CACHE_DIR}/docker.json" 2>/dev/null | head -20)
        for line in "${img_lines[@]}"; do
            lines+=("$(ui_truncate "${line}" 70)")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No image data")"); fi

    ui_draw_subscreen "Docker - Images" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_stats() {
    local lines=()
    lines+=("$(ui_section_header "Resource Usage (cached)")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local stat_lines line
        mapfile -t stat_lines < <(jq -r '.stats[]? | "\(.Name // .name): CPU \(.CPUPerc // .cpu // "?") MEM \(.MemUsage // .mem // "?")"' "${CACHE_DIR}/docker.json" 2>/dev/null | head -20)
        for line in "${stat_lines[@]}"; do
            lines+=("$(ui_truncate "${line}" 70)")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No stats data")"); fi

    ui_draw_subscreen "Docker - Resource Usage" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_restart_container() {
    if [[ ! -f "${CACHE_DIR}/docker.json" ]] || ! command -v jq >/dev/null 2>&1; then
        ui_message "Docker" "No container cache available"
        return
    fi

    local names=()
    mapfile -t names < <(jq -r '.containers[]?.name' "${CACHE_DIR}/docker.json" 2>/dev/null)
    if (( ${#names[@]} == 0 )); then
        ui_message "Docker" "No containers in cache"
        return
    fi

    ui_select_from_list "Select Container to Restart" "${names[@]}" || return
    local container="${REPLY}"

    if ui_confirm "Restart container '${container}'?"; then
        ui_message "Docker" "Restarting ${container}..."
        ui_run_timeout 60 docker restart "${container}" >/dev/null 2>&1 &
        ui_message "Docker" "Restart initiated for ${container}"
        # Trigger cache refresh
        "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
    fi
}

docker_restart_daemon() {
    if ui_confirm "Restart Docker daemon? This affects all containers."; then
        ui_message "Docker" "Restarting Docker..."
        systemctl restart docker >/dev/null 2>&1 &
        ui_message "Docker" "Docker restart initiated"
    fi
}

docker_view_logs() {
    if [[ ! -f "${CACHE_DIR}/docker.json" ]] || ! command -v jq >/dev/null 2>&1; then
        ui_message "Docker" "No container cache available"
        return
    fi

    local names=()
    mapfile -t names < <(jq -r '.containers[]?.name' "${CACHE_DIR}/docker.json" 2>/dev/null)
    ui_select_from_list "Select Container for Logs" "${names[@]}" || return
    local container="${REPLY}"

    local log_lines=()
    log_lines+=("$(ui_section_header "Logs: ${container}")")
    local logs
    logs=$(ui_run_timeout 30 docker logs --tail "${DOCKER_LOG_LINES:-100}" "${container}" 2>&1 || echo "Failed to fetch logs")
    while IFS= read -r line; do
        log_lines+=("$(ui_truncate "${line}" 100)")
    done <<< "${logs}"

    local offset=0
    while true; do
        ui_draw_scrollable_subscreen "Docker Logs - ${container}" "${offset}" "${log_lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((offset > 0)) && ((offset--)) || true ;;
            $'\x1b[B'|j|J) ((offset < ${#log_lines[@]} - 1)) && ((offset++)) || true ;;
            b|B|$'\x1b') return ;;
            q|Q) return ;;
            r|R)
                logs=$(ui_run_timeout 30 docker logs --tail "${DOCKER_LOG_LINES:-100}" "${container}" 2>&1)
                log_lines=()
                log_lines+=("$(ui_section_header "Logs: ${container}")")
                while IFS= read -r line; do
                    log_lines+=("$(ui_truncate "${line}" 100)")
                done <<< "${logs}"
                ;;
        esac
    done
}

docker_show_daemon_json() {
    local lines=()
    lines+=("$(ui_section_header "/etc/docker/daemon.json")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local dj_lines line
        mapfile -t dj_lines < <(jq -r '.daemon_json | to_entries[] | "\(.key): \(.value)"' "${CACHE_DIR}/docker.json" 2>/dev/null | head -20)
        for line in "${dj_lines[@]}"; do
            lines+=("${line}")
        done
        if [[ ! -f /etc/docker/daemon.json ]]; then
            lines+=("$(ui_color "${COLOR_DIM}" "File not found — using defaults")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No daemon.json cache")")
    fi

    ui_draw_subscreen "Docker - daemon.json" "${lines[@]}"
    ui_read_key >/dev/null
}

docker_show_gpu_runtime() {
    local lines=()
    lines+=("$(ui_section_header "GPU Runtime")")

    if [[ -f "${CACHE_DIR}/docker.json" ]] && command -v jq >/dev/null 2>&1; then
        local runtimes default_rt
        runtimes=$(jq -r '.info.runtimes | keys | join(", ")' "${CACHE_DIR}/docker.json" 2>/dev/null || echo "N/A")
        default_rt=$(jq -r '.info.default_runtime // "runc"' "${CACHE_DIR}/docker.json" 2>/dev/null)
        lines+=("$(ui_kv_line "Default Runtime" "${default_rt}")")
        lines+=("$(ui_kv_line "Available" "${runtimes}")")
        if echo "${runtimes}" | grep -q nvidia; then
            lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ NVIDIA runtime available")")
        else
            lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! NVIDIA runtime not detected")")
        fi
    fi

    ui_draw_subscreen "Docker - GPU Runtime" "${lines[@]}"
    ui_read_key >/dev/null
}
