#!/usr/bin/env bash
# =============================================================================
# validate.sh - Syntax-check TheaterNAS Control Center scripts
# Run before install or commit: ./validate.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

errors=0
checked=0
missing_optional=0

check_file() {
    local file="$1"
    local required="${2:-1}"

    if [[ ! -f "${file}" ]]; then
        if [[ "${required}" == "1" ]]; then
            echo "MISSING (required): ${file}"
            errors=$((errors + 1))
        else
            echo "SKIP ${file} (optional, not installed)"
            missing_optional=$((missing_optional + 1))
        fi
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

# Required on an installed system
for f in main-menu install.sh update.sh uninstall.sh validate.sh; do
    check_file "${f}" 1
done

# Optional repo/distribution scripts (not required under /opt)
for f in remote-install.sh fix-update.sh; do
    check_file "${f}" 0
done

for f in modules/*.sh; do
    if [[ -f "${f}" ]]; then
        check_file "${f}" 1
    fi
done

echo ""
if (( errors > 0 )); then
    echo "FAILED: ${errors} error(s) in ${checked} file(s)"
    exit 1
fi

echo "PASSED: ${checked} file(s)"
exit 0
