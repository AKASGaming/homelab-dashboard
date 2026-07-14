#!/usr/bin/env bash
# =============================================================================
# remote-install.sh - One-line installer for TheaterNAS Control Center
# Usage: curl -fsSL https://raw.githubusercontent.com/AKASGaming/homelab-dashboard/main/remote-install.sh | sudo bash
#    or: sudo bash remote-install.sh
# =============================================================================

set -euo pipefail

REPO_URL="${HOMELAB_REPO_URL:-https://github.com/AKASGaming/homelab-dashboard.git}"
BRANCH="${HOMELAB_BRANCH:-main}"
INSTALL_TMP=""

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
    [[ -n "${INSTALL_TMP}" && -d "${INSTALL_TMP}" ]] && rm -rf "${INSTALL_TMP}"
}
trap cleanup EXIT

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║       TheaterNAS Control Center - Remote Installer       ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${RED}Please run as root: sudo bash remote-install.sh${NC}" >&2
    exit 1
fi

# Install git if needed
if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    apt-get update -qq
    apt-get install -y -qq git
fi

INSTALL_TMP=$(mktemp -d)
echo "Cloning repository..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_TMP}"

echo "Running installer..."
bash "${INSTALL_TMP}/install.sh"

echo -e "${GREEN}Installation complete! Run: main-menu${NC}"
