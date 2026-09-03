#!/usr/bin/env bash
set -euo pipefail

AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AKUO_CODE_SIGN_IDENTITY="${AKUO_CODE_SIGN_IDENTITY:-}"
AKUO_BUILD_CONFIGURATION=""
AKUO_CANDIDATE_PATH=""
AKUO_APPLICATIONS_PATH="/Applications"
# Packaging contract tests redirect the fixed installation target into a
# disposable root; normal installation always uses /Applications.
if [[ -n "${AKUO_INSTALLER_TEST_ROOT:-}" ]]; then
    AKUO_APPLICATIONS_PATH="$AKUO_INSTALLER_TEST_ROOT/Applications"
fi
AKUO_INSTALL_PATH="$AKUO_APPLICATIONS_PATH/Akuo.app"
AKUO_EXPECTED_BUNDLE_ID="app.akuo.Akuo"

# Resolved from this script's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_PROJECT_ROOT/Scripts/lib/install-safety.sh"

if [[ "$#" -eq 1 && ( "$1" == "debug" || "$1" == "release" ) ]]; then
    AKUO_BUILD_CONFIGURATION="$1"
    AKUO_CANDIDATE_PATH="$AKUO_PROJECT_ROOT/dist/Akuo.app"
elif [[ "$#" -eq 2 && "$1" == "--candidate" && -n "$2" ]]; then
    AKUO_CANDIDATE_PATH="$2"
else
    echo "usage: AKUO_CODE_SIGN_IDENTITY='Apple Development: Name (TEAMID)' $0 [debug|release]" >&2
    echo "       $0 --candidate /path/to/Akuo.app" >&2
    exit 2
fi

if [[ -n "$AKUO_BUILD_CONFIGURATION" ]]; then
    if [[ -z "$AKUO_CODE_SIGN_IDENTITY" ]]; then
        echo "local installation requires AKUO_CODE_SIGN_IDENTITY to name a persistent Apple signing certificate" >&2
        exit 2
    fi
    if [[ "$AKUO_CODE_SIGN_IDENTITY" == "-" ]]; then
        echo "local installation does not accept the ad-hoc identity '-'" >&2
        exit 2
    fi

    AKUO_CODE_SIGN_IDENTITY="$AKUO_CODE_SIGN_IDENTITY" \
        "$AKUO_PROJECT_ROOT/Scripts/build-app.sh" "$AKUO_BUILD_CONFIGURATION"
fi
"$AKUO_PROJECT_ROOT/Scripts/verify-local-signing.sh" "$AKUO_CANDIDATE_PATH"
AKUO_CANDIDATE_SHA256="$(shasum -a 256 "$AKUO_CANDIDATE_PATH/Contents/MacOS/Akuo" | awk '{print $1}')"

akuo_bundle_identifier() {
    plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

if [[ -L "$AKUO_INSTALL_PATH" || ( -e "$AKUO_INSTALL_PATH" && ! -d "$AKUO_INSTALL_PATH" ) ]]; then
    echo "refusing local install: $AKUO_INSTALL_PATH exists but is not an application directory" >&2
    exit 1
fi

AKUO_INSTALLED_STABLE=false
if [[ -d "$AKUO_INSTALL_PATH" ]]; then
    if "$AKUO_PROJECT_ROOT/Scripts/verify-local-signing.sh" "$AKUO_INSTALL_PATH" >/dev/null 2>&1; then
        AKUO_INSTALLED_STABLE=true
    else
        AKUO_INSTALLED_DETAILS="$(codesign -d --verbose=4 "$AKUO_INSTALL_PATH" 2>&1 || true)"
        AKUO_INSTALLED_BUNDLE_ID="$(akuo_bundle_identifier "$AKUO_INSTALL_PATH")"
        if ! codesign --verify --deep --strict "$AKUO_INSTALL_PATH" || \
            [[ "$AKUO_INSTALLED_BUNDLE_ID" != "$AKUO_EXPECTED_BUNDLE_ID" ]] || \
            ! grep -q '^Signature=adhoc$' <<<"$AKUO_INSTALLED_DETAILS"; then
            echo "refusing local install: existing Akuo has an invalid or unexpected identity" >&2
            exit 1
        fi
        echo "One-time migration: replacing the existing ad-hoc Akuo identity." >&2
        echo "Accessibility must be granted once after this installation." >&2
    fi
fi

if pgrep -f "^$AKUO_INSTALL_PATH/Contents/MacOS/Akuo([[:space:]]|$)" >/dev/null; then
    printf 'refusing local install: quit the running %s first\n' "$AKUO_INSTALL_PATH" >&2
    exit 1
fi

AKUO_STAGE_ROOT="$(mktemp -d "$AKUO_APPLICATIONS_PATH/.akuo-install.XXXXXX")"
AKUO_STAGE_APP="$AKUO_STAGE_ROOT/Akuo.app"
AKUO_BACKUP_APP=""
AKUO_REPLACEMENT_INSTALLED=false

akuo_cleanup() {
    local status=$?
    local preserve_recovery=false
    trap - EXIT
    if [[ "$status" -ne 0 && "$AKUO_REPLACEMENT_INSTALLED" == true ]]; then
        if ! rm -rf -- "$AKUO_INSTALL_PATH"; then
            preserve_recovery=true
        elif [[ -n "$AKUO_BACKUP_APP" && -d "$AKUO_BACKUP_APP" ]] && \
            ! akuo_restore_backup "$AKUO_BACKUP_APP" "$AKUO_INSTALL_PATH"; then
            preserve_recovery=true
        fi
    elif [[ "$status" -ne 0 && -n "$AKUO_BACKUP_APP" && -d "$AKUO_BACKUP_APP" && ! -e "$AKUO_INSTALL_PATH" ]]; then
        if ! akuo_restore_backup "$AKUO_BACKUP_APP" "$AKUO_INSTALL_PATH"; then
            preserve_recovery=true
        fi
    fi
    if [[ "$preserve_recovery" == true ]]; then
        printf 'Akuo recovery failed; backup preserved at %s\n' "$AKUO_BACKUP_APP" >&2
    else
        rm -rf -- "$AKUO_STAGE_ROOT"
    fi
    exit "$status"
}
trap akuo_cleanup EXIT

ditto "$AKUO_CANDIDATE_PATH" "$AKUO_STAGE_APP"
"$AKUO_PROJECT_ROOT/Scripts/verify-local-signing.sh" "$AKUO_STAGE_APP"
AKUO_STAGED_SHA256="$(shasum -a 256 "$AKUO_STAGE_APP/Contents/MacOS/Akuo" | awk '{print $1}')"
if [[ "$AKUO_STAGED_SHA256" != "$AKUO_CANDIDATE_SHA256" ]]; then
    echo "refusing local install: staged executable does not match the verified candidate" >&2
    exit 1
fi

if [[ "$AKUO_INSTALLED_STABLE" == true ]]; then
    if ! akuo_require_mutually_compatible "$AKUO_INSTALL_PATH" "$AKUO_STAGE_APP"; then
        echo "refusing local install: installed and staged Akuo identities are not mutually compatible" >&2
        exit 1
    fi
fi

if [[ -d "$AKUO_INSTALL_PATH" ]]; then
    AKUO_BACKUP_APP="$AKUO_STAGE_ROOT/Akuo.previous.app"
    mv -- "$AKUO_INSTALL_PATH" "$AKUO_BACKUP_APP"
fi
mv -- "$AKUO_STAGE_APP" "$AKUO_INSTALL_PATH"
AKUO_REPLACEMENT_INSTALLED=true

codesign --verify --deep --strict "$AKUO_INSTALL_PATH"
"$AKUO_PROJECT_ROOT/Scripts/verify-local-signing.sh" "$AKUO_INSTALL_PATH"
AKUO_INSTALLED_SHA256="$(shasum -a 256 "$AKUO_INSTALL_PATH/Contents/MacOS/Akuo" | awk '{print $1}')"
if [[ "$AKUO_INSTALLED_SHA256" != "$AKUO_STAGED_SHA256" ]]; then
    echo "installed executable does not match the staged candidate; rolling back" >&2
    exit 1
fi

printf 'Installed stable Akuo build at %s\n' "$AKUO_INSTALL_PATH"
printf 'Akuo executable SHA-256: %s\n' "$AKUO_INSTALLED_SHA256"
