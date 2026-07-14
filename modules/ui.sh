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

# =============================================================================
# Configuration and theme loading
# =============================================================================

ui_load_config() {
    local config_file="${1:-${INSTALL_DIR}/config/config.conf}"
    if [[ -f "${config_file}" ]]; then
        # shellcheck source=/dev/null
        source "${config_file}"
    fi
    INSTALL_DIR="${INSTALL_DIR:-/opt/homelab-dashboard}"
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
    (( UI_ROWS < 20 )) && UI_ROWS=20
    (( UI_COLS < 60 )) && UI_COLS=60
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
    ui_restore_screen
    stty sane 2>/dev/null || true
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
    (( pad < 0 )) && pad=0
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
    printf '\n'
}

ui_draw_box_top() {
    local width="$1"
    ui_color "${COLOR_BORDER}" "┌"
    ui_draw_hline $((width - 2)) "─"
    printf '\033[%sm' "${COLOR_BORDER}"
    printf '┐\n'
    ui_reset_attrs
}

ui_draw_box_bottom() {
    local width="$1"
    ui_color "${COLOR_BORDER}" "└"
    ui_draw_hline $((width - 2)) "─"
    printf '\033[%sm' "${COLOR_BORDER}"
    printf '┘\n'
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
    printf '\033[%sm' "${COLOR_BORDER}"
    printf '┤\n'
    ui_reset_attrs
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
# Header, status bar, footer
# =============================================================================

ui_draw_header() {
    local width="${UI_COLS}"
    local title="${BANNER_TITLE:-THEATERNAS CONTROL CENTER}"
    local hostname
    hostname=$(ui_cache_json "system.json" '.hostname' "$(hostname -s 2>/dev/null || echo unknown)")

    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "${title}")" $((width - 4)))"
    ui_draw_separator "${width}"

    # Status bar line
    local cpu ram gpu docker_status pihole_status plex_status
    cpu=$(ui_cache_json "system.json" '.cpu_percent' "?")
    ram=$(ui_cache_json "system.json" '.ram_percent' "?")
    gpu=$(ui_cache_json "gpu.json" '.utilization' "?")
    docker_status=$(ui_cache_json "docker.json" '.daemon_running' "false")
    pihole_status=$(ui_cache_json "media.json" '.pihole.running' "false")
    plex_status=$(ui_cache_json "media.json" '.plex.running' "false")

    local status_line=""
    status_line+=$(ui_color "${COLOR_LABEL}" "CPU ")
    status_line+=$(ui_color "${COLOR_VALUE}" "${cpu}% ")
    status_line+=$(ui_color "${COLOR_LABEL}" "RAM ")
    status_line+=$(ui_color "${COLOR_VALUE}" "${ram}% ")
    status_line+=$(ui_color "${COLOR_LABEL}" "GPU ")
    status_line+=$(ui_color "${COLOR_VALUE}" "${gpu}% ")
    status_line+=$(ui_color "${COLOR_LABEL}" "Docker ")
    status_line+=$(ui_status_icon "$([[ "${docker_status}" == "true" ]] && echo ok || echo err)")
    status_line+=" "
    status_line+=$(ui_color "${COLOR_LABEL}" "Pi-hole ")
    status_line+=$(ui_status_icon "$([[ "${pihole_status}" == "true" ]] && echo ok || echo err)")
    status_line+=" "
    status_line+=$(ui_color "${COLOR_LABEL}" "Plex ")
    status_line+=$(ui_status_icon "$([[ "${plex_status}" == "true" ]] && echo ok || echo err)")

    ui_draw_box_line "${width}" "${status_line}"
    ui_draw_separator "${width}"
}

ui_draw_footer() {
    local width="${UI_COLS}"
    local hints
    hints=$(ui_color "${COLOR_DIM}" "Enter Open")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "Q Quit")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "R Refresh")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "S Screensaver")
    hints+="  "
    hints+=$(ui_color "${COLOR_DIM}" "↑↓ Navigate")

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
    local menu_width=$((width / 3))
    local detail_width=$((width - menu_width - 6))
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
    (( shown > max_items )) && shown=${max_items}
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
    local menu_width=$((width / 3))
    local detail_width=$((width - menu_width - 6))

    local hostname uptime containers gpu_temp lan_ip tailscale_ip root_usage
    hostname=$(ui_cache_json "system.json" '.hostname' "unknown")
    uptime=$(ui_cache_json "system.json" '.uptime_human' "unknown")
    containers=$(ui_cache_json "docker.json" '.container_count' "0")
    gpu_temp=$(ui_cache_json "gpu.json" '.temperature' "N/A")
    lan_ip=$(ui_cache_json "network.json" '.lan_ip' "N/A")
    tailscale_ip=$(ui_cache_json "tailscale.json" '.self_ip' "N/A")
    root_usage=$(ui_cache_json "system.json" '.root_usage_percent' "N/A")

    local details=()
    details+=("$(ui_color "${COLOR_LABEL}" "Hostname: ")$(ui_color "${COLOR_VALUE}" "${hostname}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Uptime: ")$(ui_color "${COLOR_VALUE}" "${uptime}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Containers: ")$(ui_color "${COLOR_VALUE}" "${containers}")")
    details+=("$(ui_color "${COLOR_LABEL}" "GPU Temp: ")$(ui_color "${COLOR_VALUE}" "${gpu_temp}")")
    details+=("$(ui_color "${COLOR_LABEL}" "LAN: ")$(ui_color "${COLOR_VALUE}" "${lan_ip}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Tailscale: ")$(ui_color "${COLOR_VALUE}" "${tailscale_ip}")")
    details+=("$(ui_color "${COLOR_LABEL}" "Root Usage: ")$(ui_color "${COLOR_VALUE}" "${root_usage}%")")

    local max_items=$((UI_ROWS - 8))
    local i start
    start=0
    if (( UI_MENU_INDEX >= max_items )); then
        start=$((UI_MENU_INDEX - max_items + 1))
    fi

    # Redraw with details on right side
    local row=0
    for ((i = start; i < start + max_items && i < ${#UI_MENU_ITEMS[@]}; i++)); do
        local item="${UI_MENU_ITEMS[$i]}"
        local prefix="  "
        local color="${COLOR_MENU_INACTIVE}"
        if (( i == UI_MENU_INDEX )); then
            prefix="> "
            color="${COLOR_MENU_ACTIVE}"
        fi
        local menu_part
        menu_part=$(ui_pad_right "$(ui_color "${color}" "${prefix}${item}")" "${menu_width}")
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
}

# =============================================================================
# Sub-screen layout (full module views)
# =============================================================================

ui_draw_subscreen() {
    local title="$1"
    shift
    local lines=("$@")
    local width="${UI_COLS}"
    local max_lines=$((UI_ROWS - 6))
    local i

    ui_update_size
    ui_clear
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
    footer_text="$(ui_color "${COLOR_DIM}" "Enter Select  B Back  R Refresh  Q Quit")"
    ui_draw_box_line "${width}" "$(ui_center "${footer_text}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
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
    (( end > ${#lines[@]} )) && end=${#lines[@]}

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
    footer_text="$(ui_color "${COLOR_DIM}" "↑↓ Scroll  B Back  R Refresh  Q Quit")"
    ui_draw_box_line "${width}" "$(ui_center "${footer_text}" $((width - 4)))"
    ui_draw_box_bottom "${width}"
}

# =============================================================================
# Input handling
# =============================================================================

ui_read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null || key=""
    if [[ "${key}" == $'\x1b' ]]; then
        local rest
        read -rsn2 -t 0.1 rest 2>/dev/null || rest=""
        key+="${rest}"
    fi
    UI_LAST_KEY="${key}"
    printf '%s' "${key}"
}

ui_wait_key() {
    local timeout="${1:-0}"
    if (( timeout > 0 )); then
        read -rsn1 -t "${timeout}" UI_LAST_KEY 2>/dev/null || UI_LAST_KEY=""
        if [[ "${UI_LAST_KEY}" == $'\x1b' ]]; then
            local rest
            read -rsn2 -t 0.1 rest 2>/dev/null || rest=""
            UI_LAST_KEY+="${rest}"
        fi
    else
        ui_read_key >/dev/null
    fi
}

ui_handle_menu_nav() {
    local key="${UI_LAST_KEY}"
    case "${key}" in
        $'\x1b[A'|k|K) # Up
            ((UI_MENU_INDEX > 0)) && ((UI_MENU_INDEX--)) || true
            return 0
            ;;
        $'\x1b[B'|j|J) # Down
            ((UI_MENU_INDEX < ${#UI_MENU_ITEMS[@]} - 1)) && ((UI_MENU_INDEX++)) || true
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
        ''|$'\n'|$'\r') # Enter
            return 1
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

    ui_update_size
    ui_clear
    ui_draw_box_top "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_HEADER}" "Confirm")" "${inner}")"
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" ""
    ui_draw_box_line "${width}" "$(ui_center "${message}" "${inner}")"
    ui_draw_box_line "${width}" ""
    ui_draw_separator "${width}"
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Y Yes  N No")" "${inner}")"
    ui_draw_box_bottom "${width}"

    local key
    while true; do
        ui_read_key >/dev/null
        key="${UI_LAST_KEY}"
        case "${key}" in
            y|Y) return 0 ;;
            n|N|q|Q|$'\x1b') return 1 ;;
        esac
    done
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
    ui_draw_box_line "${width}" "$(ui_center "$(ui_color "${COLOR_DIM}" "Press any key...")" "${inner}")"
    ui_draw_box_bottom "${width}"
    ui_read_key >/dev/null
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
    local index=0
    local result=""

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
        ui_draw_subscreen "${title}" "${lines[@]}"
        ui_read_key >/dev/null
        case "${UI_LAST_KEY}" in
            $'\x1b[A'|k|K) ((index > 0)) && ((index--)) || true ;;
            $'\x1b[B'|j|J) ((index < ${#items[@]} - 1)) && ((index++)) || true ;;
            ''|$'\n'|$'\r') result="${items[$index]}"; REPLY="${result}"; return 0 ;;
            b|B|$'\x1b') return 1 ;;
            q|Q) return 2 ;;
        esac
    done
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
    (( percent > 100 )) && percent=100
    filled=$((percent * width / 100))
    empty=$((width - filled))
    ui_color "${COLOR_STATUS_OK}" "$(ui_repeat_char '█' "${filled}")"
    ui_color "${COLOR_DIM}" "$(ui_repeat_char '░' "${empty}")"
    printf ' %s%%' "${percent}"
}
