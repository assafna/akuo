#!/usr/bin/env bash
set -euo pipefail

AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_BUILD_CONFIGURATION="${1:-}"
AKUO_CODE_SIGN_IDENTITY="${AKUO_CODE_SIGN_IDENTITY:--}"

# Resolved from this script's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/signing-policy.sh"
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/candidate-version.sh"

if [[ "$#" -ne 1 || ( "$AKUO_BUILD_CONFIGURATION" != "debug" && "$AKUO_BUILD_CONFIGURATION" != "release" ) ]]; then
    echo "usage: $0 [debug|release]" >&2
    exit 2
fi

AKUO_APP_PATH="$AKUO_PROJECT_ROOT/dist/Akuo.app"
AKUO_EXECUTABLE_PATH="$AKUO_APP_PATH/Contents/MacOS/Akuo"
AKUO_VERSION_SOURCE="$AKUO_PROJECT_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift"
AKUO_INFO_PLIST="$AKUO_PROJECT_ROOT/Configuration/Akuo-Info.plist"

cd "$AKUO_PROJECT_ROOT"
akuo_read_candidate_identity "$AKUO_VERSION_SOURCE"
plutil -lint "$AKUO_INFO_PLIST"
akuo_assert_versionless_template "$AKUO_INFO_PLIST"
akuo_validate_candidate_history "$AKUO_PROJECT_ROOT"
swift build -c "$AKUO_BUILD_CONFIGURATION" --product Akuo
AKUO_BIN_DIR="$(swift build -c "$AKUO_BUILD_CONFIGURATION" --show-bin-path)"

# This is deliberately the only path packaging removes. Other files under dist/
# may be release evidence or artifacts owned by another build.
if [[ "$AKUO_APP_PATH" != "$AKUO_PROJECT_ROOT/dist/Akuo.app" ]]; then
    echo "refusing to remove unexpected app path: $AKUO_APP_PATH" >&2
    exit 1
fi
rm -rf -- "$AKUO_APP_PATH"
mkdir -p -- "$AKUO_APP_PATH/Contents/MacOS" "$AKUO_APP_PATH/Contents/Resources"

cp "$AKUO_INFO_PLIST" "$AKUO_APP_PATH/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$AKUO_CANDIDATE_VERSION" \
    "$AKUO_APP_PATH/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$AKUO_CANDIDATE_BUILD" \
    "$AKUO_APP_PATH/Contents/Info.plist"
plutil -lint "$AKUO_APP_PATH/Contents/Info.plist"
cp "$AKUO_BIN_DIR/Akuo" "$AKUO_EXECUTABLE_PATH"
chmod 755 "$AKUO_EXECUTABLE_PATH"
akuo_verify_candidate_plist "$AKUO_APP_PATH/Contents/Info.plist"
akuo_verify_runtime_identity "$AKUO_EXECUTABLE_PATH"

if [[ "$AKUO_CODE_SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$AKUO_APP_PATH"
else
    # Sign once to let codesign resolve the certificate and expose its team ID,
    # then replace that signature with Akuo's stable, repository-controlled DR.
    codesign --force --deep --sign "$AKUO_CODE_SIGN_IDENTITY" "$AKUO_APP_PATH"
    AKUO_SIGNING_DETAILS="$(codesign -d --verbose=4 "$AKUO_APP_PATH" 2>&1)"
    AKUO_TEAM_ID="$(sed -n 's/^TeamIdentifier=//p' <<<"$AKUO_SIGNING_DETAILS")"
    if [[ ! "$AKUO_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "selected signing identity has no valid Apple developer team identifier" >&2
        exit 1
    fi
    AKUO_DESIGNATED_REQUIREMENT="$(akuo_expected_designated_requirement "$AKUO_TEAM_ID")"
    codesign --force --deep --sign "$AKUO_CODE_SIGN_IDENTITY" \
        -r "=$AKUO_DESIGNATED_REQUIREMENT" "$AKUO_APP_PATH"
fi
codesign --verify --deep --strict "$AKUO_APP_PATH"

AKUO_EXECUTABLE_SHA256="$(shasum -a 256 "$AKUO_EXECUTABLE_PATH" | awk '{print $1}')"
printf 'Akuo executable SHA-256: %s\n' "$AKUO_EXECUTABLE_SHA256"
printf 'Bundle: %s\n' "$AKUO_APP_PATH"
if [[ "$AKUO_CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "Signing: ad-hoc (not eligible for persistent Accessibility permission)"
else
    printf 'Signing identity: %s\n' "$AKUO_CODE_SIGN_IDENTITY"
fi
codesign -d -r- "$AKUO_APP_PATH" 2>&1
