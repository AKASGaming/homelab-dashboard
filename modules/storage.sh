#!/usr/bin/env bash
# =============================================================================
# storage.sh - Storage, SMART, and disk health module
# =============================================================================

[[ -n "${_STORAGE_SH_LOADED:-}" ]] && return 0
_STORAGE_SH_LOADED=1

storage_module_menu() {
    local items=(
        "Overview"
        "SMART Health"
        "Disk Temperatures"
        "SSD Wear"
        "Filesystem"
        "Mounts"
        "Largest Folders"
        "Back"
    )

    while true; do
        ui_numbered_menu "Storage" "${items[@]}"
        case "${UI_MENU_RESULT}" in
            back|refresh) continue ;;
            quit) UI_RUNNING=0; return 0 ;;
            select)
                case "${UI_MENU_INDEX}" in
                    0) storage_show_overview ;;
                    1) storage_show_smart ;;
                    2) storage_show_temps ;;
                    3) storage_show_wear ;;
                    4) storage_show_filesystem ;;
                    5) storage_show_mounts ;;
                    6) storage_show_largest ;;
                    7) return 0 ;;
                esac
                ;;
        esac
    done
}

storage_show_overview() {
    local lines=()
    lines+=("$(ui_section_header "Storage Overview")")
    lines+=("$(ui_kv_line "Root Usage" "$(ui_cache_json system.json .root_usage_percent)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json system.json .root_usage_percent)" 30)")
    lines+=("$(ui_kv_line "Available" "$(ui_cache_json system.json .root_avail)")")

    if [[ -f "${CACHE_DIR}/storage.json" ]] && command -v jq >/dev/null 2>&1; then
        local count
        count=$(jq '.smart | length' "${CACHE_DIR}/storage.json" 2>/dev/null || echo 0)
        lines+=("")
        lines+=("$(ui_kv_line "SMART Devices" "${count}")")
    fi

    ui_info_screen "Storage - Overview" "${lines[@]}"
}

storage_show_smart() {
    local lines=()
    lines+=("$(ui_section_header "SMART Health")")

    if [[ -f "${CACHE_DIR}/storage.json" ]] && command -v jq >/dev/null 2>&1; then
        local count
        count=$(jq '.smart | length' "${CACHE_DIR}/storage.json" 2>/dev/null || echo 0)
        local i
        for ((i = 0; i < count; i++)); do
            local dev health
            dev=$(jq -r ".smart[${i}].device" "${CACHE_DIR}/storage.json")
            health=$(jq -r ".smart[${i}].health" "${CACHE_DIR}/storage.json")
            if echo "${health}" | grep -qi "passed"; then
                lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓") $(ui_kv_line "${dev}" "${health}")")
            else
                lines+=("$(ui_color "${COLOR_STATUS_WARN}" "!") $(ui_kv_line "${dev}" "${health}")")
            fi
        done
        if (( count == 0 )); then
            lines+=("$(ui_color "${COLOR_DIM}" "Install smartmontools for SMART data")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "SMART cache unavailable")")
    fi

    ui_info_screen "Storage - SMART" "${lines[@]}"
}

storage_show_temps() {
    local lines=()
    lines+=("$(ui_section_header "Disk Temperatures")")

    if [[ -f "${CACHE_DIR}/storage.json" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.smart[]? | "\(.device): \(.temperature)°C"' "${CACHE_DIR}/storage.json" 2>/dev/null | while IFS= read -r line; do
            lines+=("${line}")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No temperature data")"); fi

    ui_info_screen "Storage - Temperatures" "${lines[@]}"
}

storage_show_wear() {
    local lines=()
    lines+=("$(ui_section_header "SSD Wear")")

    if [[ -f "${CACHE_DIR}/storage.json" ]] && command -v jq >/dev/null 2>&1; then
        jq -r '.smart[]? | "\(.device): wear \(.wear)"' "${CACHE_DIR}/storage.json" 2>/dev/null | while IFS= read -r line; do
            lines+=("${line}")
        done
    fi
    if (( ${#lines[@]} < 2 )); then lines+=("$(ui_color "${COLOR_DIM}" "No wear data (NVMe/SATA SSD only)")"); fi

    ui_info_screen "Storage - SSD Wear" "${lines[@]}"
}

storage_show_filesystem() {
    local lines=()
    lines+=("$(ui_section_header "Filesystem Usage")")

    df -hP -x tmpfs -x devtmpfs 2>/dev/null | while IFS= read -r line; do
        lines+=("${line}")
    done

    ui_info_screen "Storage - Filesystem" "${lines[@]}"
}

storage_show_mounts() {
    local lines=()
    lines+=("$(ui_section_header "Mount Points")")

    findmnt -D 2>/dev/null | head -25 | while IFS= read -r line; do
        lines+=("${line}")
    done

    if (( ${#lines[@]} < 2 )); then
        mount 2>/dev/null | head -20 | while IFS= read -r line; do
            lines+=("${line}")
        done
    fi

    ui_info_screen "Storage - Mounts" "${lines[@]}"
}

storage_show_largest() {
    local lines=()
    lines+=("$(ui_section_header "Largest Folders (cached)")")
    lines+=("$(ui_color "${COLOR_DIM}" "Path: ${LARGEST_DIRS_PATH:-/}")")
    lines+=("")

    local dirs
    dirs=$(ui_cache_json storage.json .largest_dirs_raw)
    while IFS= read -r line; do
        [[ -n "${line}" ]] && lines+=("${line}")
    done <<< "${dirs}"

    if (( ${#lines[@]} < 3 )); then lines+=("$(ui_color "${COLOR_DIM}" "No data yet — collected by cache daemon")"); fi

    ui_info_screen "Storage - Largest Folders" "${lines[@]}"
}
