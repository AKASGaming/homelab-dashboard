#!/usr/bin/env bash
# =============================================================================
# cache-daemon.sh - Background cache collector for TheaterNAS Control Center
# Collects slow metrics (Docker, Pi-hole, etc.) and writes JSON cache files.
# The dashboard UI ONLY reads these files — never blocks on Docker.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${INSTALL_DIR}/config/config.conf"

CACHE_DIR="${CACHE_DIR:-${INSTALL_DIR}/cache}"
mkdir -p "${CACHE_DIR}"

LOG_FILE="${CACHE_DIR}/daemon.log"
LOCK_FILE="${CACHE_DIR}/daemon.lock"

# =============================================================================
# Logging
# =============================================================================

cache_log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" >> "${LOG_FILE}"
}

# =============================================================================
# Utility functions
# =============================================================================

cache_run_timeout() {
    local secs="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}" "$@" 2>/dev/null || true
    else
        "$@" 2>/dev/null || true
    fi
}

cache_write_json() {
    local file="$1"
    local content="$2"
    local tmp="${CACHE_DIR}/.${file}.tmp"
    printf '%s\n' "${content}" > "${tmp}"
    mv -f "${tmp}" "${CACHE_DIR}/${file}"
}

cache_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/}
    printf '%s' "${s}"
}

# =============================================================================
# System metrics
# =============================================================================

cache_collect_system() {
    local hostname os kernel uptime_secs uptime_human load cpu ram
    local root_usage root_avail root_total pending_reboot

    hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)

    local days hours mins
    days=$((uptime_secs / 86400))
    hours=$(((uptime_secs % 86400) / 3600))
    mins=$(((uptime_secs % 3600) / 60))
    uptime_human="${days}d ${hours}h ${mins}m"

    load=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "0 0 0")

    # CPU usage via /proc/stat delta-free snapshot
    cpu=$(awk '
        NR==1 { idle=$5+$6; total=0; for(i=2;i<=NF;i++) total+=$i; print (total-idle)*100/total; exit }
    ' /proc/stat 2>/dev/null || echo "0")
    cpu=$(printf '%.0f' "${cpu}" 2>/dev/null || echo "0")

    # RAM
    ram=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.0f", (t-a)*100/t}' /proc/meminfo 2>/dev/null || echo "0")

    # Root filesystem
    root_usage=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || echo "0")
    root_avail=$(df -hP / 2>/dev/null | awk 'NR==2{print $4}' || echo "N/A")
    root_total=$(df -hP / 2>/dev/null | awk 'NR==2{print $2}' || echo "N/A")

    pending_reboot="false"
    if [[ -f /var/run/reboot-required ]] || [[ -f /run/reboot-required ]]; then
        pending_reboot="true"
    fi

    # Temperatures
    local temps="[]"
    if command -v sensors >/dev/null 2>&1; then
        temps=$(sensors -j 2>/dev/null | jq -c '[.. | objects | select(has("temp1_input")) | .temp1_input] | map(select(type=="number"))' 2>/dev/null || echo "[]")
    fi

    # Mounts
    local mounts
    mounts=$(df -hP -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR>1{printf "%s %s %s %s\\n",$1,$6,$5,$4}' | head -20 || echo "")

    cache_write_json "system.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "hostname": "$(cache_json_escape "${hostname}")",
  "os": "$(cache_json_escape "${os}")",
  "kernel": "$(cache_json_escape "${kernel}")",
  "uptime_seconds": ${uptime_secs},
  "uptime_human": "$(cache_json_escape "${uptime_human}")",
  "load": "$(cache_json_escape "${load}")",
  "cpu_percent": "${cpu}",
  "ram_percent": "${ram}",
  "root_usage_percent": "${root_usage}",
  "root_avail": "$(cache_json_escape "${root_avail}")",
  "root_total": "$(cache_json_escape "${root_total}")",
  "pending_reboot": ${pending_reboot},
  "temperatures": ${temps},
  "mounts_raw": "$(cache_json_escape "${mounts}")"
}
EOF
)"
}

# =============================================================================
# Docker metrics (with timeout — never hang)
# =============================================================================

cache_collect_docker() {
    local daemon_running="false"
    local container_count=0 running_count=0 stopped_count=0
    local containers_json="[]" networks_json="[]" volumes_json="[]" images_json="[]"
    local docker_info="{}" daemon_json="{}"

    if ! command -v docker >/dev/null 2>&1; then
        cache_write_json "docker.json" '{"daemon_running":false,"error":"docker not installed","containers":[],"container_count":0}'
        return
    fi

    if cache_run_timeout 5 docker info >/dev/null 2>&1; then
        daemon_running="true"
    else
        cache_write_json "docker.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "daemon_running": false,
  "error": "docker daemon not responding",
  "containers": [],
  "container_count": 0,
  "running_count": 0,
  "stopped_count": 0
}
EOF
)"
        return
    fi

    local ps_output
    ps_output=$(cache_run_timeout "${CACHE_TIMEOUT_DOCKER:-120}" docker ps -a \
        --format '{{json .}}' 2>/dev/null || true)

    if [[ -n "${ps_output}" ]]; then
        containers_json=$(echo "${ps_output}" | jq -s '
            map({
                id: .ID,
                name: .Names,
                image: .Image,
                status: .Status,
                state: (if (.State // "") != "" then .State elif (.Status | test("^Up")) then "running" else "stopped" end),
                health: (.Health // "none"),
                ports: .Ports,
                running_for: .RunningFor
            })
        ' 2>/dev/null || echo "[]")
        container_count=$(echo "${containers_json}" | jq 'length' 2>/dev/null || echo 0)
        running_count=$(echo "${containers_json}" | jq '[.[] | select(.state=="running")] | length' 2>/dev/null || echo 0)
        stopped_count=$((container_count - running_count))
    fi

    networks_json=$(cache_run_timeout 30 docker network ls --format '{{json .}}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
    volumes_json=$(cache_run_timeout 30 docker volume ls --format '{{json .}}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
    images_json=$(cache_run_timeout 60 docker images --format '{{json .}}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")

    daemon_json=$(cache_run_timeout 15 docker info --format '{{json .}}' 2>/dev/null | jq '{
        server_version: .ServerVersion,
        storage_driver: .Driver,
        cgroup_driver: .CgroupDriver,
        runtimes: .Runtimes,
        default_runtime: .DefaultRuntime,
        docker_root: .DockerRootDir,
        containers_running: .ContainersRunning,
        containers_stopped: .ContainersStopped,
        images: .Images
    }' 2>/dev/null || echo "{}")

    # daemon.json
    local daemon_json_file="{}"
    if [[ -f /etc/docker/daemon.json ]]; then
        daemon_json_file=$(cat /etc/docker/daemon.json 2>/dev/null | jq -c '.' 2>/dev/null || echo "{}")
    fi

    # Container stats (lightweight)
    local stats_json="[]"
    stats_json=$(cache_run_timeout 60 docker stats --no-stream --format '{{json .}}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")

    cache_write_json "docker.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "daemon_running": ${daemon_running},
  "container_count": ${container_count},
  "running_count": ${running_count},
  "stopped_count": ${stopped_count},
  "containers": ${containers_json},
  "networks": ${networks_json},
  "volumes": ${volumes_json},
  "images": ${images_json},
  "info": ${daemon_json},
  "daemon_json": ${daemon_json_file},
  "stats": ${stats_json}
}
EOF
)"
}

# =============================================================================
# GPU metrics (NVIDIA)
# =============================================================================

cache_gpu_smi_failed() {
    local output="$1"
    [[ -z "${output}" ]] && return 0
    echo "${output}" | grep -qiE 'failed|couldn.t communicate|not find|error|unable|insufficient|no devices|make sure' && return 0
    return 1
}

cache_gpu_metric_invalid() {
    local value="$1"
    [[ -z "${value}" || "${value}" == "N/A" || "${value}" == "null" ]] && return 0
    [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]] && return 1
    return 0
}

cache_gpu_write_error() {
    local reason="${1:-NVIDIA driver not responding}"
    cache_write_json "gpu.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "available": false,
  "status": "error",
  "utilization": "error",
  "memory": "error",
  "temperature": "error",
  "power": "error",
  "driver": "error",
  "gpu_name": "error",
  "encoder": "error",
  "decoder": "error",
  "processes_raw": "",
  "nvidia_smi_q": "",
  "error_message": "$(cache_json_escape "${reason}")",
  "help_hint": "GPU error — update-dashboard does not fix drivers. GPU > Maintenance > Recovery Guide"
}
EOF
)"
}

cache_collect_gpu() {
    if [[ "${GPU_ENABLED:-true}" != "true" ]] || ! command -v "${GPU_COMMAND:-nvidia-smi}" >/dev/null 2>&1; then
        cache_gpu_write_error "nvidia-smi not installed"
        return
    fi

    local gpu_cmd="${GPU_COMMAND:-nvidia-smi}"
    local util mem temp power driver cuda encoder decoder processes full_query
    local smi_output

    smi_output=$("${gpu_cmd}" --query-gpu=utilization.gpu,temperature.gpu,name,driver_version \
        --format=csv,noheader,nounits 2>&1 | head -1 || true)

    if cache_gpu_smi_failed "${smi_output}"; then
        if echo "${smi_output}" | grep -qi 'couldn.t communicate'; then
            cache_gpu_write_error "NVIDIA driver not communicating"
        elif echo "${smi_output}" | grep -qi 'not found'; then
            cache_gpu_write_error "NVIDIA driver not found"
        else
            cache_gpu_write_error "NVIDIA GPU query failed"
        fi
        return
    fi

    util=$(echo "${smi_output}" | awk -F',' '{gsub(/ /,"",$1); print $1}')
    temp=$(echo "${smi_output}" | awk -F',' '{gsub(/ /,"",$2); print $2}')
    cuda=$(echo "${smi_output}" | awk -F',' '{gsub(/^ /,"",$3); print $3}')
    driver=$(echo "${smi_output}" | awk -F',' '{gsub(/^ /,"",$4); print $4}')

    if cache_gpu_metric_invalid "${util}" || cache_gpu_metric_invalid "${temp}"; then
        cache_gpu_write_error "NVIDIA returned invalid GPU metrics"
        return
    fi

    mem=$("${gpu_cmd}" --query-gpu=utilization.memory,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "N/A")
    power=$("${gpu_cmd}" --query-gpu=power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "N/A")
    encoder=$("${gpu_cmd}" --query-gpu=encoder.stats.sessionCount,encoder.stats.averageFps --format=csv,noheader 2>/dev/null | head -1 || echo "0, 0")
    decoder=$("${gpu_cmd}" --query-gpu=decoder.stats.sessionCount,decoder.stats.averageFps --format=csv,noheader 2>/dev/null | head -1 || echo "0, 0")
    processes=$("${gpu_cmd}" --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader 2>/dev/null | head -20 || echo "")
    full_query=$(cache_run_timeout "${GPU_QUERY_TIMEOUT:-15}" "${gpu_cmd}" -q 2>/dev/null | head -200 || echo "")

    cache_write_json "gpu.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "available": true,
  "status": "ok",
  "utilization": "$(cache_json_escape "${util}")",
  "memory": "$(cache_json_escape "${mem}")",
  "temperature": "$(cache_json_escape "${temp}")C",
  "power": "$(cache_json_escape "${power}")",
  "driver": "$(cache_json_escape "${driver}")",
  "gpu_name": "$(cache_json_escape "${cuda}")",
  "encoder": "$(cache_json_escape "${encoder}")",
  "decoder": "$(cache_json_escape "${decoder}")",
  "processes_raw": "$(cache_json_escape "${processes}")",
  "nvidia_smi_q": "$(cache_json_escape "${full_query}")",
  "error_message": "",
  "help_hint": ""
}
EOF
)"
}

# =============================================================================
# Network metrics
# =============================================================================

cache_collect_network() {
    local lan_ip wan_ip gateway dns internet interfaces routes
    local ping_latency dns_latency

    lan_ip="N/A"
    wan_ip="N/A"
    gateway="N/A"
    dns="N/A"
    internet="false"

    # LAN IP
    if [[ -n "${LAN_INTERFACE:-}" ]] && ip link show "${LAN_INTERFACE}" >/dev/null 2>&1; then
        lan_ip=$(ip -4 addr show "${LAN_INTERFACE}" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1 || echo "N/A")
    else
        lan_ip=$(ip -4 route get "${PING_TARGET:-1.1.1.1}" 2>/dev/null | awk '/src/{print $7; exit}' || echo "N/A")
    fi

    # WAN IP
    if [[ -n "${WAN_INTERFACE:-}" ]]; then
        wan_ip=$(ip -4 addr show "${WAN_INTERFACE}" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1 || echo "N/A")
    fi
    if [[ "${wan_ip}" == "N/A" ]]; then
        wan_ip=$(cache_run_timeout 10 curl -4 -s ifconfig.me 2>/dev/null || cache_run_timeout 10 wget -qO- ifconfig.me 2>/dev/null || echo "N/A")
    fi

    gateway=$(ip route 2>/dev/null | awk '/default/{print $3; exit}' || echo "N/A")
    dns=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' || echo "N/A")

    if cache_run_timeout 5 ping -c 1 -W 2 "${PING_TARGET:-1.1.1.1}" >/dev/null 2>&1; then
        internet="true"
    fi

    ping_latency=$(ping -c "${PING_COUNT:-3}" -W 2 "${PING_TARGET:-1.1.1.1}" 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5; exit}' || echo "N/A")
    dns_latency=$(cache_run_timeout 10 dig +stats "${DNS_TEST_HOST:-google.com}" 2>/dev/null | awk '/Query time/{print $4; exit}' || echo "N/A")

    interfaces=$(ip -br addr 2>/dev/null | awk '{print $1" "$2" "$3}' | head -20 || echo "")
    routes=$(ip route 2>/dev/null | head -30 || echo "")

    cache_write_json "network.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "lan_ip": "$(cache_json_escape "${lan_ip}")",
  "wan_ip": "$(cache_json_escape "${wan_ip}")",
  "gateway": "$(cache_json_escape "${gateway}")",
  "dns": "$(cache_json_escape "${dns}")",
  "internet": ${internet},
  "ping_latency_ms": "$(cache_json_escape "${ping_latency}")",
  "dns_latency_ms": "$(cache_json_escape "${dns_latency}")",
  "interfaces_raw": "$(cache_json_escape "${interfaces}")",
  "routes_raw": "$(cache_json_escape "${routes}")"
}
EOF
)"
}

# =============================================================================
# Tailscale (Docker container)
# =============================================================================

cache_collect_tailscale() {
    local container="${TAILSCALE_CONTAINER:-tailscale}"
    local status ip version peers available="false"
    local self_ip="N/A" backend_state="unknown"

    if command -v docker >/dev/null 2>&1; then
        if cache_run_timeout 30 docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${container}"; then
            available="true"
            status=$(cache_run_timeout 30 docker exec "${container}" tailscale status 2>/dev/null || echo "unavailable")
            ip=$(cache_run_timeout 15 docker exec "${container}" tailscale ip -4 2>/dev/null | head -1 || echo "N/A")
            version=$(cache_run_timeout 15 docker exec "${container}" tailscale version 2>/dev/null | head -1 || echo "N/A")
            self_ip="${ip}"
            backend_state=$(echo "${status}" | head -5 || echo "unknown")
        fi
    fi

    # Also check host tailscale
    if [[ "${available}" != "true" ]] && command -v tailscale >/dev/null 2>&1; then
        if cache_run_timeout 15 tailscale status >/dev/null 2>&1; then
            available="true"
            status=$(cache_run_timeout 15 tailscale status 2>/dev/null || echo "")
            self_ip=$(cache_run_timeout 10 tailscale ip -4 2>/dev/null | head -1 || echo "N/A")
            version=$(cache_run_timeout 10 tailscale version 2>/dev/null | head -1 || echo "N/A")
        fi
    fi

    cache_write_json "tailscale.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "available": ${available},
  "container": "$(cache_json_escape "${container}")",
  "self_ip": "$(cache_json_escape "${self_ip}")",
  "version": "$(cache_json_escape "${version}")",
  "status_raw": "$(cache_json_escape "${status}")",
  "backend_state": "$(cache_json_escape "${backend_state}")"
}
EOF
)"
}

# =============================================================================
# WireGuard
# =============================================================================

cache_collect_wireguard() {
    local wg_data="[]"
    local interfaces="${WG_INTERFACES:-wg0}"

    if command -v wg >/dev/null 2>&1; then
        local iface_list
        if [[ "${interfaces}" == "auto" ]]; then
            iface_list=$(ip link 2>/dev/null | awk -F': ' '/wg/{print $2}' | awk '{print $1}' || echo "")
        else
            iface_list=$(echo "${interfaces}" | tr ',' ' ')
        fi

        local entries="["
        local first=true
        for iface in ${iface_list}; do
            [[ -z "${iface}" ]] && continue
            local wg_ip pub_key endpoint
            wg_ip=$(ip -4 addr show "${iface}" 2>/dev/null | awk '/inet /{print $2; exit}' || echo "N/A")
            pub_key=$(wg show "${iface}" public-key 2>/dev/null || echo "N/A")
            endpoint=$(wg show "${iface}" endpoints 2>/dev/null | head -1 || echo "N/A")
            local peers
            peers=$(wg show "${iface}" 2>/dev/null | head -50 || echo "")
            if [[ "${first}" == "true" ]]; then first=false; else entries+=","; fi
            entries+=$(cat <<PEER_EOF
{
  "interface": "$(cache_json_escape "${iface}")",
  "ip": "$(cache_json_escape "${wg_ip}")",
  "public_key": "$(cache_json_escape "${pub_key}")",
  "endpoint": "$(cache_json_escape "${endpoint}")",
  "peers_raw": "$(cache_json_escape "${peers}")"
}
PEER_EOF
)
        done
        entries+="]"
        wg_data="${entries}"
    fi

    cache_write_json "wireguard.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "available": $(command -v wg >/dev/null 2>&1 && echo true || echo false),
  "interfaces": ${wg_data}
}
EOF
)"
}

# =============================================================================
# Media (Pi-hole v6 + Plex)
# =============================================================================

cache_collect_pihole() {
    local container="${PIHOLE_CONTAINER:-pihole}"
    local running="false" queries_blocked="N/A" queries_total="N/A" status="unknown"
    local api_url="${PIHOLE_API_URL:-http://127.0.0.1}"
    local api_port="${PIHOLE_API_PORT:-80}"
    local base="${api_url}:${api_port}"

    if command -v docker >/dev/null 2>&1; then
        if cache_run_timeout 10 docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${container}"; then
            running="true"
        fi
    fi

    # Pi-hole v6 API - /api/stats/summary
    local summary="{}"
    if [[ "${running}" == "true" ]] || cache_run_timeout "${CACHE_TIMEOUT_PIHOLE:-30}" curl -sf "${base}/api/stats/summary" >/dev/null 2>&1; then
        local auth_header=""
        if [[ -n "${PIHOLE_API_PASSWORD:-}" ]]; then
            auth_header="-H sid: $(cache_run_timeout 10 curl -sf -X POST "${base}/api/auth" -H 'Content-Type: application/json' -d "{\"password\":\"${PIHOLE_API_PASSWORD}\"}" 2>/dev/null | jq -r '.session.sid // empty' 2>/dev/null)"
        fi
        summary=$(cache_run_timeout "${CACHE_TIMEOUT_PIHOLE:-30}" bash -c "curl -sf ${auth_header} '${base}/api/stats/summary'" 2>/dev/null | jq -c '.' 2>/dev/null || echo "{}")
        if [[ "${summary}" != "{}" ]]; then
            queries_total=$(echo "${summary}" | jq -r '.queries.total // "N/A"' 2>/dev/null || echo "N/A")
            queries_blocked=$(echo "${summary}" | jq -r '.queries.blocked // "N/A"' 2>/dev/null || echo "N/A")
            status="ok"
        fi
    fi

    local logs=""
    if [[ "${running}" == "true" ]] && command -v docker >/dev/null 2>&1; then
        logs=$(cache_run_timeout 15 docker logs --tail 20 "${container}" 2>&1 || echo "")
    fi

    printf '{"running":%s,"container":"%s","status":"%s","queries_total":"%s","queries_blocked":"%s","summary":%s,"logs_raw":"%s"}' \
        "${running}" \
        "$(cache_json_escape "${container}")" \
        "$(cache_json_escape "${status}")" \
        "$(cache_json_escape "${queries_total}")" \
        "$(cache_json_escape "${queries_blocked}")" \
        "${summary}" \
        "$(cache_json_escape "${logs}")"
}

cache_collect_plex() {
    local container="${PLEX_CONTAINER:-plex}"
    local running="false" transcodes="N/A" sessions="0"
    local plex_url="${PLEX_URL:-http://127.0.0.1:32400}"

    if command -v docker >/dev/null 2>&1; then
        if cache_run_timeout 10 docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${container}"; then
            running="true"
        fi
    fi

    local token_param=""
    if [[ -n "${PLEX_TOKEN:-}" ]]; then
        token_param="?X-Plex-Token=${PLEX_TOKEN}"
    fi

    local sessions_data="[]"
    if cache_run_timeout 15 curl -sf "${plex_url}/status/sessions${token_param}" >/dev/null 2>&1; then
        sessions_data=$(cache_run_timeout 15 curl -sf "${plex_url}/status/sessions${token_param}" 2>/dev/null | head -100 || echo "[]")
        sessions=$(echo "${sessions_data}" | grep -o 'MediaContainer size="[0-9]*"' 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
    fi

    local logs=""
    if [[ "${running}" == "true" ]] && command -v docker >/dev/null 2>&1; then
        logs=$(cache_run_timeout 15 docker logs --tail 20 "${container}" 2>&1 || echo "")
    fi

    printf '{"running":%s,"container":"%s","sessions":"%s","transcodes":"%s","sessions_raw":"%s","logs_raw":"%s"}' \
        "${running}" \
        "$(cache_json_escape "${container}")" \
        "$(cache_json_escape "${sessions}")" \
        "$(cache_json_escape "${transcodes}")" \
        "$(cache_json_escape "${sessions_data}")" \
        "$(cache_json_escape "${logs}")"
}

cache_collect_media() {
    local pihole plex
    pihole=$(cache_collect_pihole)
    plex=$(cache_collect_plex)

    cache_write_json "media.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "pihole": ${pihole},
  "plex": ${plex}
}
EOF
)"
}

# =============================================================================
# Storage / SMART
# =============================================================================

cache_collect_storage() {
    local smart_data="[]" disk_temps="[]" wear_data="[]"
    local devices

    if [[ "${SMART_DEVICES:-auto}" == "auto" ]]; then
        devices=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}' || echo "")
    else
        devices=$(echo "${SMART_DEVICES}" | tr ',' ' ')
    fi

    if command -v smartctl >/dev/null 2>&1; then
        local entries="["
        local first=true
        for dev in ${devices}; do
            [[ -z "${dev}" || ! -b "${dev}" ]] && continue
            local health attr temp wear
            health=$(cache_run_timeout 15 smartctl -H "${dev}" 2>/dev/null | grep -i "overall" | head -1 || echo "unknown")
            attr=$(cache_run_timeout 15 smartctl -A "${dev}" 2>/dev/null | head -30 || echo "")
            temp=$(cache_run_timeout 15 smartctl -A "${dev}" 2>/dev/null | awk '/Temperature/{print $10; exit}' || echo "N/A")
            wear=$(cache_run_timeout 15 smartctl -A "${dev}" 2>/dev/null | awk '/Wear_Leveling|Media_Wearout|Percent_Lifetime/{print $4; exit}' || echo "N/A")
            if [[ "${first}" == "true" ]]; then first=false; else entries+=","; fi
            entries+=$(cat <<SMART_EOF
{
  "device": "$(cache_json_escape "${dev}")",
  "health": "$(cache_json_escape "${health}")",
  "temperature": "$(cache_json_escape "${temp}")",
  "wear": "$(cache_json_escape "${wear}")",
  "attributes_raw": "$(cache_json_escape "${attr}")"
}
SMART_EOF
)
        done
        entries+="]"
        smart_data="${entries}"
    fi

    # Largest directories (can be slow — run with timeout)
    local largest=""
    largest=$(cache_run_timeout 120 du -xh --max-depth=1 "${LARGEST_DIRS_PATH:-/}" 2>/dev/null | sort -hr | head -"${LARGEST_DIRS_COUNT:-10}" || echo "")

    cache_write_json "storage.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "smart": ${smart_data},
  "largest_dirs_raw": "$(cache_json_escape "${largest}")"
}
EOF
)"
}

# =============================================================================
# Speedtest (optional, slow — cached separately)
# =============================================================================

cache_collect_speedtest() {
    if [[ "${SPEEDTEST_ENABLED:-true}" != "true" ]]; then
        return
    fi

    local cmd="${SPEEDTEST_CMD:-speedtest}"
    local result="{}"

    if command -v "${cmd}" >/dev/null 2>&1; then
        if [[ "${cmd}" == "speedtest" ]]; then
            result=$(cache_run_timeout "${CACHE_TIMEOUT_SPEEDTEST:-300}" speedtest -f json 2>/dev/null | jq -c '{
                download: .download.bandwidth,
                upload: .upload.bandwidth,
                ping: .ping.latency,
                server: .server.name,
                isp: .isp
            }' 2>/dev/null || echo "{}")
        elif [[ "${cmd}" == "speedtest-cli" ]]; then
            local output
            output=$(cache_run_timeout "${CACHE_TIMEOUT_SPEEDTEST:-300}" speedtest-cli --json 2>/dev/null || echo "{}")
            result="${output}"
        fi
    fi

    cache_write_json "speedtest.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "result": ${result}
}
EOF
)"
}

# =============================================================================
# Main collection cycle
# =============================================================================

cache_collect_all() {
    cache_log "Starting collection cycle"
    cache_collect_system
    cache_collect_docker
    cache_collect_gpu
    cache_collect_network
    cache_collect_tailscale
    cache_collect_wireguard
    cache_collect_media
    cache_collect_storage
    # Speedtest only every 10th cycle to avoid excessive bandwidth use
    local cycle_count
    cycle_count=$(cat "${CACHE_DIR}/.cycle_count" 2>/dev/null || echo 0)
    cycle_count=$((cycle_count + 1))
    echo "${cycle_count}" > "${CACHE_DIR}/.cycle_count"
    if (( cycle_count % 10 == 0 )); then
        cache_collect_speedtest
    fi
    cache_write_json "daemon_status.json" "$(cat <<EOF
{
  "timestamp": $(date +%s),
  "last_cycle": $(date +%s),
  "pid": $$,
  "status": "ok"
}
EOF
)"
    cache_log "Collection cycle complete"
}

# =============================================================================
# Daemon loop
# =============================================================================

cache_daemon_loop() {
    cache_log "Cache daemon started (PID $$)"
    while true; do
        cache_collect_all
        sleep "${CACHE_INTERVAL:-30}"
    done
}

cache_acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local old_pid
        old_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
        if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
            cache_log "Another instance running (PID ${old_pid})"
            exit 0
        fi
    fi
    echo $$ > "${LOCK_FILE}"
}

cache_release_lock() {
    rm -f "${LOCK_FILE}"
}

# =============================================================================
# Entry point
# =============================================================================

main() {
    case "${1:-daemon}" in
        once)
            cache_collect_all
            ;;
        daemon)
            trap 'cache_release_lock; exit 0' INT TERM EXIT
            cache_acquire_lock
            # Initial collection immediately
            cache_collect_all &
            cache_daemon_loop
            ;;
        *)
            echo "Usage: $0 {daemon|once}"
            exit 1
            ;;
    esac
}

main "$@"
