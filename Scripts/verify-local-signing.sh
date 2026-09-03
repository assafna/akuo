#!/usr/bin/env bash
set -euo pipefail

AKUO_EXPECTED_BUNDLE_ID="app.akuo.Akuo"
AKUO_APP_PATH="${1:-}"
AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Resolved from this script's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/signing-policy.sh"

if [[ "$#" -ne 1 || ! -d "$AKUO_APP_PATH" ]]; then
    echo "usage: $0 APP_PATH" >&2
    exit 2
fi

if ! codesign --verify --deep --strict "$AKUO_APP_PATH"; then
    echo "refusing local install: app does not have a valid strict code signature" >&2
    exit 1
fi

AKUO_ACTUAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$AKUO_APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$AKUO_ACTUAL_BUNDLE_ID" != "$AKUO_EXPECTED_BUNDLE_ID" ]]; then
    printf 'refusing local install: expected bundle identifier %s, got %s\n' \
        "$AKUO_EXPECTED_BUNDLE_ID" "${AKUO_ACTUAL_BUNDLE_ID:-<missing>}" >&2
    exit 1
fi

AKUO_SIGNING_DETAILS="$(codesign -d --verbose=4 "$AKUO_APP_PATH" 2>&1)"
if grep -q '^Signature=adhoc$' <<<"$AKUO_SIGNING_DETAILS"; then
    echo "refusing local install: ad-hoc signature has a build-specific identity" >&2
    exit 1
fi

AKUO_TEAM_ID="$(sed -n 's/^TeamIdentifier=//p' <<<"$AKUO_SIGNING_DETAILS")"
if [[ -z "$AKUO_TEAM_ID" || "$AKUO_TEAM_ID" == "not set" ]]; then
    echo "refusing local install: signature has no Apple developer team identifier" >&2
    exit 1
fi
if [[ ! "$AKUO_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "refusing local install: signature has a malformed Apple developer team identifier" >&2
    exit 1
fi

AKUO_REQUIREMENT_OUTPUT="$(codesign -d -r- "$AKUO_APP_PATH" 2>&1)"
AKUO_DESIGNATED_REQUIREMENT="$(awk '{ sub(/^# /, "") } /^designated => / { print; exit }' <<<"$AKUO_REQUIREMENT_OUTPUT")"
if [[ -z "$AKUO_DESIGNATED_REQUIREMENT" ]]; then
    echo "refusing local install: signature has no designated requirement" >&2
    exit 1
fi
if ! akuo_requirement_matches_policy "$AKUO_DESIGNATED_REQUIREMENT" "$AKUO_TEAM_ID"; then
    echo "refusing local install: designated requirement does not match Akuo's repository-controlled signing policy" >&2
    exit 1
fi

AKUO_TRUST_REQUIREMENT="=anchor apple generic and identifier \"$AKUO_EXPECTED_BUNDLE_ID\" and certificate leaf[subject.OU] = \"$AKUO_TEAM_ID\""
if ! codesign --verify --deep --strict -R "$AKUO_TRUST_REQUIREMENT" "$AKUO_APP_PATH"; then
    echo "refusing local install: signature is not Apple-anchored to its reported developer team" >&2
    exit 1
fi

printf 'Verified stable Akuo signing identity (team %s)\n' "$AKUO_TEAM_ID"
printf '%s\n' "$AKUO_DESIGNATED_REQUIREMENT"
