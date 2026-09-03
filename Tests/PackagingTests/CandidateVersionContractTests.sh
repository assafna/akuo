#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-version-tests.XXXXXX")"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

AKUO_FIXTURE_ROOT="$AKUO_TEST_TMP/project"
AKUO_FAKE_BIN="$AKUO_TEST_TMP/fake-bin"
AKUO_BUILD_BIN="$AKUO_TEST_TMP/build-bin"

akuo_write_file() {
    local path="$1"
    shift

    mkdir -p -- "$(dirname -- "$path")"
    printf '%s\n' "$@" >"$path"
}

akuo_write_identity_source() {
    local version_declaration="$1"
    local build_declaration="$2"

    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift" \
        'public enum AkuoCoreVersion {' \
        "    $version_declaration" \
        "    $build_declaration" \
        '}'
}

akuo_write_template() {
    local version="${1:-}"
    local build="${2:-}"
    local identity_lines=()

    if [[ -n "$version" ]]; then
        identity_lines+=(
            '  <key>CFBundleShortVersionString</key><string>'"$version"'</string>'
        )
    fi
    if [[ -n "$build" ]]; then
        identity_lines+=(
            '  <key>CFBundleVersion</key><string>'"$build"'</string>'
        )
    fi
    akuo_write_file "$AKUO_FIXTURE_ROOT/Configuration/Akuo-Info.plist" \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' \
        '  <key>CFBundleExecutable</key><string>Akuo</string>' \
        '  <key>CFBundleIdentifier</key><string>app.akuo.Akuo</string>' \
        '  <key>CFBundlePackageType</key><string>APPL</string>' \
        "${identity_lines[@]}" \
        '</dict></plist>'
}

akuo_commit() {
    git -C "$AKUO_FIXTURE_ROOT" add .
    git -C "$AKUO_FIXTURE_ROOT" commit -q -m "$1"
}

akuo_reset_fixture() {
    rm -rf -- "$AKUO_FIXTURE_ROOT" "$AKUO_FAKE_BIN" "$AKUO_BUILD_BIN"
    mkdir -p \
        "$AKUO_FIXTURE_ROOT/Scripts/lib" \
        "$AKUO_FIXTURE_ROOT/Sources/AkuoMac" \
        "$AKUO_FAKE_BIN" \
        "$AKUO_BUILD_BIN"
    cp "$AKUO_TEST_ROOT/Scripts/build-app.sh" "$AKUO_FIXTURE_ROOT/Scripts/build-app.sh"
    cp "$AKUO_TEST_ROOT/Scripts/lib/signing-policy.sh" \
        "$AKUO_FIXTURE_ROOT/Scripts/lib/signing-policy.sh"
    if [[ -f "$AKUO_TEST_ROOT/Scripts/lib/candidate-version.sh" ]]; then
        cp "$AKUO_TEST_ROOT/Scripts/lib/candidate-version.sh" \
            "$AKUO_FIXTURE_ROOT/Scripts/lib/candidate-version.sh"
    fi
    if [[ -f "$AKUO_TEST_ROOT/Scripts/verify-candidate-version.sh" ]]; then
        cp "$AKUO_TEST_ROOT/Scripts/verify-candidate-version.sh" \
            "$AKUO_FIXTURE_ROOT/Scripts/verify-candidate-version.sh"
    fi
    chmod +x "$AKUO_FIXTURE_ROOT/Scripts/"*.sh

    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "4"'
    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoMac/AkuoMacVersion.swift" \
        'import AkuoCore' \
        'public enum AkuoMacVersion {' \
        '    public static let current = AkuoCoreVersion.current' \
        '    public static let build = AkuoCoreVersion.build' \
        '}'
    akuo_write_template

    # Stub bodies are single-quoted so their variables expand when each generated
    # command runs, not while this test writes the command.
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_FAKE_BIN/swift" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ " $* " == *" --show-bin-path "* ]]; then' \
        '    printf "%s\n" "${AKUO_BUILD_BIN:?}"' \
        'fi'
    chmod +x "$AKUO_FAKE_BIN/swift"
    akuo_write_file "$AKUO_FAKE_BIN/codesign" \
        '#!/usr/bin/env bash' \
        'exit 0'
    chmod +x "$AKUO_FAKE_BIN/codesign"
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_BUILD_BIN/Akuo" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ "${1:-}" == --candidate-identity ]]; then' \
        '    printf "%b\n" "${AKUO_RUNTIME_IDENTITY:-0.4.0\\t4}"' \
        '    exit 0' \
        'fi' \
        'exit 64'
    chmod +x "$AKUO_BUILD_BIN/Akuo"

    git -C "$AKUO_FIXTURE_ROOT" init -q
    git -C "$AKUO_FIXTURE_ROOT" config user.name 'Akuo Version Contract'
    git -C "$AKUO_FIXTURE_ROOT" config user.email version-contract@example.invalid
    akuo_commit 'fixture identity'
}

akuo_build() {
    env \
        PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_BUILD_BIN="$AKUO_BUILD_BIN" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        "$AKUO_FIXTURE_ROOT/Scripts/build-app.sh" release
}

akuo_verify() {
    env \
        PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        "$AKUO_FIXTURE_ROOT/Scripts/verify-candidate-version.sh" \
        "$AKUO_FIXTURE_ROOT/dist/Akuo.app"
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
        printf 'FAIL: expected rejection containing %q, got:\n%s\n' \
            "$expected_message" "$output" >&2
        exit 1
    fi
}

# Production mutation caught: omitting plist injection after removing candidate
# literals from the committed template.
test_injects_authoritative_identity() {
    akuo_reset_fixture
    akuo_build >/dev/null
    local plist="$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/Info.plist"

    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == 0.4.0 ]]
    [[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == 4 ]]
    akuo_verify >/dev/null
}

# Production mutation caught: accepting hard-coded candidate identity values in
# the committed plist, where they can drift from the authoritative Swift source.
test_rejects_template_drift() {
    akuo_reset_fixture
    akuo_write_template 0.3.0 3
    akuo_commit 'drifted template'
    akuo_assert_rejected 'must not declare CFBundleShortVersionString or CFBundleVersion' \
        akuo_build
}

# Production mutation caught: accepting an absent marketing-version declaration.
test_rejects_absent_version() {
    akuo_reset_fixture
    akuo_write_identity_source '' 'public static let build = "4"'
    akuo_commit 'remove version'
    akuo_assert_rejected 'missing authoritative current declaration' akuo_build
}

# Production mutation caught: selecting one value when the marketing version is
# declared more than once.
test_rejects_duplicate_version() {
    akuo_reset_fixture
    akuo_write_identity_source \
        $'public static let current = "0.4.0"\n    public static let current = "0.5.0"' \
        'public static let build = "4"'
    akuo_commit 'duplicate version'
    akuo_assert_rejected 'duplicate authoritative current declarations' akuo_build
}

# Production mutation caught: accepting a non-semantic marketing-version literal.
test_rejects_malformed_version() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "release-four"' \
        'public static let build = "4"'
    akuo_commit 'malformed version'
    akuo_assert_rejected 'malformed authoritative current declaration' akuo_build
}

# Production mutation caught: evaluating or guessing a computed version instead
# of requiring one auditable string literal.
test_rejects_nonliteral_version() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = releaseVersion' \
        'public static let build = "4"'
    akuo_commit 'nonliteral version'
    akuo_assert_rejected 'malformed authoritative current declaration' akuo_build
}

# Production mutation caught: accepting an absent build declaration.
test_rejects_absent_build() {
    akuo_reset_fixture
    akuo_write_identity_source 'public static let current = "0.4.0"' ''
    akuo_commit 'remove build'
    akuo_assert_rejected 'missing authoritative build declaration' akuo_build
}

# Production mutation caught: selecting one value when the build is declared
# more than once.
test_rejects_duplicate_build() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        $'public static let build = "4"\n    public static let build = "5"'
    akuo_commit 'duplicate build'
    akuo_assert_rejected 'duplicate authoritative build declarations' akuo_build
}

# Production mutation caught: accepting a malformed build literal.
test_rejects_malformed_build() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "04"'
    akuo_commit 'malformed build'
    akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: evaluating or guessing a computed build instead
# of requiring one auditable string literal.
test_rejects_nonliteral_build() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = String(4)'
    akuo_commit 'nonliteral build'
    akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: packaging a binary whose runtime identity does not
# match the authoritative declaration and injected plist.
test_rejects_runtime_drift() {
    akuo_reset_fixture
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t5' \
        akuo_assert_rejected 'runtime candidate identity does not match authoritative declaration' \
        akuo_build
}

# Production mutation caught: accepting a candidate plist that was changed after
# packaging even though source and runtime still agree.
test_verifier_rejects_candidate_plist_drift() {
    akuo_reset_fixture
    akuo_build >/dev/null
    plutil -replace CFBundleVersion -string 5 \
        "$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/Info.plist"
    akuo_assert_rejected 'candidate plist identity does not match authoritative declaration' \
        akuo_verify
}

# Production mutation caught: trusting a v-tag name instead of inspecting the
# tagged source/plist identity and rejecting its released pair on a later commit.
test_rejects_released_pair_reuse() {
    akuo_reset_fixture
    akuo_write_identity_source 'public static let current = "0.4.0"' ''
    akuo_write_template 0.4.0 4
    akuo_commit 'legacy tagged source identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v9.9.9 -m 'fixture release'
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "4"'
    akuo_write_template
    akuo_commit 'reuse tagged pair later'
    akuo_assert_rejected 'candidate identity 0.4.0 (4) was already released by v9.9.9' \
        akuo_build
}

# Production mutation caught: rejecting the tagged release commit itself merely
# because its pair appears in the tag being built.
test_allows_exact_tagged_release() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'tagged release source'
    akuo_commit 'unrelated source revision'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    akuo_build >/dev/null
    akuo_verify >/dev/null
}

# Production mutation caught: treating a new source commit with an unchanged
# build identity as a rebuild of the previous candidate.
test_rejects_new_source_with_same_build() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'new distributable source revision'
    akuo_commit 'new source without build advance'
    akuo_assert_rejected 'new source revision must advance the authoritative build identity' \
        akuo_build
}

# Production mutation caught: storing mutable build history outside Git and then
# rejecting a deterministic rebuild of the exact same commit.
test_allows_same_commit_rebuild() {
    akuo_reset_fixture
    akuo_build >/dev/null
    akuo_build >/dev/null
    akuo_verify >/dev/null
}

case "${1:-all}" in
    injection) test_injects_authoritative_identity ;;
    template-drift) test_rejects_template_drift ;;
    absent-version) test_rejects_absent_version ;;
    duplicate-version) test_rejects_duplicate_version ;;
    malformed-version) test_rejects_malformed_version ;;
    nonliteral-version) test_rejects_nonliteral_version ;;
    absent-build) test_rejects_absent_build ;;
    duplicate-build) test_rejects_duplicate_build ;;
    malformed-build) test_rejects_malformed_build ;;
    nonliteral-build) test_rejects_nonliteral_build ;;
    runtime-drift) test_rejects_runtime_drift ;;
    plist-drift) test_verifier_rejects_candidate_plist_drift ;;
    released-reuse) test_rejects_released_pair_reuse ;;
    exact-tag) test_allows_exact_tagged_release ;;
    new-source-reuse) test_rejects_new_source_with_same_build ;;
    same-commit) test_allows_same_commit_rebuild ;;
    all)
        test_injects_authoritative_identity
        test_rejects_template_drift
        test_rejects_absent_version
        test_rejects_duplicate_version
        test_rejects_malformed_version
        test_rejects_nonliteral_version
        test_rejects_absent_build
        test_rejects_duplicate_build
        test_rejects_malformed_build
        test_rejects_nonliteral_build
        test_rejects_runtime_drift
        test_verifier_rejects_candidate_plist_drift
        test_rejects_released_pair_reuse
        test_allows_exact_tagged_release
        test_rejects_new_source_with_same_build
        test_allows_same_commit_rebuild
        ;;
    *)
        printf 'unknown test case: %s\n' "$1" >&2
        exit 2
        ;;
esac

printf 'PASS: candidate version source, packaging, runtime, and reuse contracts\n'
