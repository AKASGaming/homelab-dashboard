#!/usr/bin/env bash
# =============================================================================
# install.sh - TheaterNAS Control Center installer
# Run as root: sudo ./install.sh
# =============================================================================

set -euo pipefail

INSTALL_DIR="/opt/homelab-dashboard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="homelab-dashboard-cache"
VERSION_FILE="${SCRIPT_DIR}/VERSION"

# Colors for installer output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Pre-flight checks
# =============================================================================

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This installer must be run as root (sudo ./install.sh)"
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    local deps=(bash jq curl ip awk sed grep systemctl)

    for dep in "${deps[@]}"; do
        command -v "${dep}" >/dev/null 2>&1 || missing+=("${dep}")
    done

    if (( ${#missing[@]} > 0 )); then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Installing dependencies..."
        apt-get update -qq
        apt-get install -y -qq jq curl iproute2 gawk sed grep systemd 2>/dev/null || {
            log_error "Failed to install dependencies. Install manually: ${missing[*]}"
            exit 1
        }
    fi
    log_ok "Dependencies satisfied"
}

# =============================================================================
# Backup existing installation
# =============================================================================

backup_existing() {
    if [[ -d "${INSTALL_DIR}" ]]; then
        local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        log_warn "Existing installation detected"
        if [[ -f "${INSTALL_DIR}/config/config.conf" ]]; then
            cp -a "${INSTALL_DIR}/config/config.conf" "/tmp/homelab-dashboard-config.conf.bak"
            log_ok "Config backed up to /tmp/homelab-dashboard-config.conf.bak"
        fi
        mv "${INSTALL_DIR}" "${backup_dir}"
        log_ok "Previous installation backed up to ${backup_dir}"
    fi
}

# =============================================================================
# Install files
# =============================================================================

install_files() {
    log_info "Installing to ${INSTALL_DIR}..."

    mkdir -p "${INSTALL_DIR}"/{config,cache,themes,assets,modules,systemd}

    # Copy all project files
    cp -a "${SCRIPT_DIR}/main-menu" "${INSTALL_DIR}/"
    cp -a "${SCRIPT_DIR}/VERSION" "${INSTALL_DIR}/"
    cp -a "${SCRIPT_DIR}/README.md" "${INSTALL_DIR}/" 2>/dev/null || true
    cp -a "${SCRIPT_DIR}/config/"* "${INSTALL_DIR}/config/" 2>/dev/null || true
    cp -a "${SCRIPT_DIR}/themes/"* "${INSTALL_DIR}/themes/"
    cp -a "${SCRIPT_DIR}/modules/"* "${INSTALL_DIR}/modules/"
    cp -a "${SCRIPT_DIR}/systemd/"* "${INSTALL_DIR}/systemd/"

    # Restore backed up config if exists
    if [[ -f "/tmp/homelab-dashboard-config.conf.bak" ]]; then
        cp -a "/tmp/homelab-dashboard-config.conf.bak" "${INSTALL_DIR}/config/config.conf"
        log_ok "Previous config restored"
    fi

    # Set permissions
    chmod +x "${INSTALL_DIR}/main-menu"
    chmod +x "${INSTALL_DIR}/modules/"*.sh
    chmod 755 "${INSTALL_DIR}"
    chmod 755 "${INSTALL_DIR}/cache"
    chmod 644 "${INSTALL_DIR}/config/config.conf"

    log_ok "Files installed"
}

# =============================================================================
# Create launchers
# =============================================================================

create_launchers() {
    log_info "Creating launchers..."

    cat > /usr/local/bin/main-menu <<'LAUNCHER'
#!/usr/bin/env bash
export HOMELAB_DASHBOARD_DIR="/opt/homelab-dashboard"
exec /opt/homelab-dashboard/main-menu "$@"
LAUNCHER
    chmod +x /usr/local/bin/main-menu

    cat > /usr/local/bin/update-dashboard <<'UPDATER'
#!/usr/bin/env bash
exec /opt/homelab-dashboard/update.sh "$@"
UPDATER
    chmod +x /usr/local/bin/update-dashboard

    cat > /usr/local/bin/uninstall-dashboard <<'UNINSTALLER'
#!/usr/bin/env bash
exec /opt/homelab-dashboard/uninstall.sh "$@"
UNINSTALLER
    chmod +x /usr/local/bin/uninstall-dashboard

    # Copy update/uninstall scripts to install dir
    cp -a "${SCRIPT_DIR}/update.sh" "${INSTALL_DIR}/"
    cp -a "${SCRIPT_DIR}/uninstall.sh" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/update.sh" "${INSTALL_DIR}/uninstall.sh"

    log_ok "Launchers created: main-menu, update-dashboard, uninstall-dashboard"
}

# =============================================================================
# Install systemd service
# =============================================================================

install_systemd() {
    log_info "Installing cache daemon service..."

    cp "${INSTALL_DIR}/systemd/homelab-dashboard-cache.service" \
        "/etc/systemd/system/${SERVICE_NAME}.service"

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"

    sleep 2
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log_ok "Cache daemon service running"
    else
        log_warn "Cache daemon may still be starting. Check: systemctl status ${SERVICE_NAME}"
    fi
}

# =============================================================================
# Post-install
# =============================================================================

post_install() {
    local version="unknown"
    [[ -f "${VERSION_FILE}" ]] && version=$(tr -d '[:space:]' < "${VERSION_FILE}")

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  TheaterNAS Control Center v${version} installed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Launch:    main-menu"
    echo "  Update:    update-dashboard"
    echo "  Remove:    uninstall-dashboard"
    echo "  Config:    ${INSTALL_DIR}/config/config.conf"
    echo "  Cache:     systemctl status ${SERVICE_NAME}"
    echo ""
    echo "  Edit ${INSTALL_DIR}/config/config.conf to set container names,"
    echo "  Pi-hole password, theme, and other settings."
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${CYAN}TheaterNAS Control Center Installer${NC}"
    echo ""

    check_root
    check_dependencies
    backup_existing
    install_files
    create_launchers
    install_systemd
    post_install
}

main "$@"
