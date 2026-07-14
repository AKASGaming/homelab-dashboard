#!/usr/bin/env bash
# =============================================================================
# uninstall.sh - TheaterNAS Control Center uninstaller
# Run as root: sudo uninstall-dashboard
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/homelab-dashboard"
SERVICE_NAME="homelab-dashboard-cache"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

confirm() {
    local prompt="$1"
    read -r -p "${prompt} [y/N] " response
    [[ "${response}" =~ ^[Yy]$ ]]
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Must run as root (sudo uninstall-dashboard)" >&2
        exit 1
    fi
}

stop_service() {
    if systemctl is-active --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        log_info "Stopping cache daemon..."
        systemctl stop "${SERVICE_NAME}.service"
        systemctl disable "${SERVICE_NAME}.service"
        log_ok "Service stopped and disabled"
    fi

    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
        log_ok "Service file removed"
    fi
}

remove_launchers() {
    local launchers=(/usr/local/bin/main-menu /usr/local/bin/update-dashboard /usr/local/bin/uninstall-dashboard)
    for launcher in "${launchers[@]}"; do
        if [[ -f "${launcher}" ]]; then
            rm -f "${launcher}"
            log_ok "Removed ${launcher}"
        fi
    done
}

remove_installation() {
    local keep_config="${1:-false}"

    if [[ ! -d "${INSTALL_DIR}" ]]; then
        log_warn "Installation directory not found"
        return
    fi

    if [[ "${keep_config}" == "true" ]]; then
        local config_backup="/etc/homelab-dashboard-config.conf.removed"
        if [[ -f "${INSTALL_DIR}/config/config.conf" ]]; then
            cp -a "${INSTALL_DIR}/config/config.conf" "${config_backup}"
            log_ok "Config saved to ${config_backup}"
        fi
    fi

    rm -rf "${INSTALL_DIR}"
    log_ok "Removed ${INSTALL_DIR}"
}

main() {
    echo ""
    echo -e "${YELLOW}TheaterNAS Control Center Uninstaller${NC}"
    echo ""

    check_root

    if ! confirm "Remove TheaterNAS Control Center?"; then
        echo "Cancelled."
        exit 0
    fi

    local keep_config=false
    if confirm "Keep configuration file backup?"; then
        keep_config=true
    fi

    stop_service
    remove_launchers
    remove_installation "${keep_config}"

    echo ""
    log_ok "Uninstall complete"
    echo ""
}

main "$@"
