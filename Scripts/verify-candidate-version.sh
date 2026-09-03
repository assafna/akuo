#!/usr/bin/env bash
set -euo pipefail

AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_APP_PATH="${1:-}"

# Resolved from this script's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/candidate-version.sh"

if [[ "$#" -ne 1 || ! -d "$AKUO_APP_PATH" ]]; then
    echo "usage: $0 /path/to/Akuo.app" >&2
    exit 2
fi

AKUO_VERSION_SOURCE="$AKUO_PROJECT_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift"
AKUO_INFO_TEMPLATE="$AKUO_PROJECT_ROOT/Configuration/Akuo-Info.plist"
AKUO_CANDIDATE_PLIST="$AKUO_APP_PATH/Contents/Info.plist"
AKUO_CANDIDATE_EXECUTABLE="$AKUO_APP_PATH/Contents/MacOS/Akuo"

akuo_capture_clean_source_revision "$AKUO_PROJECT_ROOT"
akuo_read_candidate_identity "$AKUO_VERSION_SOURCE"
akuo_validate_candidate_history "$AKUO_PROJECT_ROOT"
plutil -lint "$AKUO_INFO_TEMPLATE"
akuo_assert_versionless_template "$AKUO_INFO_TEMPLATE"
plutil -lint "$AKUO_CANDIDATE_PLIST"
akuo_verify_candidate_plist "$AKUO_CANDIDATE_PLIST"
akuo_verify_candidate_source_revision "$AKUO_CANDIDATE_PLIST"
akuo_verify_runtime_identity "$AKUO_CANDIDATE_EXECUTABLE"

printf 'Candidate identity: %s (%s)\n' \
    "$AKUO_CANDIDATE_VERSION" "$AKUO_CANDIDATE_BUILD"
