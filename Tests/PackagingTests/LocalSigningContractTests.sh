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

akuo_write_stub() {
    local stub_path="$1"
    shift

    printf '%s\n' "$@" >"$stub_path"
    chmod +x "$stub_path"
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

AKUO_CONTRACT_PROJECT="$AKUO_TEST_TMP/contract-project"
AKUO_CONTRACT_BIN="$AKUO_TEST_TMP/contract-bin"
AKUO_CONTRACT_ROOT="$AKUO_TEST_TMP/contract-root"
AKUO_CONTRACT_CANDIDATE="$AKUO_TEST_TMP/AcceptedCandidate.app"
AKUO_BUILD_MARKER="$AKUO_TEST_TMP/build-invoked"
AKUO_VERIFY_LOG="$AKUO_TEST_TMP/verify.log"
AKUO_STAGE_SHA_LOG="$AKUO_TEST_TMP/stage-sha.log"
mkdir -p \
    "$AKUO_CONTRACT_PROJECT/Scripts/lib" \
    "$AKUO_CONTRACT_BIN" \
    "$AKUO_CONTRACT_ROOT/Applications"
cp "$AKUO_TEST_ROOT/Scripts/install-local.sh" "$AKUO_CONTRACT_PROJECT/Scripts/install-local.sh"
cp "$AKUO_TEST_ROOT/Scripts/lib/install-safety.sh" "$AKUO_CONTRACT_PROJECT/Scripts/lib/install-safety.sh"
akuo_make_fixture "$AKUO_CONTRACT_CANDIDATE"

# Stub bodies are single-quoted so their variables expand when the generated
# command runs, not while this test writes the command.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Scripts/build-app.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': >"${AKUO_BUILD_MARKER:?}"' \
    'if [[ -z "${AKUO_BUILD_SOURCE_APP:-}" ]]; then' \
    '    echo "FAIL: prebuilt-candidate mode invoked build-app.sh" >&2' \
    '    exit 97' \
    'fi' \
    'project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"' \
    'mkdir -p "$project_root/dist"' \
    '/usr/bin/ditto "$AKUO_BUILD_SOURCE_APP" "$project_root/dist/Akuo.app"'
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Scripts/verify-local-signing.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$1" >>"${AKUO_VERIFY_LOG:?}"' \
    'if [[ "${AKUO_REJECT_STAGED_IDENTITY:-}" == true && "$1" == */.akuo-install.*/Akuo.app ]]; then' \
    '    echo "refusing local install: staged fixture identity mismatch" >&2' \
    '    exit 1' \
    'fi' \
    '[[ -d "$1" ]]'
akuo_write_stub "$AKUO_CONTRACT_BIN/codesign" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ " $* " == *" -d "* && " $* " == *" -r- "* ]]; then' \
    '    echo '\''designated => identifier "app.akuo.Akuo"'\''' \
    'fi'
akuo_write_stub "$AKUO_CONTRACT_BIN/pgrep" \
    '#!/usr/bin/env bash' \
    'exit 1'
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_BIN/ditto" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '/usr/bin/ditto "$1" "$2"' \
    'if [[ "${AKUO_MUTATE_STAGED_EXECUTABLE:-}" == true ]]; then' \
    '    cp /usr/bin/false "$2/Contents/MacOS/Akuo"' \
    'fi' \
    '/usr/bin/shasum -a 256 "$2/Contents/MacOS/Akuo" | awk '\''{print $1}'\'' >>"${AKUO_STAGE_SHA_LOG:?}"'

AKUO_PREBUILT_OUTPUT=""
if ! AKUO_PREBUILT_OUTPUT="$(
    env \
        PATH="$AKUO_CONTRACT_BIN:$PATH" \
        AKUO_BUILD_MARKER="$AKUO_BUILD_MARKER" \
        AKUO_INSTALLER_TEST_ROOT="$AKUO_CONTRACT_ROOT" \
        AKUO_STAGE_SHA_LOG="$AKUO_STAGE_SHA_LOG" \
        AKUO_VERIFY_LOG="$AKUO_VERIFY_LOG" \
        "$AKUO_CONTRACT_PROJECT/Scripts/install-local.sh" \
        --candidate "$AKUO_CONTRACT_CANDIDATE" 2>&1
)"; then
    printf 'FAIL: prebuilt-candidate install was rejected:\n%s\n' "$AKUO_PREBUILT_OUTPUT" >&2
    exit 1
fi
if [[ -e "$AKUO_BUILD_MARKER" ]]; then
    echo "FAIL: prebuilt-candidate install invoked build-app.sh" >&2
    exit 1
fi
if ! cmp -s \
    "$AKUO_CONTRACT_CANDIDATE/Contents/MacOS/Akuo" \
    "$AKUO_CONTRACT_ROOT/Applications/Akuo.app/Contents/MacOS/Akuo"; then
    echo "FAIL: installed executable differs from the selected prebuilt candidate" >&2
    exit 1
fi
if [[ "$(sed -n '1p' "$AKUO_VERIFY_LOG")" != "$AKUO_CONTRACT_CANDIDATE" ]]; then
    echo "FAIL: installer did not verify the selected prebuilt candidate first" >&2
    exit 1
fi
AKUO_ACCEPTED_SHA="$(shasum -a 256 "$AKUO_CONTRACT_CANDIDATE/Contents/MacOS/Akuo" | awk '{print $1}')"
if [[ "$(sed -n '1p' "$AKUO_STAGE_SHA_LOG")" != "$AKUO_ACCEPTED_SHA" ]]; then
    echo "FAIL: staged executable differs from the selected prebuilt candidate" >&2
    exit 1
fi
if [[ "$(sed -n '2p' "$AKUO_VERIFY_LOG")" != */.akuo-install.*/Akuo.app ]]; then
    echo "FAIL: installer did not verify the staged application" >&2
    exit 1
fi
if [[ "$(sed -n '3p' "$AKUO_VERIFY_LOG")" != "$AKUO_CONTRACT_ROOT/Applications/Akuo.app" ]]; then
    echo "FAIL: installer did not verify the installed application" >&2
    exit 1
fi
if [[ "$AKUO_PREBUILT_OUTPUT" != *"Akuo executable SHA-256: $AKUO_ACCEPTED_SHA"* ]]; then
    echo "FAIL: installer did not report the accepted candidate hash" >&2
    exit 1
fi

AKUO_BUILD_ROOT="$AKUO_TEST_TMP/build-mode-root"
AKUO_BUILD_SOURCE_APP="$AKUO_TEST_TMP/BuiltCandidate.app"
mkdir -p "$AKUO_BUILD_ROOT/Applications"
akuo_make_fixture "$AKUO_BUILD_SOURCE_APP"
cp /usr/bin/false "$AKUO_BUILD_SOURCE_APP/Contents/MacOS/Akuo"
rm -f "$AKUO_BUILD_MARKER" "$AKUO_VERIFY_LOG" "$AKUO_STAGE_SHA_LOG"
if ! env \
    PATH="$AKUO_CONTRACT_BIN:$PATH" \
    AKUO_BUILD_MARKER="$AKUO_BUILD_MARKER" \
    AKUO_BUILD_SOURCE_APP="$AKUO_BUILD_SOURCE_APP" \
    AKUO_CODE_SIGN_IDENTITY='Apple Development: Contract Fixture (ABCDEFGHIJ)' \
    AKUO_INSTALLER_TEST_ROOT="$AKUO_BUILD_ROOT" \
    AKUO_STAGE_SHA_LOG="$AKUO_STAGE_SHA_LOG" \
    AKUO_VERIFY_LOG="$AKUO_VERIFY_LOG" \
    "$AKUO_CONTRACT_PROJECT/Scripts/install-local.sh" release >/dev/null; then
    echo "FAIL: build-and-install mode no longer succeeds" >&2
    exit 1
fi
if [[ ! -e "$AKUO_BUILD_MARKER" ]]; then
    echo "FAIL: build-and-install mode did not invoke build-app.sh" >&2
    exit 1
fi
if ! cmp -s \
    "$AKUO_BUILD_SOURCE_APP/Contents/MacOS/Akuo" \
    "$AKUO_BUILD_ROOT/Applications/Akuo.app/Contents/MacOS/Akuo"; then
    echo "FAIL: build-and-install mode did not install its built candidate" >&2
    exit 1
fi

AKUO_EXISTING_APP="$AKUO_CONTRACT_ROOT/Applications/Akuo.app"
rm -rf "$AKUO_EXISTING_APP"
akuo_make_fixture "$AKUO_EXISTING_APP"
cp /usr/bin/false "$AKUO_EXISTING_APP/Contents/MacOS/Akuo"
AKUO_EXISTING_SHA="$(shasum -a 256 "$AKUO_EXISTING_APP/Contents/MacOS/Akuo" | awk '{print $1}')"
rm -f "$AKUO_BUILD_MARKER" "$AKUO_VERIFY_LOG" "$AKUO_STAGE_SHA_LOG"
akuo_assert_rejected \
    "staged executable does not match the verified candidate" \
    env \
        PATH="$AKUO_CONTRACT_BIN:$PATH" \
        AKUO_BUILD_MARKER="$AKUO_BUILD_MARKER" \
        AKUO_INSTALLER_TEST_ROOT="$AKUO_CONTRACT_ROOT" \
        AKUO_MUTATE_STAGED_EXECUTABLE=true \
        AKUO_STAGE_SHA_LOG="$AKUO_STAGE_SHA_LOG" \
        AKUO_VERIFY_LOG="$AKUO_VERIFY_LOG" \
        "$AKUO_CONTRACT_PROJECT/Scripts/install-local.sh" \
        --candidate "$AKUO_CONTRACT_CANDIDATE"
if [[ "$(shasum -a 256 "$AKUO_EXISTING_APP/Contents/MacOS/Akuo" | awk '{print $1}')" != "$AKUO_EXISTING_SHA" ]]; then
    echo "FAIL: staged hash mismatch replaced the existing application" >&2
    exit 1
fi

rm -f "$AKUO_VERIFY_LOG" "$AKUO_STAGE_SHA_LOG"
akuo_assert_rejected \
    "staged fixture identity mismatch" \
    env \
        PATH="$AKUO_CONTRACT_BIN:$PATH" \
        AKUO_BUILD_MARKER="$AKUO_BUILD_MARKER" \
        AKUO_INSTALLER_TEST_ROOT="$AKUO_CONTRACT_ROOT" \
        AKUO_REJECT_STAGED_IDENTITY=true \
        AKUO_STAGE_SHA_LOG="$AKUO_STAGE_SHA_LOG" \
        AKUO_VERIFY_LOG="$AKUO_VERIFY_LOG" \
        "$AKUO_CONTRACT_PROJECT/Scripts/install-local.sh" \
        --candidate "$AKUO_CONTRACT_CANDIDATE"
if [[ "$(shasum -a 256 "$AKUO_EXISTING_APP/Contents/MacOS/Akuo" | awk '{print $1}')" != "$AKUO_EXISTING_SHA" ]]; then
    echo "FAIL: staged identity mismatch replaced the existing application" >&2
    exit 1
fi

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

printf 'PASS: local signing and exact-candidate installation contracts\n'
