#!/usr/bin/env bash
# =============================================================================
# update.sh - TheaterNAS Control Center updater
# Preserves config, replaces code, restarts cache daemon.
# Run as root: sudo update-dashboard
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/homelab-dashboard"
SERVICE_NAME="homelab-dashboard-cache"
REPO_URL="${HOMELAB_REPO_URL:-https://github.com/AKASGaming/homelab-dashboard.git}"
TEMP_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

cleanup() {
    [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]] && rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Must run as root (sudo update-dashboard)"
        exit 1
    fi
}

backup_config() {
    if [[ -f "${INSTALL_DIR}/config/config.conf" ]]; then
        cp -a "${INSTALL_DIR}/config/config.conf" "/tmp/homelab-dashboard-config.conf.bak"
        log_ok "Config backed up"
    fi
}

get_source() {
    local source_dir="${1:-}"

    if [[ -n "${source_dir}" && -d "${source_dir}" ]]; then
        echo "${source_dir}"
        return
    fi

    if [[ -d "${INSTALL_DIR}/.git" ]] && command -v git >/dev/null 2>&1; then
        log_info "Pulling updates from git..."
        git -C "${INSTALL_DIR}" pull --ff-only
        echo "${INSTALL_DIR}"
        return
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_error "git not found. Install git or provide source directory: update-dashboard /path/to/source"
        exit 1
    fi

    TEMP_DIR=$(mktemp -d)
    log_info "Cloning ${REPO_URL}..."
    git clone --depth 1 "${REPO_URL}" "${TEMP_DIR}"
    echo "${TEMP_DIR}"
}

strip_crlf() {
    local target_dir="$1"
    local f
    find "${target_dir}" -type f \( -name '*.sh' -o -name 'main-menu' -o -name '*.conf' -o -name '*.theme' -o -name '*.service' \) -print0 |
        while IFS= read -r -d '' f; do
            sed -i 's/\r$//' "${f}" 2>/dev/null || true
        done
}

update_files() {
    local source_dir="$1"

    log_info "Updating files from ${source_dir}..."

    if [[ ! -f "${source_dir}/main-menu" ]]; then
        log_error "Invalid source directory: main-menu not found in ${source_dir}"
        exit 1
    fi

    # Update code files, preserve config and cache
    cp -a "${source_dir}/main-menu" "${INSTALL_DIR}/"
    cp -a "${source_dir}/VERSION" "${INSTALL_DIR}/"
    cp -a "${source_dir}/modules/"* "${INSTALL_DIR}/modules/"
    cp -a "${source_dir}/themes/"* "${INSTALL_DIR}/themes/"
    cp -a "${source_dir}/systemd/"* "${INSTALL_DIR}/systemd/"
    cp -a "${source_dir}/install.sh" "${INSTALL_DIR}/" 2>/dev/null || true
    cp -a "${source_dir}/update.sh" "${INSTALL_DIR}/"
    cp -a "${source_dir}/uninstall.sh" "${INSTALL_DIR}/"

    strip_crlf "${INSTALL_DIR}"

    # Restore config
    if [[ -f "/tmp/homelab-dashboard-config.conf.bak" ]]; then
        cp -a "/tmp/homelab-dashboard-config.conf.bak" "${INSTALL_DIR}/config/config.conf"
        log_ok "Config preserved"
    fi

    chmod +x "${INSTALL_DIR}/main-menu"
    chmod +x "${INSTALL_DIR}/modules/"*.sh
    chmod +x "${INSTALL_DIR}/update.sh"
    chmod +x "${INSTALL_DIR}/uninstall.sh"

    log_ok "Files updated"
}

restart_daemon() {
    log_info "Restarting cache daemon..."
    cp "${INSTALL_DIR}/systemd/homelab-dashboard-cache.service" \
        "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}.service"
    log_ok "Cache daemon restarted"
}

main() {
    local source_dir="${1:-}"

    echo ""
    echo -e "${CYAN}TheaterNAS Control Center Updater${NC}"
    echo ""

    check_root

    if [[ ! -d "${INSTALL_DIR}" ]]; then
        log_error "Not installed. Run install.sh first."
        exit 1
    fi

    backup_config
    source_dir=$(get_source "${source_dir}")
    update_files "${source_dir}"
    restart_daemon

    local version="unknown"
    [[ -f "${INSTALL_DIR}/VERSION" ]] && version=$(tr -d '[:space:]' < "${INSTALL_DIR}/VERSION")

    echo ""
    log_ok "Updated to v${version}"
    echo ""
}

main "$@"
