#!/bin/zsh
set -euo pipefail

xcodebuild -downloadComponent MetalToolchain 2>/dev/null || true

if [[ -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_ID:-}" || -z "${ASC_PRIVATE_KEY:-}" ]]; then
  echo "Missing ASC_ISSUER_ID, ASC_KEY_ID, or ASC_PRIVATE_KEY." >&2
  echo "Set them as Xcode Cloud environment variables." >&2
  exit 1
fi

APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.jtr.RockYou}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NEXT_BUILD_NUMBER="$("${SCRIPT_DIR}/asc_next_build_number.swift" "${APP_BUNDLE_ID}")"

if [[ -z "${NEXT_BUILD_NUMBER}" || ! "${NEXT_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Failed to compute a numeric build number." >&2
  exit 1
fi

export CURRENT_PROJECT_VERSION="${NEXT_BUILD_NUMBER}"
echo "Setting CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION}"
