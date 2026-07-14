#!/usr/bin/env bash
# =============================================================================
# system.sh - System information module
# =============================================================================

[[ -n "${_SYSTEM_SH_LOADED:-}" ]] && return 0
_SYSTEM_SH_LOADED=1

system_show_menu() {
    local items=(
        "Overview"
        "CPU & Load"
        "Memory"
        "Temperatures"
        "Filesystem"
        "Mounts"
        "SMART Health"
        "Back"
    )
    local index=0

    while true; do
        case "${index}" in
            0) system_show_overview ;;
            1) system_show_cpu ;;
            2) system_show_memory ;;
            3) system_show_temps ;;
            4) system_show_filesystem ;;
            5) system_show_mounts ;;
            6) system_show_smart ;;
        esac

        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            b|B|$'\x1b') return 0 ;;
            q|Q) exit 0 ;;
            r|R) continue ;;
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || index=0 ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || index=$((${#items[@]} - 1)) ;;
            ''|$'\n'|$'\r')
                if (( index == 7 )); then return 0; fi
                ;;
        esac

        ui_select_from_list "System" "${items[@]}" || return 0
        index=0
        for i in "${!items[@]}"; do
            [[ "${items[$i]}" == "${REPLY}" ]] && index=$i
        done
    done
}

system_module_menu() {
    local items=(
        "Overview"
        "CPU & Load"
        "Memory"
        "Temperatures"
        "Filesystem"
        "Mounts"
        "SMART Health"
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
        ui_draw_subscreen "${draw_mode}" "System" "${lines[@]}"
        ui_read_key >/dev/null
        draw_mode="nav"
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return 0 ;;
            q|Q) UI_RUNNING=0; return 0 ;;
            r|R)
                draw_mode="full"
                case "${index}" in
                    0) system_show_overview; continue ;;
                    1) system_show_cpu; continue ;;
                    2) system_show_memory; continue ;;
                    3) system_show_temps; continue ;;
                    4) system_show_filesystem; continue ;;
                    5) system_show_mounts; continue ;;
                    6) system_show_smart; continue ;;
                esac
                ;;
            ''|$'\n'|$'\r')
                draw_mode="full"
                case "${index}" in
                    0) system_show_overview ;;
                    1) system_show_cpu ;;
                    2) system_show_memory ;;
                    3) system_show_temps ;;
                    4) system_show_filesystem ;;
                    5) system_show_mounts ;;
                    6) system_show_smart ;;
                    7) return 0 ;;
                esac
                ;;
        esac
    done
}

system_show_overview() {
    local lines=()
    lines+=("$(ui_section_header "System Overview")")
    lines+=("$(ui_kv_line "Hostname" "$(ui_cache_json system.json .hostname)")")
    lines+=("$(ui_kv_line "OS" "$(ui_cache_json system.json .os)")")
    lines+=("$(ui_kv_line "Kernel" "$(ui_cache_json system.json .kernel)")")
    lines+=("$(ui_kv_line "Uptime" "$(ui_cache_json system.json .uptime_human)")")
    lines+=("$(ui_kv_line "Load" "$(ui_cache_json system.json .load)")")
    lines+=("")

    local reboot
    reboot=$(ui_cache_json system.json .pending_reboot)
    if [[ "${reboot}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "⚠ Pending reboot required")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ No pending reboot")")
    fi

    lines+=("")
    lines+=("$(ui_kv_line "CPU" "$(ui_cache_json system.json .cpu_percent)%") $(ui_progress_bar "$(ui_cache_json system.json .cpu_percent)")")
    lines+=("$(ui_kv_line "RAM" "$(ui_cache_json system.json .ram_percent)%") $(ui_progress_bar "$(ui_cache_json system.json .ram_percent)")")
    lines+=("$(ui_kv_line "Root" "$(ui_cache_json system.json .root_usage_percent)% used ($(ui_cache_json system.json .root_avail) free)")")

    local age
    age=$(ui_cache_age system.json)
    lines+=("")
    lines+=("$(ui_color "${COLOR_DIM}" "Cache age: ${age}s")")

    ui_draw_subscreen "System - Overview" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_cpu() {
    local lines=()
    lines+=("$(ui_section_header "CPU & Load Average")")
    lines+=("$(ui_kv_line "CPU Usage" "$(ui_cache_json system.json .cpu_percent)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json system.json .cpu_percent)" 30)")
    lines+=("")
    lines+=("$(ui_kv_line "Load (1/5/15)" "$(ui_cache_json system.json .load)")")

    if [[ -f /proc/cpuinfo ]]; then
        local cores model
        cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
        model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "unknown")
        lines+=("$(ui_kv_line "Cores" "${cores}")")
        lines+=("$(ui_kv_line "Model" "${model}")")
    fi

    ui_draw_subscreen "System - CPU" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_memory() {
    local lines=()
    lines+=("$(ui_section_header "Memory")")
    lines+=("$(ui_kv_line "Usage" "$(ui_cache_json system.json .ram_percent)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json system.json .ram_percent)" 30)")

    if [[ -f /proc/meminfo ]]; then
        local total avail used
        total=$(awk '/MemTotal/{printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
        avail=$(awk '/MemAvailable/{printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
        used=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f GiB", (t-a)/1024/1024}' /proc/meminfo)
        lines+=("")
        lines+=("$(ui_kv_line "Total" "${total}")")
        lines+=("$(ui_kv_line "Used" "${used}")")
        lines+=("$(ui_kv_line "Available" "${avail}")")
    fi

    ui_draw_subscreen "System - Memory" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_temps() {
    local lines=()
    lines+=("$(ui_section_header "Temperatures")")

    if command -v sensors >/dev/null 2>&1; then
        local sensor_out
        sensor_out=$(sensors 2>/dev/null | head -30 || echo "sensors unavailable")
        while IFS= read -r line; do
            lines+=("${line}")
        done <<< "${sensor_out}"
    else
        local temps
        temps=$(ui_cache_json system.json '.temperatures[]?' 2>/dev/null || echo "")
        if [[ -n "${temps}" ]]; then
            while IFS= read -r t; do
                lines+=("$(ui_kv_line "Sensor" "${t}°C")")
            done <<< "${temps}"
        else
            lines+=("$(ui_color "${COLOR_DIM}" "No temperature data available")")
        fi
    fi

    ui_draw_subscreen "System - Temperatures" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_filesystem() {
    local lines=()
    lines+=("$(ui_section_header "Filesystem Usage")")
    lines+=("$(ui_kv_line "Root (/)" "$(ui_cache_json system.json .root_usage_percent)% used")")
    lines+=("$(ui_kv_line "Available" "$(ui_cache_json system.json .root_avail) / $(ui_cache_json system.json .root_total)")")
    lines+=("$(ui_progress_bar "$(ui_cache_json system.json .root_usage_percent)" 30)")

    ui_draw_subscreen "System - Filesystem" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_mounts() {
    local lines=()
    lines+=("$(ui_section_header "Mounted Drives")")

    local mounts
    mounts=$(df -hP -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 || echo "")
    if [[ -n "${mounts}" ]]; then
        lines+=("$(ui_color "${COLOR_LABEL}" "$(printf '%-20s %-8s %-8s %s' "Device" "Mount" "Use%" "Avail")")")
        while IFS= read -r line; do
            local dev mount use avail
            dev=$(echo "${line}" | awk '{print $1}')
            mount=$(echo "${line}" | awk '{print $6}')
            use=$(echo "${line}" | awk '{print $5}')
            avail=$(echo "${line}" | awk '{print $4}')
            lines+=("$(printf '%-20s %-8s %-8s %s' "${dev}" "${mount}" "${use}" "${avail}")")
        done <<< "${mounts}"
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No mount data")")
    fi

    ui_draw_subscreen "System - Mounts" "${lines[@]}"
    ui_read_key >/dev/null
}

system_show_smart() {
    local lines=()
    lines+=("$(ui_section_header "SMART Health (from cache)")")

    if command -v jq >/dev/null 2>&1 && [[ -f "${CACHE_DIR}/storage.json" ]]; then
        local count
        count=$(jq '.smart | length' "${CACHE_DIR}/storage.json" 2>/dev/null || echo 0)
        local i
        for ((i = 0; i < count; i++)); do
            local dev health temp wear
            dev=$(jq -r ".smart[${i}].device" "${CACHE_DIR}/storage.json")
            health=$(jq -r ".smart[${i}].health" "${CACHE_DIR}/storage.json")
            temp=$(jq -r ".smart[${i}].temperature" "${CACHE_DIR}/storage.json")
            wear=$(jq -r ".smart[${i}].wear" "${CACHE_DIR}/storage.json")
            lines+=("$(ui_kv_line "${dev}" "${health}")")
            lines+=("  $(ui_color "${COLOR_DIM}" "Temp: ${temp}°C  Wear: ${wear}")")
        done
        if (( count == 0 )); then
            lines+=("$(ui_color "${COLOR_DIM}" "No SMART data. Install smartmontools.")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "SMART cache unavailable")")
    fi

    ui_draw_subscreen "System - SMART" "${lines[@]}"
    ui_read_key >/dev/null
}
