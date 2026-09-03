#!/usr/bin/env bash
set -euo pipefail

AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_APP_PATH="${1:-}"
AKUO_VERIFY_SNAPSHOT_ROOT=""

akuo_cleanup_verify_snapshot() {
    if [[ -n "$AKUO_VERIFY_SNAPSHOT_ROOT" && -d "$AKUO_VERIFY_SNAPSHOT_ROOT" ]]; then
        rm -rf -- "$AKUO_VERIFY_SNAPSHOT_ROOT"
    fi
}
trap akuo_cleanup_verify_snapshot EXIT

# Resolved from this script's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/candidate-version.sh"

if [[ "$#" -ne 1 || ! -d "$AKUO_APP_PATH" ]]; then
    echo "usage: $0 /path/to/Akuo.app" >&2
    exit 2
fi

AKUO_CANDIDATE_PLIST="$AKUO_APP_PATH/Contents/Info.plist"
AKUO_CANDIDATE_EXECUTABLE="$AKUO_APP_PATH/Contents/MacOS/Akuo"

akuo_capture_clean_source_revision "$AKUO_PROJECT_ROOT"
akuo_assert_safe_archive_entries "$AKUO_PROJECT_ROOT" "$AKUO_SOURCE_REVISION"
AKUO_VERIFY_SNAPSHOT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/akuo-verify-snapshot.XXXXXX")"
git -C "$AKUO_PROJECT_ROOT" archive --format=tar "$AKUO_SOURCE_REVISION" | \
    tar -xf - -C "$AKUO_VERIFY_SNAPSHOT_ROOT"
AKUO_VERSION_SOURCE="$AKUO_VERIFY_SNAPSHOT_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift"
AKUO_INFO_TEMPLATE="$AKUO_VERIFY_SNAPSHOT_ROOT/Configuration/Akuo-Info.plist"
akuo_read_candidate_identity "$AKUO_VERSION_SOURCE"
akuo_validate_candidate_history "$AKUO_PROJECT_ROOT"
plutil -lint "$AKUO_INFO_TEMPLATE"
akuo_assert_versionless_template "$AKUO_INFO_TEMPLATE"
plutil -lint "$AKUO_CANDIDATE_PLIST"
akuo_verify_candidate_plist "$AKUO_CANDIDATE_PLIST"
akuo_verify_candidate_source_revision "$AKUO_CANDIDATE_PLIST"
akuo_verify_runtime_identity "$AKUO_CANDIDATE_EXECUTABLE"
akuo_verify_runtime_source_revision "$AKUO_CANDIDATE_EXECUTABLE"

printf 'Candidate identity: %s (%s)\n' \
    "$AKUO_CANDIDATE_VERSION" "$AKUO_CANDIDATE_BUILD"
