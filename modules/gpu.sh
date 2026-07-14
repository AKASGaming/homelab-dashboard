#!/usr/bin/env bash
# =============================================================================
# gpu.sh - NVIDIA GPU monitoring and maintenance module
# =============================================================================

[[ -n "${_GPU_SH_LOADED:-}" ]] && return 0
_GPU_SH_LOADED=1

gpu_module_menu() {
    local items=(
        "Overview"
        "Utilization"
        "Memory"
        "Temperature & Power"
        "Encoder/Decoder"
        "Processes"
        "nvidia-smi -q"
        "Maintenance"
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
        ui_draw_subscreen "${draw_mode}" "GPU" "${lines[@]}"
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
                    0) gpu_show_overview ;;
                    1) gpu_show_utilization ;;
                    2) gpu_show_memory ;;
                    3) gpu_show_temp_power ;;
                    4) gpu_show_encoder ;;
                    5) gpu_show_processes ;;
                    6) gpu_show_full_query ;;
                    7) gpu_maintenance_menu ;;
                    8) return 0 ;;
                esac
                ;;
        esac
    done
}

gpu_show_overview() {
    local lines=()
    local available
    available=$(ui_cache_json gpu.json .available)

    lines+=("$(ui_section_header "GPU Overview")")
    if [[ "${available}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ NVIDIA GPU detected")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU not available")")
    fi
    lines+=("")
    lines+=("$(ui_kv_line "GPU" "$(ui_cache_json gpu.json .gpu_name)")")
    lines+=("$(ui_kv_line "Driver" "$(ui_cache_json gpu.json .driver)")")
    lines+=("$(ui_kv_line "Utilization" "$(ui_cache_json gpu.json .utilization)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json gpu.json .utilization)" 25)")
    lines+=("$(ui_kv_line "Temperature" "$(ui_cache_json gpu.json .temperature)")")
    lines+=("$(ui_kv_line "Power" "$(ui_cache_json gpu.json .power) W")")

    ui_draw_subscreen "GPU - Overview" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_utilization() {
    local lines=()
    lines+=("$(ui_section_header "GPU Utilization")")
    lines+=("$(ui_kv_line "GPU" "$(ui_cache_json gpu.json .utilization)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json gpu.json .utilization)" 40)")
    lines+=("")
    lines+=("$(ui_kv_line "Encoder" "$(ui_cache_json gpu.json .encoder)")")
    lines+=("$(ui_kv_line "Decoder" "$(ui_cache_json gpu.json .decoder)")")

    ui_draw_subscreen "GPU - Utilization" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_memory() {
    local lines=()
    lines+=("$(ui_section_header "GPU Memory")")
    local mem
    mem=$(ui_cache_json gpu.json .memory)
    lines+=("$(ui_kv_line "Usage" "${mem}")")

    if command -v nvidia-smi >/dev/null 2>&1; then
        lines+=("")
        nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv 2>/dev/null | while IFS= read -r line; do
            lines+=("${line}")
        done
    fi

    ui_draw_subscreen "GPU - Memory" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_temp_power() {
    local lines=()
    lines+=("$(ui_section_header "Temperature & Power")")
    lines+=("$(ui_kv_line "Temperature" "$(ui_cache_json gpu.json .temperature)")")
    lines+=("$(ui_kv_line "Power" "$(ui_cache_json gpu.json .power)")")

    if command -v nvidia-smi >/dev/null 2>&1; then
        lines+=("")
        nvidia-smi --query-gpu=temperature.gpu,fan.speed,power.draw,power.limit --format=csv 2>/dev/null | while IFS= read -r line; do
            lines+=("${line}")
        done
    fi

    ui_draw_subscreen "GPU - Temperature & Power" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_encoder() {
    local lines=()
    lines+=("$(ui_section_header "Encoder / Decoder")")
    lines+=("$(ui_kv_line "Encoder" "$(ui_cache_json gpu.json .encoder)")")
    lines+=("$(ui_kv_line "Decoder" "$(ui_cache_json gpu.json .decoder)")")

    ui_draw_subscreen "GPU - Encoder/Decoder" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_processes() {
    local lines=()
    lines+=("$(ui_section_header "GPU Processes")")

    local procs
    procs=$(ui_cache_json gpu.json .processes_raw)
    if [[ -n "${procs}" ]]; then
        lines+=("$(ui_color "${COLOR_LABEL}" "PID  Process  Memory")")
        while IFS= read -r line; do
            [[ -n "${line}" ]] && lines+=("${line}")
        done <<< "${procs}"
    else
        if command -v nvidia-smi >/dev/null 2>&1; then
            nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv 2>/dev/null | while IFS= read -r line; do
                lines+=("${line}")
            done
        else
            lines+=("$(ui_color "${COLOR_DIM}" "No GPU processes")")
        fi
    fi

    ui_draw_subscreen "GPU - Processes" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_show_full_query() {
    local lines=()
    lines+=("$(ui_section_header "nvidia-smi -q (cached)")")

    local query
    query=$(ui_cache_json gpu.json .nvidia_smi_q)
    local offset=0
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 90)")
    done <<< "${query}"

    while true; do
        ui_draw_scrollable_subscreen "GPU - nvidia-smi -q" "${offset}" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((offset > 0)) && ((offset--)) || true ;;
            $'\x1b[B'|j|J) ((offset < ${#lines[@]} - 1)) && ((offset++)) || true ;;
            b|B|$'\x1b') return ;;
            r|R)
                if command -v nvidia-smi >/dev/null 2>&1; then
                    query=$(ui_run_timeout 15 nvidia-smi -q 2>/dev/null | head -200)
                    lines=()
                    lines+=("$(ui_section_header "nvidia-smi -q (live)")")
                    while IFS= read -r line; do
                        lines+=("$(ui_truncate "${line}" 90)")
                    done <<< "${query}"
                fi
                ;;
        esac
    done
}

gpu_maintenance_menu() {
    local items=(
        "Restart Persistence Daemon"
        "Reload NVIDIA Modules"
        "Reconfigure Container Toolkit"
        "Verify Docker GPU"
        "DKMS Status"
        "Driver Rebuild Helper"
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
        ui_draw_subscreen "${draw_mode}" "GPU - Maintenance" "${lines[@]}"
        ui_read_key >/dev/null
        draw_mode="nav"
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            b|B|$'\x1b') return ;;
            $'\r'|$'\n')
                draw_mode="full"
                case "${index}" in
                    0) gpu_restart_persistence ;;
                    1) gpu_reload_modules ;;
                    2) gpu_reconfigure_toolkit ;;
                    3) gpu_verify_docker ;;
                    4) gpu_dkms_status ;;
                    5) gpu_driver_rebuild ;;
                    6) return ;;
                esac
                ;;
        esac
    done
}

gpu_restart_persistence() {
    if ui_confirm "Restart NVIDIA persistence daemon?"; then
        systemctl restart nvidia-persistenced 2>/dev/null || nvidia-persistenced --persistence-mode 2>/dev/null || true
        ui_message "GPU" "Persistence daemon restart attempted"
    fi
}

gpu_reload_modules() {
    if ui_confirm "Reload NVIDIA kernel modules? This may disrupt GPU workloads."; then
        ui_message "GPU" "Reloading modules..."
        modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
        modprobe nvidia nvidia_modeset nvidia_drm nvidia_uvm 2>/dev/null || true
        ui_message "GPU" "Module reload attempted"
    fi
}

gpu_reconfigure_toolkit() {
    if ui_confirm "Reconfigure NVIDIA Container Toolkit?"; then
        if command -v nvidia-ctk >/dev/null 2>&1; then
            nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
            systemctl restart docker 2>/dev/null || true
            ui_message "GPU" "Container toolkit reconfigured"
        else
            ui_message "GPU" "nvidia-ctk not found"
        fi
    fi
}

gpu_verify_docker() {
    local lines=()
    lines+=("$(ui_section_header "Docker GPU Verification")")
    if ui_run_timeout 60 docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi 2>&1 | head -15 | while IFS= read -r line; do
        lines+=("${line}")
    done; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ GPU test container succeeded")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU test failed or timed out")")
    fi
    ui_draw_subscreen "GPU - Docker Verify" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_dkms_status() {
    local lines=()
    lines+=("$(ui_section_header "DKMS Status")")
    if command -v dkms >/dev/null 2>&1; then
        dkms status 2>/dev/null | while IFS= read -r line; do
            lines+=("${line}")
        done
    else
        lines+=("$(ui_color "${COLOR_DIM}" "DKMS not installed")")
    fi
    ui_draw_subscreen "GPU - DKMS" "${lines[@]}"
    ui_read_key >/dev/null
}

gpu_driver_rebuild() {
    local lines=()
    lines+=("$(ui_section_header "Driver Rebuild Helper")")
    lines+=("Run these commands as root if needed:")
    lines+=("")
    lines+=("  dkms autoinstall")
    lines+=("  update-initramfs -u")
    lines+=("  reboot")
    lines+=("")
    if ui_confirm "Run dkms autoinstall now?"; then
        dkms autoinstall 2>&1 | head -20 | while IFS= read -r line; do
            lines+=("${line}")
        done
        ui_message "GPU" "DKMS autoinstall completed"
    fi
    ui_draw_subscreen "GPU - Driver Rebuild" "${lines[@]}"
    ui_read_key >/dev/null
}
