#!/usr/bin/env bash
set -euo pipefail

AKUO_APP_PATH="${1:-}"
AKUO_MANIFEST_PATH="${2:-}"
AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_VERIFY_TMP=""

akuo_cleanup_manifest_verification() {
    if [[ -n "$AKUO_VERIFY_TMP" && -d "$AKUO_VERIFY_TMP" ]]; then
        rm -rf -- "$AKUO_VERIFY_TMP"
    fi
}
trap akuo_cleanup_manifest_verification EXIT

if [[ "$#" -ne 2 || ! -d "$AKUO_APP_PATH" || ! -f "$AKUO_MANIFEST_PATH" ]]; then
    echo "usage: $0 APP_PATH MANIFEST_PATH" >&2
    exit 2
fi

AKUO_FIRST_JSON_CHARACTER="$(
    LC_ALL=C tr -d '[:space:]' <"$AKUO_MANIFEST_PATH" | cut -c1
)"
if [[ "$AKUO_FIRST_JSON_CHARACTER" != "{" ]]; then
    echo "build manifest must be a JSON object" >&2
    exit 1
fi

AKUO_VERIFY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-build-manifest-verify.XXXXXX")"
AKUO_MANIFEST_XML="$AKUO_VERIFY_TMP/manifest.xml"
if ! plutil -convert xml1 -o "$AKUO_MANIFEST_XML" "$AKUO_MANIFEST_PATH"; then
    echo "build manifest is not valid JSON property-list data" >&2
    exit 1
fi

AKUO_EXPECTED_KEYS=$'CFBundleIdentifier\nCFBundleShortVersionString\nCFBundleVersion\nbundleContentSHA256\ndesignatedRequirement\nexecutableSHA256\ngitHead\nschemaVersion\nsourceState\nswiftVersion\nxcodeVersion'
AKUO_ACTUAL_KEYS="$(
    sed -n 's/^[[:space:]]*<key>\([^<]*\)<\/key>[[:space:]]*$/\1/p' \
        "$AKUO_MANIFEST_XML" |
        LC_ALL=C sort
)"
if [[ "$AKUO_ACTUAL_KEYS" != "$AKUO_EXPECTED_KEYS" ]]; then
    echo "manifest keys do not exactly match schema" >&2
    exit 1
fi

akuo_require_manifest_type() {
    local key="$1"
    local expected_type="$2"
    local actual_type

    actual_type="$(plutil -type "$key" "$AKUO_MANIFEST_PATH" 2>/dev/null || true)"
    if [[ "$actual_type" != "$expected_type" ]]; then
        printf 'manifest field %s must have type %s\n' \
            "$key" "$expected_type" >&2
        exit 1
    fi
}

akuo_manifest_string() {
    local key="$1"
    local value

    akuo_require_manifest_type "$key" string
    value="$(plutil -extract "$key" raw -o - "$AKUO_MANIFEST_PATH")"
    if [[ -z "$value" ]]; then
        printf 'manifest field %s must not be empty\n' "$key" >&2
        exit 1
    fi
    printf '%s' "$value"
}

akuo_require_manifest_type schemaVersion integer
AKUO_SCHEMA_VERSION="$(plutil -extract schemaVersion raw -o - "$AKUO_MANIFEST_PATH")"
if [[ "$AKUO_SCHEMA_VERSION" != 1 ]]; then
    echo "unsupported build manifest schema version" >&2
    exit 1
fi

AKUO_SOURCE_REVISION="$(akuo_manifest_string gitHead)"
AKUO_SOURCE_STATE="$(akuo_manifest_string sourceState)"
akuo_manifest_string swiftVersion >/dev/null
akuo_manifest_string xcodeVersion >/dev/null
AKUO_BUNDLE_IDENTIFIER="$(akuo_manifest_string CFBundleIdentifier)"
AKUO_BUNDLE_SHORT_VERSION="$(akuo_manifest_string CFBundleShortVersionString)"
AKUO_BUNDLE_VERSION="$(akuo_manifest_string CFBundleVersion)"
AKUO_DESIGNATED_REQUIREMENT="$(akuo_manifest_string designatedRequirement)"
AKUO_EXECUTABLE_SHA256="$(akuo_manifest_string executableSHA256)"
AKUO_BUNDLE_CONTENT_SHA256="$(akuo_manifest_string bundleContentSHA256)"

if [[ ! "$AKUO_SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
    echo "manifest gitHead is malformed" >&2
    exit 1
fi
if [[ "$AKUO_SOURCE_STATE" != clean && "$AKUO_SOURCE_STATE" != dirty ]]; then
    echo "manifest sourceState must be clean or dirty" >&2
    exit 1
fi
if [[ ! "$AKUO_EXECUTABLE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "manifest executableSHA256 is malformed" >&2
    exit 1
fi
if [[ ! "$AKUO_BUNDLE_CONTENT_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "manifest bundleContentSHA256 is malformed" >&2
    exit 1
fi
if [[ "$AKUO_DESIGNATED_REQUIREMENT" != designated\ =\>* ]]; then
    echo "manifest designatedRequirement is malformed" >&2
    exit 1
fi

AKUO_INFO_PLIST="$AKUO_APP_PATH/Contents/Info.plist"
if [[ ! -f "$AKUO_INFO_PLIST" ]]; then
    echo "bundle Info.plist is missing" >&2
    exit 1
fi

akuo_compare_plist_string() {
    local manifest_name="$1"
    local plist_name="$2"
    local expected_value="$3"
    local actual_type
    local actual_value

    actual_type="$(plutil -type "$plist_name" "$AKUO_INFO_PLIST" 2>/dev/null || true)"
    if [[ "$actual_type" != string ]]; then
        printf 'bundle metadata %s must have type string\n' "$plist_name" >&2
        exit 1
    fi
    actual_value="$(plutil -extract "$plist_name" raw -o - "$AKUO_INFO_PLIST")"
    if [[ "$actual_value" != "$expected_value" ]]; then
        printf '%s does not match bundle metadata\n' "$manifest_name" >&2
        exit 1
    fi
}

akuo_compare_plist_string CFBundleIdentifier CFBundleIdentifier "$AKUO_BUNDLE_IDENTIFIER"
akuo_compare_plist_string CFBundleShortVersionString CFBundleShortVersionString \
    "$AKUO_BUNDLE_SHORT_VERSION"
akuo_compare_plist_string CFBundleVersion CFBundleVersion "$AKUO_BUNDLE_VERSION"
akuo_compare_plist_string gitHead AkuoSourceRevision "$AKUO_SOURCE_REVISION"

AKUO_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$AKUO_INFO_PLIST")"
AKUO_EXECUTABLE_PATH="$AKUO_APP_PATH/Contents/MacOS/$AKUO_EXECUTABLE_NAME"
if [[ ! -f "$AKUO_EXECUTABLE_PATH" || -L "$AKUO_EXECUTABLE_PATH" ]]; then
    echo "bundle executable is missing or not a regular file" >&2
    exit 1
fi

AKUO_REQUIREMENT_OUTPUT="$(codesign -d -r- "$AKUO_APP_PATH" 2>&1)"
AKUO_ACTUAL_DESIGNATED_REQUIREMENT="$(
    awk '{ sub(/^# /, "") } /^designated => / { print; exit }' \
        <<<"$AKUO_REQUIREMENT_OUTPUT"
)"
if [[ -z "$AKUO_ACTUAL_DESIGNATED_REQUIREMENT" ]]; then
    echo "bundle signature has no designated requirement" >&2
    exit 1
fi
if [[ "$AKUO_ACTUAL_DESIGNATED_REQUIREMENT" != "$AKUO_DESIGNATED_REQUIREMENT" ]]; then
    echo "designatedRequirement does not match bundle signature" >&2
    exit 1
fi

AKUO_ACTUAL_EXECUTABLE_SHA256="$(
    shasum -a 256 "$AKUO_EXECUTABLE_PATH" | awk '{ print $1 }'
)"
if [[ "$AKUO_ACTUAL_EXECUTABLE_SHA256" != "$AKUO_EXECUTABLE_SHA256" ]]; then
    echo "executable SHA-256 does not match manifest" >&2
    exit 1
fi

AKUO_ACTUAL_BUNDLE_CONTENT_SHA256="$(
    "$AKUO_PROJECT_ROOT/Scripts/lib/bundle-content-digest.sh" "$AKUO_APP_PATH"
)"
if [[ "$AKUO_ACTUAL_BUNDLE_CONTENT_SHA256" != "$AKUO_BUNDLE_CONTENT_SHA256" ]]; then
    echo "bundle content SHA-256 does not match manifest" >&2
    exit 1
fi

printf 'Verified Akuo build manifest schema %s\n' "$AKUO_SCHEMA_VERSION"
printf 'Source: %s (%s)\n' "$AKUO_SOURCE_REVISION" "$AKUO_SOURCE_STATE"
printf 'Executable SHA-256: %s\n' "$AKUO_EXECUTABLE_SHA256"
printf 'Bundle content SHA-256: %s\n' "$AKUO_BUNDLE_CONTENT_SHA256"
