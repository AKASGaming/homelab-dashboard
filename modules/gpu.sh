#!/usr/bin/env bash
# =============================================================================
# gpu.sh - NVIDIA GPU monitoring and maintenance module
# =============================================================================

[[ -n "${_GPU_SH_LOADED:-}" ]] && return 0
_GPU_SH_LOADED=1

gpu_is_error_state() {
    local status util
    status=$(ui_cache_json gpu.json .status)
    util=$(ui_cache_json gpu.json .utilization)
    [[ "${status}" == "error" ]] && return 0
    ui_gpu_is_error_value "${util}" && return 0
    return 1
}

gpu_append_recovery_guide() {
    local -n _out_lines=$1
    _out_lines+=("")
    _out_lines+=("$(ui_color "${COLOR_STATUS_WARN}" "update-dashboard does NOT update NVIDIA drivers.")")
    _out_lines+=("$(ui_color "${COLOR_DIM}" "After a kernel or system update, run Maintenance in this order:")")
    _out_lines+=("  1) DKMS Status — confirm nvidia module matches kernel $(uname -r)")
    _out_lines+=("  2) Driver Rebuild Helper — runs dkms autoinstall + initramfs")
    _out_lines+=("  3) Reboot the server")
    _out_lines+=("  4) Reload NVIDIA Modules — if GPU still errors after reboot")
    _out_lines+=("  5) Verify Docker GPU — if you use GPU containers")
    _out_lines+=("  6) Reconfigure Container Toolkit — if Docker verify fails")
}

gpu_show_error_context() {
    local title="$1"
    local lines=()
    local err_msg

    lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU driver not responding")")
    err_msg=$(ui_cache_json gpu.json .error_message)
    [[ -n "${err_msg}" ]] && lines+=("$(ui_color "${COLOR_DIM}" "${err_msg}")")
    lines+=("$(ui_color "${COLOR_DIM}" "nvidia-smi cannot read GPU metrics until drivers are rebuilt.")")
    gpu_append_recovery_guide lines
    ui_info_screen "${title}" "${lines[@]}"
}

gpu_capture_command_lines() {
    local -n _out_lines=$1
    local output="$2"
    if [[ -z "${output}" ]]; then
        return 1
    fi
    while IFS= read -r line; do
        [[ -n "${line}" ]] && _out_lines+=("$(ui_truncate "${line}" 100)")
    done <<< "${output}"
    return 0
}

gpu_show_progress() {
    local title="$1"
    local message="$2"

    ui_update_size
    ui_clear
    ui_draw_box_top "${UI_COLS}"
    ui_draw_box_line "${UI_COLS}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((UI_COLS - 4)))"
    ui_draw_separator "${UI_COLS}"
    ui_draw_box_line "${UI_COLS}" ""
    ui_draw_box_line "${UI_COLS}" "$(ui_center "${message}" $((UI_COLS - 4)))"
    ui_draw_box_line "${UI_COLS}" ""
    ui_draw_separator "${UI_COLS}"
    ui_draw_box_bottom "${UI_COLS}"
}

gpu_refresh_cache() {
    if [[ -x "${INSTALL_DIR}/modules/cache-daemon.sh" ]]; then
        "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 || true
    fi
}

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

    while true; do
        ui_numbered_menu "GPU" "${items[@]}"
        case "${UI_MENU_RESULT}" in
            back) return 0 ;;
            refresh) continue ;;
            quit) UI_RUNNING=0; return 0 ;;
            select)
                case "${UI_MENU_INDEX}" in
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
    local available status util
    available=$(ui_cache_json gpu.json .available)
    status=$(ui_cache_json gpu.json .status)
    util=$(ui_cache_json gpu.json .utilization)

    lines+=("$(ui_section_header "GPU Overview")")
    if [[ "${status}" == "error" ]] || ui_gpu_is_error_value "${util}"; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU error")")
        lines+=("")
        local err_msg
        err_msg=$(ui_cache_json gpu.json .error_message)
        [[ -n "${err_msg}" ]] && lines+=("$(ui_color "${COLOR_DIM}" "${err_msg}")")
        lines+=("$(ui_color "${COLOR_DIM}" "nvidia-smi cannot communicate with the driver.")")
        lines+=("$(ui_color "${COLOR_DIM}" "This is common after kernel or system updates.")")
        gpu_append_recovery_guide lines
    elif [[ "${available}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ NVIDIA GPU detected")")
        lines+=("")
        lines+=("$(ui_kv_line "GPU" "$(ui_cache_json gpu.json .gpu_name)")")
        lines+=("$(ui_kv_line "Driver" "$(ui_cache_json gpu.json .driver)")")
        lines+=("$(ui_kv_line "Utilization" "$(ui_cache_json gpu.json .utilization)%")")
        lines+=("$(ui_progress_bar "$(ui_cache_json gpu.json .utilization)" 25)")
        lines+=("$(ui_kv_line "Temperature" "$(ui_cache_json gpu.json .temperature)")")
        lines+=("$(ui_kv_line "Power" "$(ui_cache_json gpu.json .power) W")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU not available")")
        lines+=("")
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "Open Maintenance to run GPU checks and updates.")")
    fi

    ui_info_screen "GPU - Overview" "${lines[@]}"
}

gpu_show_utilization() {
    gpu_is_error_state && { gpu_show_error_context "GPU - Utilization"; return; }
    local lines=()
    lines+=("$(ui_section_header "GPU Utilization")")
    lines+=("$(ui_kv_line "GPU" "$(ui_cache_json gpu.json .utilization)%")")
    lines+=("$(ui_progress_bar "$(ui_cache_json gpu.json .utilization)" 40)")
    lines+=("")
    lines+=("$(ui_kv_line "Encoder" "$(ui_cache_json gpu.json .encoder)")")
    lines+=("$(ui_kv_line "Decoder" "$(ui_cache_json gpu.json .decoder)")")

    ui_info_screen "GPU - Utilization" "${lines[@]}"
}

gpu_show_memory() {
    gpu_is_error_state && { gpu_show_error_context "GPU - Memory"; return; }
    local lines=()
    lines+=("$(ui_section_header "GPU Memory")")
    local mem
    mem=$(ui_cache_json gpu.json .memory)
    lines+=("$(ui_kv_line "Usage" "${mem}")")

    if command -v nvidia-smi >/dev/null 2>&1; then
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv 2>/dev/null || true)
        if [[ -n "${smi_out}" ]]; then
            lines+=("")
            gpu_capture_command_lines lines "${smi_out}" || lines+=("$(ui_color "${COLOR_DIM}" "No memory data returned")")
        fi
    fi

    ui_info_screen "GPU - Memory" "${lines[@]}"
}

gpu_show_temp_power() {
    gpu_is_error_state && { gpu_show_error_context "GPU - Temperature & Power"; return; }
    local lines=()
    lines+=("$(ui_section_header "Temperature & Power")")
    lines+=("$(ui_kv_line "Temperature" "$(ui_cache_json gpu.json .temperature)")")
    lines+=("$(ui_kv_line "Power" "$(ui_cache_json gpu.json .power)")")

    if command -v nvidia-smi >/dev/null 2>&1; then
        local smi_out
        smi_out=$(nvidia-smi --query-gpu=temperature.gpu,fan.speed,power.draw,power.limit --format=csv 2>/dev/null || true)
        if [[ -n "${smi_out}" ]]; then
            lines+=("")
            gpu_capture_command_lines lines "${smi_out}" || lines+=("$(ui_color "${COLOR_DIM}" "No sensor data returned")")
        fi
    fi

    ui_info_screen "GPU - Temperature & Power" "${lines[@]}"
}

gpu_show_encoder() {
    gpu_is_error_state && { gpu_show_error_context "GPU - Encoder/Decoder"; return; }
    local lines=()
    lines+=("$(ui_section_header "Encoder / Decoder")")
    lines+=("$(ui_kv_line "Encoder" "$(ui_cache_json gpu.json .encoder)")")
    lines+=("$(ui_kv_line "Decoder" "$(ui_cache_json gpu.json .decoder)")")

    ui_info_screen "GPU - Encoder/Decoder" "${lines[@]}"
}

gpu_show_processes() {
    gpu_is_error_state && { gpu_show_error_context "GPU - Processes"; return; }
    local lines=()
    lines+=("$(ui_section_header "GPU Processes")")

    local procs
    procs=$(ui_cache_json gpu.json .processes_raw)
    if [[ -n "${procs}" ]]; then
        lines+=("$(ui_color "${COLOR_LABEL}" "PID  Process  Memory")")
        gpu_capture_command_lines lines "${procs}"
    elif command -v nvidia-smi >/dev/null 2>&1; then
        local smi_out
        smi_out=$(nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv 2>/dev/null || true)
        if [[ -n "${smi_out}" ]]; then
            gpu_capture_command_lines lines "${smi_out}"
        else
            lines+=("$(ui_color "${COLOR_DIM}" "No GPU processes")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No GPU processes")")
    fi

    ui_info_screen "GPU - Processes" "${lines[@]}"
}

gpu_show_full_query() {
    local lines=()
    lines+=("$(ui_section_header "nvidia-smi -q (cached)")")

    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ Cached query empty — driver not responding")")
        gpu_append_recovery_guide lines
        ui_info_screen "GPU - nvidia-smi -q" "${lines[@]}"
        return
    fi

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
            $'\r'|$'\n'|b|B|$'\x1b'|q|Q) return ;;
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
        "Recovery Guide"
        "Restart Persistence Daemon"
        "Reload NVIDIA Modules"
        "Reconfigure Container Toolkit"
        "Verify Docker GPU"
        "DKMS Status"
        "Driver Rebuild Helper"
        "Back"
    )

    while true; do
        ui_numbered_menu "GPU - Maintenance" "${items[@]}"
        case "${UI_MENU_RESULT}" in
            back) return ;;
            refresh) continue ;;
            quit) UI_RUNNING=0; return ;;
            select)
                case "${UI_MENU_INDEX}" in
                    0) gpu_show_recovery_guide ;;
                    1) gpu_restart_persistence ;;
                    2) gpu_reload_modules ;;
                    3) gpu_reconfigure_toolkit ;;
                    4) gpu_verify_docker ;;
                    5) gpu_dkms_status ;;
                    6) gpu_driver_rebuild ;;
                    7) return ;;
                esac
                ;;
        esac
    done
}

gpu_show_recovery_guide() {
    local lines=()
    lines+=("$(ui_section_header "GPU Driver Recovery Guide")")
    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU is currently in an error state")")
        local err_msg
        err_msg=$(ui_cache_json gpu.json .error_message)
        [[ -n "${err_msg}" ]] && lines+=("$(ui_color "${COLOR_DIM}" "${err_msg}")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ GPU responding — use this guide after kernel updates")")
    fi
    lines+=("")
    lines+=("$(ui_color "${COLOR_DIM}" "Updating this dashboard does not rebuild NVIDIA drivers.")")
    gpu_append_recovery_guide lines
    ui_info_screen "GPU - Recovery Guide" "${lines[@]}"
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
    local docker_out

    lines+=("$(ui_section_header "Docker GPU Verification")")
    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! GPU driver error — Docker GPU test will likely fail")")
        lines+=("$(ui_color "${COLOR_DIM}" "Rebuild drivers first (Recovery Guide), reboot, then retry.")")
        lines+=("")
    fi

    docker_out=$(ui_run_timeout 60 docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi 2>&1 | head -15 || true)
    if [[ -n "${docker_out}" ]]; then
        gpu_capture_command_lines lines "${docker_out}"
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No output from test container")")
    fi

    if echo "${docker_out}" | grep -qiE 'driver|nvidia-smi|cuda'; then
        if echo "${docker_out}" | grep -qiE 'failed|error|couldn|not found'; then
            lines+=("")
            lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU test failed")")
            gpu_append_recovery_guide lines
        else
            lines+=("")
            lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ GPU test container succeeded")")
        fi
    else
        lines+=("")
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU test failed or timed out")")
        if gpu_is_error_state; then
            gpu_append_recovery_guide lines
        fi
    fi

    ui_info_screen "GPU - Docker Verify" "${lines[@]}"
}

gpu_dkms_status() {
    local lines=()
    local dkms_out kernel

    lines+=("$(ui_section_header "DKMS Status")")
    kernel=$(uname -r)
    lines+=("$(ui_kv_line "Running kernel" "${kernel}")")
    lines+=("")

    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU driver not responding")")
        lines+=("$(ui_color "${COLOR_DIM}" "DKMS output below still applies — nvidia should show 'installed' for ${kernel}.")")
        lines+=("")
    fi

    if ! command -v dkms >/dev/null 2>&1; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "DKMS is not installed")")
        lines+=("$(ui_color "${COLOR_DIM}" "Install the NVIDIA driver package that provides DKMS support.")")
        gpu_append_recovery_guide lines
        ui_info_screen "GPU - DKMS" "${lines[@]}"
        return
    fi

    ui_update_size
    ui_clear
    ui_draw_box_top "${UI_COLS}"
    ui_draw_box_line "${UI_COLS}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "GPU - DKMS")" $((UI_COLS - 4)))"
    ui_draw_separator "${UI_COLS}"
    ui_draw_box_line "${UI_COLS}" ""
    ui_draw_box_line "${UI_COLS}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Running dkms status (may take up to 30s)...")" $((UI_COLS - 4)))"
    ui_draw_box_line "${UI_COLS}" ""
    ui_draw_separator "${UI_COLS}"
    ui_draw_box_bottom "${UI_COLS}"

    dkms_out=$(ui_run_timeout 30 dkms status 2>&1 || echo "dkms status failed or timed out after 30s")

    lines=()
    lines+=("$(ui_section_header "DKMS Status")")
    lines+=("$(ui_kv_line "Running kernel" "${kernel}")")
    lines+=("")

    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ GPU driver not responding")")
        lines+=("")
    fi

    if [[ -z "${dkms_out}" ]] || [[ "${dkms_out}" == "dkms status failed or timed out after 30s" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "DKMS returned no output")")
        lines+=("$(ui_color "${COLOR_DIM}" "${dkms_out:-No modules registered or command produced no output}")")
    elif ! gpu_capture_command_lines lines "${dkms_out}"; then
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "DKMS returned no module lines")")
    fi

    if echo "${dkms_out}" | grep -qi nvidia; then
        if echo "${dkms_out}" | grep -q "${kernel}"; then
            lines+=("")
            lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ NVIDIA DKMS entry references current kernel")")
        else
            lines+=("")
            lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! NVIDIA module may not be built for ${kernel}")")
            lines+=("$(ui_color "${COLOR_DIM}" "Run Driver Rebuild Helper, then reboot.")")
        fi
    else
        lines+=("")
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! No NVIDIA module found in DKMS")")
        lines+=("$(ui_color "${COLOR_DIM}" "Driver may not be installed or may not use DKMS.")")
    fi

    if gpu_is_error_state; then
        gpu_append_recovery_guide lines
    fi

    ui_info_screen "GPU - DKMS" "${lines[@]}"
}

gpu_driver_rebuild() {
    local lines=() rebuild_out initramfs_out smi_after kernel confirm
    local rebuild_ok=0 smi_ok=0

    kernel=$(uname -r)

    lines+=("$(ui_section_header "Driver Rebuild Helper")")
    lines+=("$(ui_kv_line "Target kernel" "${kernel}")")
    lines+=("")
    lines+=("$(ui_color "${COLOR_LABEL}" "This will run:")")
    lines+=("  1) dkms autoinstall")
    lines+=("  2) update-initramfs -u")
    lines+=("  3) Reload NVIDIA kernel modules")
    lines+=("  4) Refresh GPU cache + test nvidia-smi")
    lines+=("")
    if gpu_is_error_state; then
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "GPU is errored now — that is normal before rebuild.")")
        lines+=("$(ui_color "${COLOR_DIM}" "The dashboard may still show 'error' until you reboot.")")
    fi
    lines+=("")
    lines+=("$(ui_color "${COLOR_DIM}" "Type y and press Enter to start, or n to cancel.")")

    ui_info_screen "GPU - Driver Rebuild" "${lines[@]}"

    if ! command -v dkms >/dev/null 2>&1; then
        lines=()
        lines+=("$(ui_section_header "Driver Rebuild Failed")")
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "DKMS is not installed")")
        lines+=("$(ui_color "${COLOR_DIM}" "Install the NVIDIA driver package that provides DKMS, then retry.")")
        ui_info_screen "GPU - Driver Rebuild" "${lines[@]}"
        return
    fi

    ui_prompt_choice "Start rebuild now? (y/n): " confirm
    case "${confirm}" in
        y|Y|yes|Yes) ;;
        *) return ;;
    esac

    gpu_show_progress "GPU - Driver Rebuild" "Step 1/4: Running dkms autoinstall (up to 5 minutes)..."
    rebuild_out=$(ui_run_timeout 300 dkms autoinstall 2>&1 || echo "[exit $?] dkms autoinstall failed or timed out")

    gpu_show_progress "GPU - Driver Rebuild" "Step 2/4: Updating initramfs..."
    if command -v update-initramfs >/dev/null 2>&1; then
        initramfs_out=$(update-initramfs -u 2>&1 || echo "[exit $?] update-initramfs failed")
    else
        initramfs_out="update-initramfs not found — skip manually if needed"
    fi

    gpu_show_progress "GPU - Driver Rebuild" "Step 3/4: Reloading NVIDIA kernel modules..."
    modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    modprobe nvidia nvidia_modeset nvidia_drm nvidia_uvm 2>/dev/null || true

    gpu_show_progress "GPU - Driver Rebuild" "Step 4/4: Refreshing GPU status..."
    gpu_refresh_cache

    smi_after=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>&1 | head -1 || true)

    lines=()
    lines+=("$(ui_section_header "Driver Rebuild Results")")
    lines+=("$(ui_kv_line "Kernel" "${kernel}")")
    lines+=("")

    lines+=("$(ui_color "${COLOR_LABEL}" "dkms autoinstall output:")")
    if gpu_capture_command_lines lines "${rebuild_out}"; then
        if echo "${rebuild_out}" | grep -qiE 'built|install|already|done'; then
            rebuild_ok=1
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No output captured")")
    fi

    lines+=("")
    lines+=("$(ui_color "${COLOR_LABEL}" "update-initramfs output:")")
    gpu_capture_command_lines lines "${initramfs_out}" || lines+=("$(ui_color "${COLOR_DIM}" "No output captured")")

    lines+=("")
    if (( rebuild_ok )); then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ DKMS autoinstall appears to have completed")")
    elif echo "${rebuild_out}" | grep -qiE 'error|failed|cannot'; then
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ DKMS autoinstall reported errors — review output above")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! DKMS finished — review output above to confirm success")")
    fi

    lines+=("")
    lines+=("$(ui_color "${COLOR_LABEL}" "nvidia-smi test:")")
    lines+=("  $(ui_truncate "${smi_after:-no response}" 90)")
    if ! ui_gpu_is_error_value "${smi_after}"; then
        smi_ok=1
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ GPU driver responding after rebuild")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_WARN}" "! nvidia-smi still failing — reboot is usually required")")
        lines+=("$(ui_color "${COLOR_DIM}" "Run: reboot")")
        lines+=("$(ui_color "${COLOR_DIM}" "After reboot: GPU > Overview, or press R on main menu")")
    fi

    if (( ! smi_ok )); then
        lines+=("")
        lines+=("$(ui_color "${COLOR_DIM}" "The dashboard GPU error badge is expected until reboot.")")
    fi

    ui_info_screen "GPU - Driver Rebuild" "${lines[@]}"
}
