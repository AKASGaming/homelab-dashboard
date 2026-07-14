#!/usr/bin/env bash
# =============================================================================
# network.sh - Network diagnostics module
# =============================================================================

[[ -n "${_NETWORK_SH_LOADED:-}" ]] && return 0
_NETWORK_SH_LOADED=1

network_module_menu() {
    local items=(
        "Overview"
        "Interfaces"
        "Routes"
        "DNS"
        "Internet Check"
        "Ping Diagnostics"
        "Tailscale"
        "WireGuard"
        "Speedtest"
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
        ui_draw_subscreen "${draw_mode}" "Network" "${lines[@]}"
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
                    0) network_show_overview ;;
                    1) network_show_interfaces ;;
                    2) network_show_routes ;;
                    3) network_show_dns ;;
                    4) network_show_internet ;;
                    5) network_show_ping ;;
                    6) network_show_tailscale ;;
                    7) network_show_wireguard ;;
                    8) network_show_speedtest ;;
                    9) return 0 ;;
                esac
                ;;
        esac
    done
}

network_show_overview() {
    local lines=()
    lines+=("$(ui_section_header "Network Overview")")
    lines+=("$(ui_kv_line "LAN IP" "$(ui_cache_json network.json .lan_ip)")")
    lines+=("$(ui_kv_line "WAN IP" "$(ui_cache_json network.json .wan_ip)")")
    lines+=("$(ui_kv_line "Gateway" "$(ui_cache_json network.json .gateway)")")
    lines+=("$(ui_kv_line "DNS" "$(ui_cache_json network.json .dns)")")
    lines+=("")

    local internet
    internet=$(ui_cache_json network.json .internet)
    if [[ "${internet}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ Internet connected")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ No internet")")
    fi

    lines+=("")
    lines+=("$(ui_kv_line "Ping Latency" "$(ui_cache_json network.json .ping_latency_ms) ms")")
    lines+=("$(ui_kv_line "DNS Latency" "$(ui_cache_json network.json .dns_latency_ms) ms")")
    lines+=("$(ui_kv_line "Tailscale" "$(ui_cache_json tailscale.json .self_ip)")")

    ui_draw_subscreen "Network - Overview" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_interfaces() {
    local lines=()
    lines+=("$(ui_section_header "Interfaces")")

    local iface_lines line
    mapfile -t iface_lines < <(ip -br addr 2>/dev/null)
    for line in "${iface_lines[@]}"; do
        lines+=("${line}")
    done

    if (( ${#lines[@]} < 2 )); then
        local raw
        raw=$(ui_cache_json network.json .interfaces_raw)
        while IFS= read -r line; do
            [[ -n "${line}" ]] && lines+=("${line}")
        done <<< "${raw}"
    fi

    ui_draw_subscreen "Network - Interfaces" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_routes() {
    local lines=()
    lines+=("$(ui_section_header "Routing Table")")

    ip route 2>/dev/null | head -25 | while IFS= read -r line; do
        lines+=("${line}")
    done

    ui_draw_subscreen "Network - Routes" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_dns() {
    local lines=()
    lines+=("$(ui_section_header "DNS Configuration")")
    lines+=("$(ui_kv_line "Primary DNS" "$(ui_cache_json network.json .dns)")")
    lines+=("")
    lines+=("$(ui_color "${COLOR_LABEL}" "/etc/resolv.conf:")")
    grep -v '^#' /etc/resolv.conf 2>/dev/null | head -10 | while IFS= read -r line; do
        lines+=("  ${line}")
    done
    lines+=("")
    lines+=("$(ui_kv_line "DNS Latency" "$(ui_cache_json network.json .dns_latency_ms) ms (${DNS_TEST_HOST:-google.com})")")

    ui_draw_subscreen "Network - DNS" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_internet() {
    local lines=()
    lines+=("$(ui_section_header "Internet Connectivity")")

    local internet ping wan
    internet=$(ui_cache_json network.json .internet)
    ping=$(ui_cache_json network.json .ping_latency_ms)
    wan=$(ui_cache_json network.json .wan_ip)

    if [[ "${internet}" == "true" ]]; then
        lines+=("$(ui_color "${COLOR_STATUS_OK}" "✓ Reachable (${PING_TARGET:-1.1.1.1})")")
    else
        lines+=("$(ui_color "${COLOR_STATUS_ERR}" "✗ Unreachable")")
    fi
    lines+=("$(ui_kv_line "WAN IP" "${wan}")")
    lines+=("$(ui_kv_line "Latency" "${ping} ms")")

    ui_draw_subscreen "Network - Internet" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_ping() {
    local lines=()
    lines+=("$(ui_section_header "Ping Diagnostics")")
    lines+=("$(ui_color "${COLOR_DIM}" "Pinging ${PING_TARGET:-1.1.1.1}...")")
    lines+=("")

    local result
    result=$(ping -c "${PING_COUNT:-3}" -W 2 "${PING_TARGET:-1.1.1.1}" 2>&1 || echo "Ping failed")
    while IFS= read -r line; do
        lines+=("${line}")
    done <<< "${result}"

    ui_draw_subscreen "Network - Ping" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_tailscale() {
    local lines=()
    lines+=("$(ui_section_header "Tailscale")")
    lines+=("$(ui_kv_line "Container" "${TAILSCALE_CONTAINER:-tailscale}")")
    lines+=("$(ui_kv_line "IP" "$(ui_cache_json tailscale.json .self_ip)")")
    lines+=("$(ui_kv_line "Version" "$(ui_cache_json tailscale.json .version)")")
    lines+=("")

    local status
    status=$(ui_cache_json tailscale.json .status_raw)
    while IFS= read -r line; do
        lines+=("$(ui_truncate "${line}" 80)")
    done <<< "${status}"

    ui_draw_subscreen "Network - Tailscale" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_wireguard() {
    local lines=()
    lines+=("$(ui_section_header "WireGuard")")

    if [[ -f "${CACHE_DIR}/wireguard.json" ]] && command -v jq >/dev/null 2>&1; then
        local count
        count=$(jq '.interfaces | length' "${CACHE_DIR}/wireguard.json" 2>/dev/null || echo 0)
        local i
        for ((i = 0; i < count; i++)); do
            local iface ip
            iface=$(jq -r ".interfaces[${i}].interface" "${CACHE_DIR}/wireguard.json")
            ip=$(jq -r ".interfaces[${i}].ip" "${CACHE_DIR}/wireguard.json")
            lines+=("$(ui_kv_line "${iface}" "${ip}")")
            local peers
            peers=$(jq -r ".interfaces[${i}].peers_raw" "${CACHE_DIR}/wireguard.json" | head -5)
            while IFS= read -r line; do
                [[ -n "${line}" ]] && lines+=("  $(ui_color "${COLOR_DIM}" "${line}")")
            done <<< "${peers}"
        done
        if (( count == 0 )); then
            lines+=("$(ui_color "${COLOR_DIM}" "No WireGuard interfaces detected")")
        fi
    else
        lines+=("$(ui_color "${COLOR_DIM}" "WireGuard cache unavailable")")
    fi

    ui_draw_subscreen "Network - WireGuard" "${lines[@]}"
    ui_read_key >/dev/null
}

network_show_speedtest() {
    local lines=()
    lines+=("$(ui_section_header "Speedtest (cached)")")

    if [[ -f "${CACHE_DIR}/speedtest.json" ]] && command -v jq >/dev/null 2>&1; then
        local dl ul ping server isp ts
        dl=$(jq -r '.result.download // .result.download.bandwidth // "N/A"' "${CACHE_DIR}/speedtest.json" 2>/dev/null)
        ul=$(jq -r '.result.upload // .result.upload.bandwidth // "N/A"' "${CACHE_DIR}/speedtest.json" 2>/dev/null)
        ping=$(jq -r '.result.ping // .result.ping.latency // "N/A"' "${CACHE_DIR}/speedtest.json" 2>/dev/null)
        server=$(jq -r '.result.server // .result.server.name // "N/A"' "${CACHE_DIR}/speedtest.json" 2>/dev/null)
        isp=$(jq -r '.result.isp // "N/A"' "${CACHE_DIR}/speedtest.json" 2>/dev/null)
        ts=$(jq -r '.timestamp' "${CACHE_DIR}/speedtest.json" 2>/dev/null)

        # Convert bandwidth from bytes/s to Mbps if numeric
        if [[ "${dl}" =~ ^[0-9]+$ ]]; then
            dl=$(awk "BEGIN{printf \"%.1f Mbps\", ${dl}*8/1000000}")
        fi
        if [[ "${ul}" =~ ^[0-9]+$ ]]; then
            ul=$(awk "BEGIN{printf \"%.1f Mbps\", ${ul}*8/1000000}")
        fi

        lines+=("$(ui_kv_line "Download" "${dl}")")
        lines+=("$(ui_kv_line "Upload" "${ul}")")
        lines+=("$(ui_kv_line "Ping" "${ping} ms")")
        lines+=("$(ui_kv_line "Server" "${server}")")
        lines+=("$(ui_kv_line "ISP" "${isp}")")
        lines+=("")
        lines+=("$(ui_color "${COLOR_DIM}" "Last run: $(date -d @${ts} 2>/dev/null || echo ${ts})")")
    else
        lines+=("$(ui_color "${COLOR_DIM}" "No speedtest data. Runs every 10 cache cycles.")")
        lines+=("$(ui_color "${COLOR_DIM}" "Command: ${SPEEDTEST_CMD:-speedtest}")")
    fi

    lines+=("")
    lines+=("$(ui_color "${COLOR_DIM}" "Press R to trigger a speedtest run")")

    ui_draw_subscreen "Network - Speedtest" "${lines[@]}"
    ui_read_key >/dev/null
    if [[ "${UI_LAST_KEY}" == "r" || "${UI_LAST_KEY}" == "R" ]]; then
        if ui_confirm "Run speedtest now? (may take several minutes)"; then
            ui_message "Network" "Running speedtest in background..."
            bash "${INSTALL_DIR}/modules/cache-daemon.sh" once >/dev/null 2>&1 &
        fi
    fi
}
