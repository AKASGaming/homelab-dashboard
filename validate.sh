#!/usr/bin/env bash
# =============================================================================
# validate.sh - Syntax-check all TheaterNAS Control Center scripts
# Run before install or commit: ./validate.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

errors=0
checked=0

check_file() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
        echo "MISSING: ${file}"
        errors=$((errors + 1))
        return
    fi
    if bash -n "${file}" 2>/tmp/homelab-validate.err; then
        echo "OK  ${file}"
    else
        echo "FAIL ${file}"
        sed 's/^/    /' /tmp/homelab-validate.err
        errors=$((errors + 1))
    fi
    checked=$((checked + 1))
}

echo "TheaterNAS Control Center - validation"
echo ""

for f in main-menu install.sh update.sh uninstall.sh remote-install.sh validate.sh; do
    check_file "${f}"
done

for f in modules/*.sh; do
    [[ -f "${f}" ]] && check_file "${f}"
done

echo ""
if (( errors > 0 )); then
    echo "FAILED: ${errors} error(s) in ${checked} file(s)"
    exit 1
fi

echo "PASSED: ${checked} file(s)"
exit 0
