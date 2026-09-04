#!/usr/bin/env bash
set -euo pipefail

AKUO_APP_PATH="${1:-}"
AKUO_MANIFEST_PATH="${2:-}"
AKUO_SOURCE_REVISION="${3:-}"
AKUO_SOURCE_STATE="${4:-}"
AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_MANIFEST_TMP=""
AKUO_PLIST_TMP=""

akuo_cleanup_manifest_generation() {
    [[ -z "$AKUO_MANIFEST_TMP" ]] || rm -f -- "$AKUO_MANIFEST_TMP"
    [[ -z "$AKUO_PLIST_TMP" ]] || rm -f -- "$AKUO_PLIST_TMP"
}
trap akuo_cleanup_manifest_generation EXIT

if [[ "$#" -ne 4 || ! -d "$AKUO_APP_PATH" ]]; then
    echo "usage: $0 APP_PATH MANIFEST_PATH SOURCE_REVISION SOURCE_STATE" >&2
    exit 2
fi
if [[ ! "$AKUO_SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
    echo "refusing build manifest: malformed source revision" >&2
    exit 1
fi
if [[ "$AKUO_SOURCE_STATE" != clean && "$AKUO_SOURCE_STATE" != dirty ]]; then
    echo "refusing build manifest: source state must be clean or dirty" >&2
    exit 1
fi

AKUO_INFO_PLIST="$AKUO_APP_PATH/Contents/Info.plist"
if [[ ! -f "$AKUO_INFO_PLIST" ]]; then
    echo "refusing build manifest: bundle Info.plist is missing" >&2
    exit 1
fi

akuo_read_plist_string() {
    local key="$1"
    local value

    if [[ "$(plutil -type "$key" "$AKUO_INFO_PLIST" 2>/dev/null || true)" != string ]]; then
        printf 'refusing build manifest: bundle field %s must be a string\n' \
            "$key" >&2
        exit 1
    fi
    value="$(plutil -extract "$key" raw -o - "$AKUO_INFO_PLIST")"
    if [[ -z "$value" ]]; then
        printf 'refusing build manifest: bundle field %s must not be empty\n' \
            "$key" >&2
        exit 1
    fi
    printf '%s' "$value"
}

AKUO_EXECUTABLE_NAME="$(akuo_read_plist_string CFBundleExecutable)"
AKUO_BUNDLE_IDENTIFIER="$(akuo_read_plist_string CFBundleIdentifier)"
AKUO_BUNDLE_SHORT_VERSION="$(akuo_read_plist_string CFBundleShortVersionString)"
AKUO_BUNDLE_VERSION="$(akuo_read_plist_string CFBundleVersion)"
AKUO_BUNDLE_SOURCE_REVISION="$(akuo_read_plist_string AkuoSourceRevision)"
if [[ "$AKUO_BUNDLE_SOURCE_REVISION" != "$AKUO_SOURCE_REVISION" ]]; then
    echo "refusing build manifest: source revision does not match bundle metadata" >&2
    exit 1
fi

AKUO_EXECUTABLE_PATH="$AKUO_APP_PATH/Contents/MacOS/$AKUO_EXECUTABLE_NAME"
if [[ ! -f "$AKUO_EXECUTABLE_PATH" || -L "$AKUO_EXECUTABLE_PATH" ]]; then
    echo "refusing build manifest: bundle executable is missing or not a regular file" >&2
    exit 1
fi

if ! codesign --verify --deep --strict "$AKUO_APP_PATH"; then
    echo "refusing build manifest: bundle failed strict code-signature verification" >&2
    exit 1
fi
AKUO_REQUIREMENT_OUTPUT="$(codesign -d -r- "$AKUO_APP_PATH" 2>&1)"
AKUO_DESIGNATED_REQUIREMENT="$(
    awk '{ sub(/^# /, "") } /^designated => / { print; exit }' \
        <<<"$AKUO_REQUIREMENT_OUTPUT"
)"
if [[ -z "$AKUO_DESIGNATED_REQUIREMENT" ]]; then
    echo "refusing build manifest: signature has no designated requirement" >&2
    exit 1
fi

AKUO_SWIFT_VERSION="$(swift --version 2>&1)"
AKUO_XCODE_VERSION="$(xcodebuild -version 2>&1)"
if [[ -z "$AKUO_SWIFT_VERSION" || -z "$AKUO_XCODE_VERSION" ]]; then
    echo "refusing build manifest: toolchain version output is empty" >&2
    exit 1
fi

AKUO_EXECUTABLE_SHA256="$(shasum -a 256 "$AKUO_EXECUTABLE_PATH" | awk '{ print $1 }')"
AKUO_BUNDLE_CONTENT_SHA256="$(
    "$AKUO_PROJECT_ROOT/Scripts/lib/bundle-content-digest.sh" "$AKUO_APP_PATH"
)"

mkdir -p -- "$(dirname -- "$AKUO_MANIFEST_PATH")"
AKUO_PLIST_TMP="$(mktemp "${TMPDIR:-/tmp}/akuo-build-manifest.XXXXXX")"
AKUO_MANIFEST_TMP="$(mktemp "$(dirname -- "$AKUO_MANIFEST_PATH")/.akuo-build-manifest.XXXXXX")"
plutil -create xml1 "$AKUO_PLIST_TMP"
plutil -insert schemaVersion -integer 1 "$AKUO_PLIST_TMP"
plutil -insert gitHead -string "$AKUO_SOURCE_REVISION" "$AKUO_PLIST_TMP"
plutil -insert sourceState -string "$AKUO_SOURCE_STATE" "$AKUO_PLIST_TMP"
plutil -insert swiftVersion -string "$AKUO_SWIFT_VERSION" "$AKUO_PLIST_TMP"
plutil -insert xcodeVersion -string "$AKUO_XCODE_VERSION" "$AKUO_PLIST_TMP"
plutil -insert CFBundleIdentifier -string "$AKUO_BUNDLE_IDENTIFIER" "$AKUO_PLIST_TMP"
plutil -insert CFBundleShortVersionString -string "$AKUO_BUNDLE_SHORT_VERSION" "$AKUO_PLIST_TMP"
plutil -insert CFBundleVersion -string "$AKUO_BUNDLE_VERSION" "$AKUO_PLIST_TMP"
plutil -insert designatedRequirement -string "$AKUO_DESIGNATED_REQUIREMENT" "$AKUO_PLIST_TMP"
plutil -insert executableSHA256 -string "$AKUO_EXECUTABLE_SHA256" "$AKUO_PLIST_TMP"
plutil -insert bundleContentSHA256 -string "$AKUO_BUNDLE_CONTENT_SHA256" "$AKUO_PLIST_TMP"
plutil -convert json -o "$AKUO_MANIFEST_TMP" "$AKUO_PLIST_TMP"
chmod 644 "$AKUO_MANIFEST_TMP"
mv -f -- "$AKUO_MANIFEST_TMP" "$AKUO_MANIFEST_PATH"
AKUO_MANIFEST_TMP=""

printf 'Build manifest: %s\n' "$AKUO_MANIFEST_PATH"
