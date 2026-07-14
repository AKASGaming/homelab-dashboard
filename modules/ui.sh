#!/usr/bin/env bash
# =============================================================================
# ui.sh - TheaterNAS Control Center UI Framework
# ANSI-based terminal UI: layout, themes, input, rendering helpers.
# =============================================================================

# Prevent double-sourcing
[[ -n "${_UI_SH_LOADED:-}" ]] && return 0
_UI_SH_LOADED=1

# --- Global UI state ---
UI_ROWS=24
UI_COLS=80
UI_MENU_INDEX=0
UI_MENU_ITEMS=()
UI_LAST_KEY=""
UI_RUNNING=1
UI_SNAP_LOADED=0
UI_SNAP_CPU=""
UI_SNAP_RAM=""
UI_SNAP_GPU=""
UI_SNAP_GPU_STATUS=""
UI_SNAP_GPU_HELP=""
UI_SNAP_DOCKER=""
UI_SNAP_PIHOLE=""
UI_SNAP_PLEX=""
UI_SNAP_HOSTNAME=""
UI_SNAP_UPTIME=""
UI_SNAP_CONTAINERS=""
UI_SNAP_GPU_TEMP=""
UI_SNAP_LAN_IP=""
UI_SNAP_TAILSCALE_IP=""
UI_SNAP_ROOT_USAGE=""
UI_RESIZE_PENDING=0
UI_CLEANED_UP=0
UI_MENU_RESULT=""

# =============================================================================
# Configuration and theme loading
# =============================================================================

ui_load_config() {
    local config_file="${1:-${INSTALL_DIR}/config/config.conf}"
    local saved_install_dir="${INSTALL_DIR}"
    if [[ -f "${config_file}" ]]; then
        # shellcheck source=/dev/null
        source "${config_file}"
    fi
    INSTALL_DIR="${saved_install_dir:-/opt/homelab-dashboard}"
    CACHE_DIR="${CACHE_DIR:-${INSTALL_DIR}/cache}"
    mkdir -p "${CACHE_DIR}" 2>/dev/null || true
}

ui_load_theme() {
    local theme="${THEME:-default}"
    local theme_file="${INSTALL_DIR}/themes/${theme}.theme"
    if [[ ! -f "${theme_file}" ]]; then
        theme_file="${INSTALL_DIR}/themes/default.theme"
    fi
    if [[ -f "${theme_file}" ]]; then
        # shellcheck source=/dev/null
        source "${theme_file}"
    fi
}

ui_get_version() {
    local version_file="${INSTALL_DIR}/VERSION"
    if [[ -f "${version_file}" ]]; then
        tr -d '[:space:]' < "${version_file}"
    else
        echo "unknown"
    fi
}

# =============================================================================
# Terminal control
# =============================================================================

ui_update_size() {
    if command -v tput >/dev/null 2>&1; then
        UI_ROWS=$(tput lines 2>/dev/null || echo 24)
        UI_COLS=$(tput cols 2>/dev/null || echo 80)
    else
        UI_ROWS=24
        UI_COLS=80
    fi
    (( UI_ROWS < 8 )) && UI_ROWS=8
    (( UI_COLS < 40 )) && UI_COLS=40
}

ui_layout_widths() {
    local width="${UI_COLS}"
    if (( width < 70 )); then
        UI_LAYOUT_MENU_W=$((width * 2 / 5))
    else
        UI_LAYOUT_MENU_W=$((width / 3))
    fi
    if (( UI_LAYOUT_MENU_W < 18 )); then UI_LAYOUT_MENU_W=18; fi
    UI_LAYOUT_DETAIL_W=$((width - UI_LAYOUT_MENU_W - 6))
    if (( UI_LAYOUT_DETAIL_W < 12 )); then UI_LAYOUT_DETAIL_W=12; fi
}

ui_install_resize_trap() {
    trap 'UI_RESIZE_PENDING=1' WINCH
}

ui_hide_cursor() {
    printf '\033[?25l'
}

ui_show_cursor() {
    printf '\033[?25h'
}

ui_clear() {
    printf '\033[2J\033[H'
}

ui_cursor_home() {
    printf '\033[H'
}

ui_clear_line() {
    printf '\033[2K'
}

ui_reset_attrs() {
    printf '\033[0m'
}

ui_save_screen() {
    if command -v tput >/dev/null 2>&1; then
        tput smcup 2>/dev/null || true
    fi
    ui_hide_cursor
}

ui_restore_screen() {
    ui_show_cursor
    ui_reset_attrs
    if command -v tput >/dev/null 2>&1; then
        tput rmcup 2>/dev/null || true
    fi
}

ui_cleanup() {
    if (( UI_CLEANED_UP )); then
        return 0
    fi
    UI_CLEANED_UP=1
    ui_restore_screen
    ui_tty_restore
    printf '\n'
}

ui_tty_init() {
    if [[ -t 0 ]]; then
        # Save current stty settings once for restore
        UI_STTY_SAVED=$(stty -g 2>/dev/null || echo "")
        stty -echo -icanon min 1 time 0 2>/dev/null || true
    fi
}

ui_tty_restore() {
    if [[ -n "${UI_STTY_SAVED:-}" ]]; then
        stty "${UI_STTY_SAVED}" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
}

ui_drain_input() {
    while IFS= read -rsn1 -t 0.01 _ 2>/dev/null; do
        :
    done
}

# =============================================================================
# Color helpers
# =============================================================================

ui_fg() {
    printf '\033[38;5;%sm' "$1"
}

ui_bg() {
    printf '\033[48;5;%sm' "$1"
}

ui_bold() {
    printf '\033[1m'
}

ui_dim() {
    printf '\033[2m'
}

ui_color() {
    local code="$1"
    shift
    ui_fg "${code}"
    printf '%s' "$*"
    ui_reset_attrs
}

ui_status_icon() {
    local status="$1"
    case "${status}" in
        ok|up|running|healthy|true|1)
            ui_color "${COLOR_STATUS_OK}" "✓"
            ;;
        warn|degraded|partial)
            ui_color "${COLOR_STATUS_WARN}" "!"
            ;;
        *)
            ui_color "${COLOR_STATUS_ERR}" "✗"
            ;;
    esac
}

# =============================================================================
# Text layout helpers
# =============================================================================

ui_strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g' <<< "$1"
}

ui_strlen() {
    local s="$1"
    local stripped
    stripped=$(ui_strip_ansi "${s}")
    printf '%s' "${#stripped}"
}

ui_truncate() {
    local text="$1"
    local max="$2"
    local stripped len
    stripped=$(ui_strip_ansi "${text}")
    len=${#stripped}
    if (( len <= max )); then
        printf '%s' "${text}"
    else
        printf '%s' "${stripped:0:max-1}…"
    fi
}

ui_pad_right() {
    local text="$1"
    local width="$2"
    local stripped len pad
    stripped=$(ui_strip_ansi "${text}")
    len=${#stripped}
    if (( len >= width )); then
        ui_truncate "${text}" "${width}"
    else
        printf '%s%*s' "${text}" $((width - len)) ''
    fi
}

ui_center() {
    local text="$1"
    local width="${2:-${UI_COLS}}"
    local stripped len pad
    stripped=$(ui_strip_ansi "${text}")
    len=${#stripped}
    pad=$(( (width - len) / 2 ))
    if (( pad < 0 )); then pad=0; fi
    printf '%*s%s' "${pad}" '' "${text}"
}

ui_repeat_char() {
    local char="$1"
    local count="$2"
    printf '%*s' "${count}" '' | tr ' ' "${char}"
}

# =============================================================================
# Drawing primitives
# =============================================================================

ui_draw_hline() {
    local width="$1"
    local char="${2:-─}"
    ui_color "${COLOR_BORDER}" "$(ui_repeat_char "${char}" "${width}")"
    ui_reset_attrs
}

ui_draw_box_top() {
    local width="$1"
    ui_color "${COLOR_BORDER}" "┌"
    ui_draw_hline $((width - 2)) "─"
    ui_color "${COLOR_BORDER}" "┐"
    printf '\n'
    ui_reset_attrs
}

ui_draw_box_bottom() {
    local width="$1"
    ui_color "${COLOR_BORDER}" "└"
    ui_draw_hline $((width - 2)) "─"
    ui_color "${COLOR_BORDER}" "┘"
    printf '\n'
    ui_reset_attrs
}

ui_draw_box_line() {
    local width="$1"
    local content="$2"
    local inner=$((width - 4))
    ui_color "${COLOR_BORDER}" "│ "
    ui_reset_attrs
    ui_pad_right "${content}" "${inner}"
    ui_color "${COLOR_BORDER}" " │"
    printf '\n'
    ui_reset_attrs
}

ui_draw_separator() {
    local width="$1"
    ui_color "${COLOR_BORDER}" "├"
    ui_draw_hline $((width - 2)) "─"
    ui_color "${COLOR_BORDER}" "┤"
    printf '\n'
    ui_reset_attrs
}

ui_sanitize_choice() {
    local value="$1"
    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

ui_prompt_choice() {
    local prompt="${1:-Choose an option: }"
    local __result_var="$2"

    ui_tty_restore
    printf '\033[%d;1H' "${UI_ROWS}"
    printf '\033[2K'
    ui_color "${COLOR_LABEL}" "${prompt}"
    ui_reset_attrs
    read -r "${__result_var}"
    printf -v "${__result_var}" '%s' "$(ui_sanitize_choice "${!__result_var}")"
    ui_tty_init
}

# =============================================================================
# Cache helpers (UI never blocks on slow commands)
# =============================================================================

ui_cache_read() {
    local file="$1"
    local fallback="${2:-}"
    if [[ -f "${CACHE_DIR}/${file}" ]]; then
        cat "${CACHE_DIR}/${file}"
    else
        printf '%s' "${fallback}"
    fi
}

ui_cache_json() {
    local file="$1"
    local key="${2:-}"
    local fallback="${3:-N/A}"
    local path="${CACHE_DIR}/${file}"
    if [[ -f "${path}" ]] && command -v jq >/dev/null 2>&1; then
        if [[ -n "${key}" ]]; then
            jq -r "${key} // \"${fallback}\"" "${path}" 2>/dev/null || printf '%s' "${fallback}"
        else
            cat "${path}"
        fi
    else
        printf '%s' "${fallback}"
    fi
}

ui_cache_age() {
    local file="$1"
    local path="${CACHE_DIR}/${file}"
    if [[ -f "${path}" ]]; then
        local now mtime
        now=$(date +%s)
        mtime=$(stat -c %Y "${path}" 2>/dev/null || stat -f %m "${path}" 2>/dev/null || echo 0)
        echo $((now - mtime))
    else
        echo -1
    fi
}

ui_cache_stale_indicator() {
    local file="$1"
    local max_age="${2:-${CACHE_INTERVAL:-30}}"
    local age
    age=$(ui_cache_age "${file}")
    if (( age < 0 )); then
        ui_color "${COLOR_STATUS_ERR}" "[no cache]"
    elif (( age > max_age * 2 )); then
        ui_color "${COLOR_STATUS_WARN}" "[stale ${age}s]"
    fi
}

# =============================================================================
# GPU display helpers
# =============================================================================

ui_gpu_is_error_value() {
    local value="$1"
    [[ "${value}" == "error" ]] && return 0
    [[ -z "${value}" || "${value}" == "N/A" || "${value}" == "null" || "${value}" == "?" ]] && return 0
    echo "${value}" | grep -qiE 'nvidia|failed|error|couldn|communicat|driver|not find|unknown|make sure' && return 0
    echo "${value}" | grep -q '[[:space:]]' && return 0
    return 1
}

ui_gpu_sanitize_field() {
    local value="$1"
    if ui_gpu_is_error_value "${value}"; then
        printf 'error'
    else
        printf '%s' "${value}"
    fi
}

ui_gpu_status_display() {
    local util="$1"
    util=$(ui_gpu_sanitize_field "${util}")
    if [[ "${util}" == "error" ]]; then
        ui_color "${COLOR_STATUS_ERR}" "error"
    else
        ui_color "${COLOR_VALUE}" "${util}%"
    fi
}

ui_gpu_temp_display() {
    local temp="$1"
    temp=$(ui_gpu_sanitize_field "${temp}")
    if [[ "${temp}" == "error" ]]; then
        ui_color "${COLOR_STATUS_ERR}" "error"
    else
        ui_color "${COLOR_VALUE}" "${temp}"
    fi
}

ui_gpu_error_hint() {
    local hint="$1"
    [[ -z "${hint}" ]] && hint="Open GPU > Maintenance for driver checks and updates."
    ui_color "${COLOR_STATUS_WARN}" "${hint}"
}

# =============================================================================
# Header, status bar, footer
# =============================================================================

ui_build_status_line() {
    local cpu ram gpu docker_status pihole_status plex_status

    if (( UI_SNAP_LOADED )); then
        cpu="${UI_SNAP_CPU}"
        ram="${UI_SNAP_RAM}"
        gpu="${UI_SNAP_GPU}"
        docker_status="${UI_SNAP_DOCKER}"
        pihole_status="${UI_SNAP_PIHOLE}"
        plex_status="${UI_SNAP_PLEX}"
    else
        cpu=$(ui_cache_json "system.json" '.cpu_percent' "?")
        ram=$(ui_cache_json "system.json" '.ram_percent' "?")
        gpu=$(ui_gpu_sanitize_field "$(ui_cache_json "gpu.json" '.utilization' "?")")
        docker_status=$(ui_cache_json "docker.json" '.daemon_running' "false")
        pihole_status=$(ui_cache_json "media.json" '.pihole.running' "false")
        plex_status=$(ui_cache_json "media.json" '.plex.running' "false")
    fi

    local status_line=""
    status_line+=$(ui_color "${COLOR_LABEL}" "CPU ")
    status_line+=$(ui_color "${COLOR_VALUE}" "${cpu}% ")
    status_line+=$(ui_color "${COLOR_LABEL}" "RAM ")
    status_line+=$(ui_color "${COLOR_VALUE}" "${ram}% ")
    status_line+=$(ui_color "${COLOR_LABEL}" "GPU ")
    status_line+=$(ui_gpu_status_display "${gpu}")
    status_line+=" "
    status_line+=$(ui_color "${COLOR_LABEL}" "Docker ")
    status_line+=$(ui_status_icon "$([[ "${docker_status}" == "true" ]] && echo ok || echo err)")
    status_line+=" "
    status_line+=$(ui_color "${COLOR_LABEL}" "Pi-hole ")
    status_line+=$(ui_status_icon "$([[ "${pihole_status}" == "true" ]] && echo ok || echo err)")
    status_line+=" "
    status_line+=$(ui_color "${COLOR_LABEL}" "Plex ")
    status_line+=$(ui_status_icon "$([[ "${plex_status}" == "true" ]] && echo ok || echo err)")
    printf '%s' "${status_line}"
}

ui_main_snapshot_load() {
    UI_SNAP_CPU=$(ui_cache_json "system.json" '.cpu_percent' "?")
    UI_SNAP_RAM=$(ui_cache_json "system.json" '.ram_percent' "?")
    UI_SNAP_GPU_STATUS=$(ui_cache_json "gpu.json" '.status' "unknown")
    UI_SNAP_GPU=$(ui_gpu_sanitize_field "$(ui_cache_json "gpu.json" '.utilization' "?")")
    UI_SNAP_GPU_TEMP=$(ui_gpu_sanitize_field "$(ui_cache_json "gpu.json" '.temperature' "N/A")")
    UI_SNAP_GPU_HELP=$(ui_cache_json "gpu.json" '.help_hint' "GPU error — GPU > Maintenance > Recovery Guide")
    if [[ "${UI_SNAP_GPU}" == "error" ]]; then
        UI_SNAP_GPU_STATUS="error"
    fi
    UI_SNAP_DOCKER=$(ui_cache_json "docker.json" '.daemon_running' "false")
    UI_SNAP_PIHOLE=$(ui_cache_json "media.json" '.pihole.running' "false")
    UI_SNAP_PLEX=$(ui_cache_json "media.json" '.plex.running' "false")
    UI_SNAP_HOSTNAME=$(ui_cache_json "system.json" '.hostname' "unknown")
    UI_SNAP_UPTIME=$(ui_cache_json "system.json" '.uptime_human' "unknown")
    UI_SNAP_CONTAINERS=$(ui_cache_json "docker.json" '.container_count' "0")
    UI_SNAP_LAN_IP=$(ui_cache_json "network.json" '.lan_ip' "N/A")
    UI_SNAP_TAILSCALE_IP=$(ui_cache_json "tailscale.json" '.self_ip' "N/A")
    UI_SNAP_ROOT_USAGE=$(ui_cache_json "system.json" '.root_usage_percent' "N/A")
    UI_SNAP_LOADED=1
}

ui_draw_header() {
    local width="${UI_COLS}"
    local title="${BANNER_TITLE:-THEATERNAS CONTROL CENTER}"

    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_build_status_line)"
    ui_draw_separator "${width}"
}

ui_draw_footer() {
    local width="${UI_COLS}"
    local hints menu_max
    menu_max=${#UI_MENU_ITEMS[@]}
    hints=$(ui_color "${COLOR_DIM}" "1-${menu_max} Open")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "Q Quit")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "R Refresh")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "S Screensaver")

    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "${hints}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
}

# =============================================================================
# Menu rendering
# =============================================================================

ui_set_menu_items() {
    UI_MENU_ITEMS=("$@")
    if (( UI_MENU_INDEX >= ${#UI_MENU_ITEMS[@]} )); then
        UI_MENU_INDEX=0
    fi
}

ui_draw_split_menu() {
    local width="${UI_COLS}"
    ui_layout_widths
    local menu_width="${UI_LAYOUT_MENU_W}"
    local detail_width="${UI_LAYOUT_DETAIL_W}"
    local max_items=$((UI_ROWS - 8))
    local i start detail_lines

    # Left: menu items
    start=0
    if (( UI_MENU_INDEX >= max_items )); then
        start=$((UI_MENU_INDEX - max_items + 1))
    fi

    for ((i = 0; i < ${#UI_MENU_ITEMS[@]}; i++)); do
        if (( i < start || i >= start + max_items )); then
            continue
        fi
        local item="${UI_MENU_ITEMS[$i]}"
        local prefix="  "
        local color="${COLOR_MENU_INACTIVE}"
        if (( i == UI_MENU_INDEX )); then
            prefix="> "
            color="${COLOR_MENU_ACTIVE}"
        fi
        local line
        line=$(ui_color "${color}" "${prefix}${item}")
        ui_draw_box_line "${width}" "$(ui_pad_right "${line}" "${menu_width}")$(ui_render_detail_placeholder "${detail_width}")"
    done

    # Fill empty menu slots
    local shown=$(( ${#UI_MENU_ITEMS[@]} - start ))
    if (( shown > max_items )); then shown=${max_items}; fi
    for ((i = shown; i < max_items; i++)); do
        ui_draw_box_line "${width}" "$(ui_repeat_char ' ' "${menu_width}")$(ui_repeat_char ' ' "${detail_width}")"
    done
}

ui_render_detail_placeholder() {
    echo ""
}

# =============================================================================
# Detail panel for main dashboard
# =============================================================================

ui_draw_main_details() {
    local width="${UI_COLS}"
    ui_layout_widths
    local menu_width="${UI_LAYOUT_MENU_W}"
    local detail_width="${UI_LAYOUT_DETAIL_W}"

    local hostname uptime containers gpu_temp lan_ip tailscale_ip root_usage
    if (( UI_SNAP_LOADED )); then
        hostname="${UI_SNAP_HOSTNAME}"
        uptime="${UI_SNAP_UPTIME}"
        containers="${UI_SNAP_CONTAINERS}"
        gpu_temp="${UI_SNAP_GPU_TEMP}"
        lan_ip="${UI_SNAP_LAN_IP}"
        tailscale_ip="${UI_SNAP_TAILSCALE_IP}"
        root_usage="${UI_SNAP_ROOT_USAGE}"
    else
        hostname=$(ui_cache_json "system.json" '.hostname' "unknown")
        uptime=$(ui_cache_json "system.json" '.uptime_human' "unknown")
        containers=$(ui_cache_json "docker.json" '.container_count' "0")
        gpu_temp=$(ui_gpu_sanitize_field "$(ui_cache_json "gpu.json" '.temperature' "N/A")")
        lan_ip=$(ui_cache_json "network.json" '.lan_ip' "N/A")
        tailscale_ip=$(ui_cache_json "tailscale.json" '.self_ip' "N/A")
        root_usage=$(ui_cache_json "system.json" '.root_usage_percent' "N/A")
    fi

    local details=()
    details+=("$(ui_color "${COLOR_LABEL}" "Hostname: ")$(ui_color "${COLOR_VALUE}" "${hostname}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Uptime: ")$(ui_color "${COLOR_VALUE}" "${uptime}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Containers: ")$(ui_color "${COLOR_VALUE}" "${containers}")")
    if [[ "${gpu_temp}" == "error" ]]; then
        details+=("$(ui_color "${COLOR_LABEL}" "GPU Temp: ")$(ui_gpu_temp_display "${gpu_temp}")")
        local         gpu_hint="${UI_SNAP_GPU_HELP:-GPU error — GPU > Maintenance > Recovery Guide}"
        if (( ! UI_SNAP_LOADED )); then
            gpu_hint=$(ui_cache_json "gpu.json" '.help_hint' "GPU error — GPU > Maintenance > Recovery Guide")
        fi
        details+=("$(ui_gpu_error_hint "${gpu_hint}")")
    else
        details+=("$(ui_color "${COLOR_LABEL}" "GPU Temp: ")$(ui_gpu_temp_display "${gpu_temp}")")
    fi
    details+=("$(ui_color "${COLOR_LABEL}" "LAN: ")$(ui_color "${COLOR_VALUE}" "${lan_ip}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Tailscale: ")$(ui_color "${COLOR_VALUE}" "${tailscale_ip}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Root Usage: ")$(ui_color "${COLOR_VALUE}" "${root_usage}%")")

    local max_items=$((UI_ROWS - 8))
    local i start
    start=0
    if (( UI_MENU_INDEX >= max_items )); then
        start=$((UI_MENU_INDEX - max_items + 1))
    fi

    # Numbered menu (left) + frozen detail panel (right)
    local row=0
    for ((i = start; i < start + max_items && i < ${#UI_MENU_ITEMS[@]}; i++)); do
        local num=$((i + 1))
        local item="${UI_MENU_ITEMS[$i]}"
        local menu_part
        menu_part=$(ui_pad_right "$(ui_color "${COLOR_MENU_INACTIVE}" "  ${num}) ${item}")" "${menu_width}")
        local detail_part=""
        if (( row < ${#details[@]} )); then
            detail_part="${details[$row]}"
        fi
        detail_part=$(ui_pad_right "${detail_part}" "${detail_width}")
        ui_draw_box_line "${width}" "${menu_part}${detail_part}"
        ((row++))
    done

    for ((i = row; i < max_items; i++)); do
        local detail_part=""
        if (( i < ${#details[@]} )); then
            detail_part="${details[$i]}"
        fi
        ui_draw_box_line "${width}" "$(ui_repeat_char ' ' "${menu_width}")$(ui_pad_right "${detail_part}" "${detail_width}")"
    done
}

ui_draw_main_screen() {
    ui_update_size
    ui_clear
    ui_draw_header
    ui_draw_main_details
    ui_draw_footer
    UI_RESIZE_PENDING=0
}

# Process a key on the main dashboard. Prints: nav, open, quit, refresh, screensaver, none
ui_main_process_key() {
    case "${UI_LAST_KEY}" in
        $'\x1b[A'|k|K)
            if (( UI_MENU_INDEX > 0 )); then ((UI_MENU_INDEX--)); fi
            printf 'nav'
            ;;
        $'\x1b[B'|j|J)
            if (( UI_MENU_INDEX < ${#UI_MENU_ITEMS[@]} - 1 )); then ((UI_MENU_INDEX++)); fi
            printf 'nav'
            ;;
        q|Q)
            printf 'quit'
            ;;
        r|R)
            printf 'refresh'
            ;;
        s|S)
            printf 'screensaver'
            ;;
        $'\r'|$'\n')
            ui_drain_input
            printf 'open'
            ;;
        *)
            printf 'none'
            ;;
    esac
}

# =============================================================================
# Sub-screen layout (full module views)
# =============================================================================

ui_draw_subscreen() {
    local mode="full"
    local footer_hint=""
    if [[ "${1}" == "full" || "${1}" == "nav" ]]; then
        mode="$1"
        shift
    fi
    local title="$1"
    shift
    local lines=("$@")
    local width="${UI_COLS}"
    local max_lines=$((UI_ROWS - 6))
    local i

    ui_update_size
    max_lines=$((UI_ROWS - 6))
    if (( max_lines < 3 )); then max_lines=3; fi
    if [[ "${mode}" == "full" ]]; then
        ui_clear
    else
        ui_cursor_home
    fi
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"

    for ((i = 0; i < max_lines && i < ${#lines[@]}; i++)); do
        ui_draw_box_line "${width}" "${lines[$i]}"
    done
    for ((i = ${#lines[@]}; i < max_lines; i++)); do
        ui_draw_box_line "${width}" ""
    done

    ui_draw_separator "${width}"
    local footer_text
    if [[ -n "${footer_hint}" ]]; then
        footer_text="${footer_hint}"
    else
        footer_text="$(ui_color "${COLOR_DIM}" "Enter number below  B Back  Q Quit")"
    fi
    ui_draw_box_line "${width}" "$(ui_center "${footer_text}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
}

ui_draw_numbered_menu_screen() {
    local title="$1"
    shift
    local items=("$@")
    local lines=() i num
    local width="${UI_COLS}"
    local max_lines=$((UI_ROWS - 6))
    local footer_text

    ui_update_size
    max_lines=$((UI_ROWS - 6))
    if (( max_lines < 3 )); then max_lines=3; fi

    for ((i = 0; i < ${#items[@]}; i++)); do
        num=$((i + 1))
        lines+=("  ${num}) ${items[$i]}")
    done

    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"

    for ((i = 0; i < max_lines && i < ${#lines[@]}; i++)); do
        ui_draw_box_line "${width}" "${lines[$i]}"
    done
    if (( ${#lines[@]} > max_lines )); then
        ui_draw_box_line "${width}" "$(ui_color "${COLOR_DIM}" "  ... ${#items[@]} items — type number to select")"
        for ((i = ${#lines[@]} + 1; i < max_lines; i++)); do
            ui_draw_box_line "${width}" ""
        done
    else
        for ((i = ${#lines[@]}; i < max_lines; i++)); do
            ui_draw_box_line "${width}" ""
        done
    fi

    ui_draw_separator "${width}"
    footer_text="$(ui_color "${COLOR_DIM}" "1-${#items[@]} Select  B Back  Q Quit")"
    ui_draw_box_line "${width}" "$(ui_center "${footer_text}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
}

ui_info_screen() {
    local title="$1"
    shift
    local lines=("$@")
    local width="${UI_COLS}"
    local max_lines=$((UI_ROWS - 6))
    local i

    ui_update_size
    max_lines=$((UI_ROWS - 6))
    if (( max_lines < 3 )); then max_lines=3; fi

    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"

    for ((i = 0; i < max_lines && i < ${#lines[@]}; i++)); do
        ui_draw_box_line "${width}" "${lines[$i]}"
    done
    if (( ${#lines[@]} > max_lines )); then
        ui_draw_box_line "${width}" "$(ui_color "${COLOR_DIM}" "  ... ${#lines[@]} lines — resize terminal to see more")"
    fi
    for ((i = ${#lines[@]}; i < max_lines; i++)); do
        ui_draw_box_line "${width}" ""
    done

    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Press Enter to return")" $((width - 4)))"
    ui_draw_box_bottom "${width}"

    ui_tty_restore
    printf '\033[%d;1H' "${UI_ROWS}"
    printf '\033[2K'
    ui_color "${COLOR_DIM}" "Press Enter to return"
    ui_reset_attrs
    read -r _
    ui_tty_init
}

ui_numbered_menu() {
    local title="$1"
    shift
    local items=("$@")
    local choice

    while true; do
        if (( UI_RESIZE_PENDING )); then
            ui_update_size
            UI_RESIZE_PENDING=0
        fi
        ui_draw_numbered_menu_screen "${title}" "${items[@]}"
        ui_prompt_choice "Choose an option: " choice

        case "${choice}" in
            b|B)
                UI_MENU_RESULT="back"
                return 0
                ;;
            q|Q)
                UI_MENU_RESULT="quit"
                return 0
                ;;
            r|R)
                UI_MENU_RESULT="refresh"
                return 0
                ;;
            '')
                continue
                ;;
            *[!0-9]*)
                ui_message "${title}" "Invalid choice: ${choice}"
                ;;
            *)
                if (( choice >= 1 && choice <= ${#items[@]} )); then
                    UI_MENU_INDEX=$((choice - 1))
                    UI_MENU_RESULT="select"
                    return 0
                else
                    ui_message "${title}" "Invalid choice: ${choice}"
                fi
                ;;
        esac
    done
}

ui_draw_scrollable_subscreen() {
    local title="$1"
    local scroll_offset="$2"
    shift 2
    local lines=("$@")
    local width="${UI_COLS}"
    local max_lines=$((UI_ROWS - 6))
    local i start end

    start=${scroll_offset}
    end=$((start + max_lines))
    if (( end > ${#lines[@]} )); then end=${#lines[@]}; fi

    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    local title_with_pos
    title_with_pos="${title} ($(ui_color "${COLOR_DIM}" "$((start+1))-$((end))/${#lines[@]}")"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"

    for ((i = start; i < end; i++)); do
        ui_draw_box_line "${width}" "${lines[$i]}"
    done
    for ((i = end - start; i < max_lines; i++)); do
        ui_draw_box_line "${width}" ""
    done

    ui_draw_separator "${width}"
    local footer_text
    footer_text="$(ui_color "${COLOR_DIM}" "↑↓ Scroll  Enter Return")"
    ui_draw_box_line "${width}" "$(ui_center "${footer_text}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
}

# =============================================================================
# Input handling
# =============================================================================

ui_normalize_key() {
    local k="${UI_LAST_KEY}"
    case "${k}" in
        $'\eOA') UI_LAST_KEY=$'\e[A' ;;
        $'\eOB') UI_LAST_KEY=$'\e[B' ;;
        $'\eOC') UI_LAST_KEY=$'\e[C' ;;
        $'\eOD') UI_LAST_KEY=$'\e[D' ;;
        $'\e['*)
            if [[ "${k}" =~ \[([0-9]+)\;[0-9]+([ABCD])$ ]]; then
                UI_LAST_KEY=$'\e['"${BASH_REMATCH[2]}"
            elif [[ "${k}" =~ \[([ABCD])$ ]]; then
                UI_LAST_KEY=$'\e['"${BASH_REMATCH[1]}"
            fi
            ;;
    esac
}

ui_read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null || key=""
    if [[ -z "${key}" ]]; then
        UI_LAST_KEY=""
        return 1
    fi
    if [[ "${key}" == $'\x1b' ]]; then
        local rest=""
        local part
        while IFS= read -rsn1 -t 0.15 part 2>/dev/null; do
            rest+="${part}"
            if [[ "${rest}" =~ ^\[[0-9\;]*[A-Za-z]$ ]]; then
                break
            fi
            if [[ "${rest}" =~ ^O[A-Za-z]$ ]]; then
                break
            fi
            if ((${#rest} >= 12)); then
                break
            fi
        done
        key+="${rest}"
    elif [[ "${key}" == $'\r' ]]; then
        ui_drain_input
    fi
    UI_LAST_KEY="${key}"
    ui_normalize_key
    return 0
}

# Wait for a keypress. Returns 0 if a key was pressed, 1 on timeout.
ui_wait_key() {
    local timeout="${1:-0}"
    UI_LAST_KEY=""

    if (( timeout > 0 )); then
        if ! IFS= read -rsn1 -t "${timeout}" UI_LAST_KEY 2>/dev/null; then
            return 1
        fi
    else
        if ! IFS= read -rsn1 UI_LAST_KEY 2>/dev/null; then
            return 1
        fi
    fi

    if [[ -z "${UI_LAST_KEY}" ]]; then
        return 1
    fi

    if [[ "${UI_LAST_KEY}" == $'\x1b' ]]; then
        local rest=""
        local part
        while IFS= read -rsn1 -t 0.05 part 2>/dev/null; do
            rest+="${part}"
            case "${rest}" in
                '['?|'['?*) break ;;
            esac
            if ((${#rest} >= 8)); then
                break
            fi
        done
        UI_LAST_KEY+="${rest}"
    elif [[ "${UI_LAST_KEY}" == $'\r' ]]; then
        ui_drain_input
    fi

    return 0
}

ui_handle_menu_nav() {
    ui_normalize_key
    local key="${UI_LAST_KEY}"
    case "${key}" in
        $'\x1b[A'|k|K) # Up
            if (( UI_MENU_INDEX > 0 )); then ((UI_MENU_INDEX--)); fi
            return 0
            ;;
        $'\x1b[B'|j|J) # Down
            if (( UI_MENU_INDEX < ${#UI_MENU_ITEMS[@]} - 1 )); then ((UI_MENU_INDEX++)); fi
            return 0
            ;;
        q|Q)
            return 2
            ;;
        r|R)
            return 3
            ;;
        s|S)
            return 4
            ;;
        $'\r'|$'\n') # Enter
            ui_drain_input
            return 10
            ;;
    esac
    return 99
}

# =============================================================================
# Prompts and confirmations (ANSI-based, no dialog)
# =============================================================================

ui_confirm() {
    local message="$1"
    local width="${UI_COLS}"
    local inner=$((width - 4))
    local choice

    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "Confirm")" "${inner}")"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" ""
    ui_draw_box_line "${width}" "$(ui_center "${message}" "${inner}")"
    ui_draw_box_line "${width}" ""
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Type y or n, then press Enter")" "${inner}")"
    ui_draw_box_bottom "${width}"

    ui_prompt_choice "Confirm (y/n): " choice
    case "${choice}" in
        y|Y|yes|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

ui_message() {
    local title="$1"
    local message="$2"
    local width="${UI_COLS}"
    local inner=$((width - 4))

    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" "${inner}")"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" ""
    ui_draw_box_line "${width}" "${message}"
    ui_draw_box_line "${width}" ""
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Press Enter to continue...")" "${inner}")"
    ui_draw_box_bottom "${width}"
    ui_tty_restore
    printf '\033[%d;1H' "${UI_ROWS}"
    printf '\033[2K'
    ui_color "${COLOR_DIM}" "Press Enter to continue..."
    ui_reset_attrs
    read -r _
    ui_tty_init
}

ui_text_input() {
    local prompt="$1"
    local default="${2:-}"
    local width="${UI_COLS}"
    local inner=$((width - 4))
    local value="${default}"

    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "Input")" "${inner}")"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "${prompt}"
    ui_draw_box_line "${width}" "> ${value}"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Enter Confirm  Esc Cancel")" "${inner}")"
    ui_draw_box_bottom "${width}"

    stty -echo 2>/dev/null || true
    local key char
    value=""
    while true; do
        ui_read_key >/dev/null
        key="${UI_LAST_KEY}"
        case "${key}" in
            $'\x1b') stty echo 2>/dev/null || true; return 1 ;;
            ''|$'\n'|$'\r') stty echo 2>/dev/null || true; REPLY="${value}"; return 0 ;;
            $'\x7f'|$'\b') value="${value%?}" ;;
            ?) value+="${key}" ;;
        esac
        ui_clear
        ui_draw_box_top "${width}"
        ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "Input")" "${inner}")"
        ui_draw_separator "${width}"
        ui_draw_box_line "${width}" "${prompt}"
        ui_draw_box_line "${width}" "> ${value}"
        ui_draw_separator "${width}"
        ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Enter Confirm  Esc Cancel")" "${inner}")"
        ui_draw_box_bottom "${width}"
    done
}

ui_select_from_list() {
    local title="$1"
    shift
    local items=("$@")

    ui_numbered_menu "${title}" "${items[@]}"
    case "${UI_MENU_RESULT}" in
        back)
            return 1
            ;;
        quit)
            return 2
            ;;
        select)
            REPLY="${items[$UI_MENU_INDEX]}"
            return 0
            ;;
    esac
    return 1
}

# =============================================================================
# Utility: run command with timeout (for non-cache foreground ops only)
# =============================================================================

ui_run_timeout() {
    local timeout="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout}" "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
}

# =============================================================================
# Format helpers for modules
# =============================================================================

ui_kv_line() {
    local label="$1"
    local value="$2"
    printf '%s%s' "$(ui_color "${COLOR_LABEL}" "${label}: ")" "$(ui_color "${COLOR_VALUE}" "${value}")"
}

ui_section_header() {
    local text="$1"
    ui_color "${COLOR_ACCENT}" "── ${text} ──"
}

ui_progress_bar() {
    local percent="$1"
    local width="${2:-20}"
    local filled empty
    percent=${percent%%.*}
    [[ -z "${percent}" || ! "${percent}" =~ ^[0-9]+$ ]] && percent=0
    if (( percent > 100 )); then percent=100; fi
    filled=$((percent * width / 100))
    empty=$((width - filled))
    ui_color "${COLOR_STATUS_OK}" "$(ui_repeat_char '█' "${filled}")"
    ui_color "${COLOR_DIM}" "$(ui_repeat_char '░' "${empty}")"
    printf ' %s%%' "${percent}"
}
