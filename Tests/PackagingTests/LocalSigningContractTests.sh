#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-signing-tests.XXXXXX")"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

akuo_make_fixture() {
    local app_path="$1"

    mkdir -p -- "$app_path/Contents/MacOS"
    cp /usr/bin/true "$app_path/Contents/MacOS/Akuo"
    plutil -create xml1 "$app_path/Contents/Info.plist"
    plutil -insert CFBundleExecutable -string Akuo "$app_path/Contents/Info.plist"
    plutil -insert CFBundleIdentifier -string app.akuo.Akuo "$app_path/Contents/Info.plist"
    plutil -insert CFBundlePackageType -string APPL "$app_path/Contents/Info.plist"
}

akuo_assert_rejected() {
    local expected_message="$1"
    shift
    local output
    local status

    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        printf 'FAIL: command unexpectedly succeeded: %s\n' "$*" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected_message"* ]]; then
        printf 'FAIL: expected rejection containing %q, got:\n%s\n' "$expected_message" "$output" >&2
        exit 1
    fi
}

AKUO_ADHOC_APP="$AKUO_TEST_TMP/Akuo.app"
akuo_make_fixture "$AKUO_ADHOC_APP"
codesign --force --sign - "$AKUO_ADHOC_APP"

akuo_assert_rejected \
    "ad-hoc signature has a build-specific identity" \
    "$AKUO_TEST_ROOT/Scripts/verify-local-signing.sh" "$AKUO_ADHOC_APP"

AKUO_WEAK_DR_APP="$AKUO_TEST_TMP/WeakRequirement.app"
akuo_make_fixture "$AKUO_WEAK_DR_APP"
codesign --force --sign - \
    -r '=designated => identifier "app.akuo.Akuo"' \
    "$AKUO_WEAK_DR_APP"

akuo_assert_rejected \
    "ad-hoc signature has a build-specific identity" \
    "$AKUO_TEST_ROOT/Scripts/verify-local-signing.sh" "$AKUO_WEAK_DR_APP"

akuo_assert_rejected \
    "requires AKUO_CODE_SIGN_IDENTITY" \
    env -u AKUO_CODE_SIGN_IDENTITY "$AKUO_TEST_ROOT/Scripts/install-local.sh" debug

akuo_assert_rejected \
    "does not accept the ad-hoc identity '-'" \
    env AKUO_CODE_SIGN_IDENTITY=- "$AKUO_TEST_ROOT/Scripts/install-local.sh" debug

if [[ ! -f "$AKUO_TEST_ROOT/Scripts/lib/signing-policy.sh" ]]; then
    echo "FAIL: Scripts/lib/signing-policy.sh is missing" >&2
    exit 1
fi
# Resolved from the test's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_TEST_ROOT/Scripts/lib/signing-policy.sh"

AKUO_CONTROLLED_REQUIREMENT='designated => anchor apple generic and identifier "app.akuo.Akuo" and certificate leaf[subject.OU] = ABCDEFGHIJ'
if ! akuo_requirement_matches_policy "$AKUO_CONTROLLED_REQUIREMENT" ABCDEFGHIJ; then
    echo "FAIL: repository-controlled Apple/team requirement was rejected" >&2
    exit 1
fi
AKUO_NUMERIC_TEAM_REQUIREMENT='designated => anchor apple generic and identifier "app.akuo.Akuo" and certificate leaf[subject.OU] = "2DC432GLL2"'
if ! akuo_requirement_matches_policy "$AKUO_NUMERIC_TEAM_REQUIREMENT" 2DC432GLL2; then
    echo "FAIL: numeric-leading Apple team requirement was rejected" >&2
    exit 1
fi
if akuo_requirement_matches_policy \
    'designated => identifier "app.akuo.Akuo"' ABCDEFGHIJ; then
    echo "FAIL: identifier-only requirement matched the signing policy" >&2
    exit 1
fi

if [[ ! -f "$AKUO_TEST_ROOT/Scripts/lib/install-safety.sh" ]]; then
    echo "FAIL: Scripts/lib/install-safety.sh is missing" >&2
    exit 1
fi
# Resolved from the test's absolute project root.
# shellcheck disable=SC1091
source "$AKUO_TEST_ROOT/Scripts/lib/install-safety.sh"

AKUO_FAILED_BACKUP="$AKUO_TEST_TMP/recovery/Akuo.previous.app"
AKUO_OCCUPIED_TARGET="$AKUO_TEST_TMP/occupied/Akuo.app"
mkdir -p -- "$AKUO_FAILED_BACKUP" "$AKUO_OCCUPIED_TARGET"
if akuo_restore_backup "$AKUO_FAILED_BACKUP" "$AKUO_OCCUPIED_TARGET" >/dev/null 2>&1; then
    echo "FAIL: restore unexpectedly replaced an occupied target" >&2
    exit 1
fi
if [[ ! -d "$AKUO_FAILED_BACKUP" ]]; then
    echo "FAIL: failed restore did not preserve the recovery backup" >&2
    exit 1
fi

if ! akuo_require_mutually_compatible "$AKUO_ADHOC_APP" "$AKUO_ADHOC_APP"; then
    echo "FAIL: identical signed applications were not mutually compatible" >&2
    exit 1
fi

AKUO_DIFFERENT_ADHOC_APP="$AKUO_TEST_TMP/DifferentAkuo.app"
akuo_make_fixture "$AKUO_DIFFERENT_ADHOC_APP"
cp /usr/bin/false "$AKUO_DIFFERENT_ADHOC_APP/Contents/MacOS/Akuo"
codesign --force --sign - "$AKUO_DIFFERENT_ADHOC_APP"
if akuo_require_mutually_compatible \
    "$AKUO_ADHOC_APP" "$AKUO_DIFFERENT_ADHOC_APP" >/dev/null 2>&1; then
    echo "FAIL: different signed application identities were mutually compatible" >&2
    exit 1
fi

printf 'PASS: unstable local signing identities are rejected\n'
