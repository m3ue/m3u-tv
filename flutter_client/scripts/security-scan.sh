#!/usr/bin/env bash
# Check dependencies for known vulnerabilities, like `composer security:scan` in the editor.
# Scans the same lockfiles as CI (.github/actions/security-scan, used by ci.yml and
# release.yml's validate gate): pubspec.lock and the iOS, macOS and tvOS Package.resolved files.
# Usage (from flutter_client/):
#   ./scripts/security-scan.sh

set -euo pipefail

FLUTTER_CLIENT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(dirname "$FLUTTER_CLIENT")"
ACTION_FILE="$REPO_ROOT/.github/actions/security-scan/action.yml"

if ! command -v osv-scanner &>/dev/null; then
    echo "osv-scanner not found. Install it with: brew install osv-scanner"
    exit 1
fi

# CI pins osv-scanner, and newer versions can read more lockfile types. Warn on a mismatch.
CI_VERSION="$(sed -n 's/.*osv-scanner-action@[0-9a-f]* # v\([0-9.]*\).*/\1/p' "$ACTION_FILE" | head -n 1)"
LOCAL_VERSION="$(osv-scanner --version | sed -n 's/.*version: *\([0-9.]*\).*/\1/p' | head -n 1)"
if [[ -n "$CI_VERSION" && -n "$LOCAL_VERSION" && "$LOCAL_VERSION" != "$CI_VERSION" ]]; then
    echo "Warning: using osv-scanner $LOCAL_VERSION, CI uses $CI_VERSION."
fi

# Same arguments as the CI action, run from the repo root like CI.
cd "$REPO_ROOT"
echo "Scanning flutter_client dependencies..."
osv-scanner scan source --recursive flutter_client

echo "Done."
