#!/usr/bin/env bash
# =============================================================================
# system.sh - System information module
# =============================================================================

[[ -n "${_SYSTEM_SH_LOADED:-}" ]] && return 0
_SYSTEM_SH_LOADED=1

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

    while true; do
        ui_numbered_menu "System" "${items[@]}"
        case "${UI_MENU_RESULT}" in
            back) return 0 ;;
            refresh) continue ;;
            quit) UI_RUNNING=0; return 0 ;;
            select)
                case "${UI_MENU_INDEX}" in
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

    ui_info_screen "System - Overview" "${lines[@]}"
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

    ui_info_screen "System - CPU" "${lines[@]}"
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

    ui_info_screen "System - Memory" "${lines[@]}"
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

    ui_info_screen "System - Temperatures" "${lines[@]}"
}

system_show_filesystem() {
    local lines=()
    lines+=("$(ui_section_header "Filesystem Usage")")
    lines+=("$(ui_kv_line "Root (/)" "$(ui_cache_json system.json .root_usage_percent)% used")")
    lines+=("$(ui_kv_line "Available" "$(ui_cache_json system.json .root_avail) / $(ui_cache_json system.json .root_total)")")
    lines+=("$(ui_progress_bar "$(ui_cache_json system.json .root_usage_percent)" 30)")

    ui_info_screen "System - Filesystem" "${lines[@]}"
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

    ui_info_screen "System - Mounts" "${lines[@]}"
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

    ui_info_screen "System - SMART" "${lines[@]}"
}
