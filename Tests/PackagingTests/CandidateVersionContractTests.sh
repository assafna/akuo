#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-version-tests.XXXXXX")"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

AKUO_FIXTURE_ROOT="$AKUO_TEST_TMP/project"
AKUO_ORIGIN_ROOT="$AKUO_TEST_TMP/origin.git"
AKUO_TAG_EVIDENCE="$AKUO_TEST_TMP/release-tags.evidence"
AKUO_FAKE_BIN="$AKUO_TEST_TMP/fake-bin"
AKUO_BUILD_BIN="$AKUO_TEST_TMP/build-bin"
AKUO_BUILD_INPUT_LOG="$AKUO_TEST_TMP/build-input.log"
AKUO_BUILD_CWD_LOG="$AKUO_TEST_TMP/build-cwd.log"
AKUO_RUNTIME_TEMPLATE="$AKUO_TEST_TMP/Akuo-runtime-template"
AKUO_SYSTEM_GIT="$(command -v git)"

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

akuo_refresh_tag_evidence() {
    git -C "$AKUO_FIXTURE_ROOT" ls-remote --tags --refs origin \
        'refs/tags/v*' >"$AKUO_TAG_EVIDENCE"
}

akuo_reset_fixture() {
    rm -rf -- \
        "$AKUO_FIXTURE_ROOT" "$AKUO_ORIGIN_ROOT" "$AKUO_FAKE_BIN" "$AKUO_BUILD_BIN" \
        "$AKUO_BUILD_INPUT_LOG" "$AKUO_BUILD_CWD_LOG"
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
    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoSourceRevision.swift" \
        'public enum AkuoSourceRevision {' \
        '    public static let current = ""' \
        '}'
    akuo_write_template

    # Stub bodies are single-quoted so their variables expand when each generated
    # command runs, not while this test writes the command.
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_FAKE_BIN/swift" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ " $* " != *" --show-bin-path "* ]]; then' \
        '    printf "%s\n" "$PWD" >"${AKUO_BUILD_CWD_LOG:?}"' \
        '    if [[ "${AKUO_MUTATE_THEN_RESTORE:-}" == true ]]; then' \
        '        source_path="${AKUO_FIXTURE_ROOT_ENV:?}/Sources/AkuoCore/AkuoCoreVersion.swift"' \
        '        source_contents="$(cat "$source_path")"' \
        '        printf "\n// transient build mutation\n" >>"$source_path"' \
        '    fi' \
        '    {' \
        '        if [[ -f Sources/AkuoCore/Ignored.swift ]]; then printf "ignored-input\n"; fi' \
        '        cat Sources/AkuoCore/AkuoCoreVersion.swift' \
        '        cat Sources/AkuoCore/AkuoSourceRevision.swift' \
        '    } >"${AKUO_BUILD_INPUT_LOG:?}"' \
        '    compiled_source_revision="$(sed -E -n '\''s/^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+current[[:space:]]*=[[:space:]]*"([0-9a-f]{40})"[[:space:]]*$/\1/p'\'' Sources/AkuoCore/AkuoSourceRevision.swift)"' \
        '    if [[ ! "$compiled_source_revision" =~ ^[0-9a-f]{40}$ ]]; then' \
        '        echo "fake compiler rejected runtime source revision" >&2' \
        '        exit 1' \
        '    fi' \
        '    sed "s/__AKUO_COMPILED_SOURCE_REVISION__/$compiled_source_revision/" "${AKUO_RUNTIME_TEMPLATE:?}" >"${AKUO_BUILD_BIN:?}/Akuo"' \
        '    chmod +x "${AKUO_BUILD_BIN:?}/Akuo"' \
        '    if [[ "${AKUO_MUTATE_THEN_RESTORE:-}" == true ]]; then' \
        '        printf "%s\n" "$source_contents" >"$source_path"' \
        '    fi' \
        'fi' \
        'if [[ "${AKUO_MUTATE_DURING_BUILD:-}" == true && " $* " != *" --show-bin-path "* ]]; then' \
        '    printf "mutated during build\n" >>"${AKUO_FIXTURE_ROOT_ENV:?}/README.md"' \
        'fi' \
        'if [[ " $* " == *" --show-bin-path "* ]]; then' \
        '    printf "%s\n" "${AKUO_BUILD_BIN:?}"' \
        'fi'
    chmod +x "$AKUO_FAKE_BIN/swift"
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_FAKE_BIN/git" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ "${AKUO_FAIL_REMOTE_TAG_QUERY:-}" == true && " $* " == *" ls-remote --tags --refs "* ]]; then exit 72; fi' \
        'if [[ "${AKUO_MALFORMED_REMOTE_TAGS:-}" == true && " $* " == *" ls-remote --tags --refs "* ]]; then' \
        '    printf "malformed remote tags\n"' \
        '    exit 0' \
        'fi' \
        'if [[ "${AKUO_FAIL_LOCAL_TAG_ENUMERATION:-}" == true && " $* " == *" tag --list "* ]]; then exit 71; fi' \
        'exec "${AKUO_SYSTEM_GIT:?}" "$@"'
    chmod +x "$AKUO_FAKE_BIN/git"
    akuo_write_file "$AKUO_FAKE_BIN/codesign" \
        '#!/usr/bin/env bash' \
        'exit 0'
    chmod +x "$AKUO_FAKE_BIN/codesign"
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_RUNTIME_TEMPLATE" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'compiled_source_revision="__AKUO_COMPILED_SOURCE_REVISION__"' \
        'if [[ "${1:-}" == --candidate-identity ]]; then' \
        '    printf "%b\n" "${AKUO_RUNTIME_IDENTITY:-0.4.0\\t4}"' \
        '    exit 0' \
        'fi' \
        'if [[ "${1:-}" == --candidate-source-revision ]]; then' \
        '    if [[ -n "${AKUO_RUNTIME_SOURCE_REVISION:-}" ]]; then' \
        '        printf "%s\n" "$AKUO_RUNTIME_SOURCE_REVISION"' \
        '    else' \
        '        printf "%s\n" "$compiled_source_revision"' \
        '    fi' \
        '    exit 0' \
        'fi' \
        'exit 64'

    git -C "$AKUO_FIXTURE_ROOT" init -q
    git -C "$AKUO_FIXTURE_ROOT" config user.name 'Akuo Version Contract'
    git -C "$AKUO_FIXTURE_ROOT" config user.email version-contract@example.invalid
    akuo_write_file "$AKUO_FIXTURE_ROOT/.gitignore" '.build/' 'dist/'
    akuo_write_identity_source 'public static let current = "0.3.0"' ''
    akuo_write_template 0.3.0 3
    akuo_commit 'released fixture identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.3.0 -m 'fixture release'
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "4"'
    akuo_write_template
    akuo_commit 'fixture candidate identity'

    git init -q --bare "$AKUO_ORIGIN_ROOT"
    git -C "$AKUO_FIXTURE_ROOT" remote add origin "$AKUO_ORIGIN_ROOT"
    git -C "$AKUO_FIXTURE_ROOT" push -q --set-upstream origin HEAD
    git -C "$AKUO_FIXTURE_ROOT" push -q origin --tags
    akuo_refresh_tag_evidence
}

akuo_build() {
    env \
        PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_SYSTEM_GIT="$AKUO_SYSTEM_GIT" \
        AKUO_BUILD_BIN="$AKUO_BUILD_BIN" \
        AKUO_BUILD_INPUT_LOG="$AKUO_BUILD_INPUT_LOG" \
        AKUO_BUILD_CWD_LOG="$AKUO_BUILD_CWD_LOG" \
        AKUO_RUNTIME_TEMPLATE="$AKUO_RUNTIME_TEMPLATE" \
        AKUO_FIXTURE_ROOT_ENV="$AKUO_FIXTURE_ROOT" \
        AKUO_RELEASE_TAGS_EVIDENCE="${AKUO_RELEASE_TAGS_EVIDENCE:-}" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        "$AKUO_FIXTURE_ROOT/Scripts/build-app.sh" release
}

akuo_verify() {
    env \
        PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_SYSTEM_GIT="$AKUO_SYSTEM_GIT" \
        AKUO_FIXTURE_ROOT_ENV="$AKUO_FIXTURE_ROOT" \
        AKUO_RELEASE_TAGS_EVIDENCE="${AKUO_RELEASE_TAGS_EVIDENCE:-}" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        AKUO_SOURCE_REVISION="${AKUO_SOURCE_REVISION:-}" \
        "$AKUO_FIXTURE_ROOT/Scripts/verify-candidate-version.sh" \
        "$AKUO_FIXTURE_ROOT/dist/Akuo.app"
}

akuo_validate_history_at_head() {
    (
        PATH="$AKUO_FAKE_BIN:$PATH"
        export PATH AKUO_SYSTEM_GIT
        # shellcheck disable=SC1091
        source "$AKUO_FIXTURE_ROOT/Scripts/lib/candidate-version.sh"
        akuo_read_revision_identity "$AKUO_FIXTURE_ROOT" HEAD
        AKUO_CANDIDATE_VERSION="$AKUO_REVISION_VERSION"
        AKUO_CANDIDATE_BUILD="$AKUO_REVISION_BUILD"
        akuo_validate_candidate_history "$AKUO_FIXTURE_ROOT"
    )
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
# literals from the committed template, or omitting its exact source revision.
test_injects_authoritative_identity() {
    akuo_reset_fixture
    akuo_build >/dev/null
    local plist="$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/Info.plist"

    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == 0.4.0 ]]
    [[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == 4 ]]
    [[ "$(plutil -extract AkuoSourceRevision raw -o - "$plist")" == \
        "$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" ]]
    [[ "$(AKUO_SYSTEM_GIT="$AKUO_SYSTEM_GIT" \
        AKUO_FIXTURE_ROOT_ENV="$AKUO_FIXTURE_ROOT" \
        "$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/MacOS/Akuo" \
            --candidate-source-revision)" == \
        "$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" ]]
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

# Production mutation caught: accepting a bundle whose recorded source revision
# was changed after packaging while its version/build pair still agrees.
test_verifier_rejects_source_revision_drift() {
    akuo_reset_fixture
    akuo_build >/dev/null
    plutil -replace AkuoSourceRevision -string \
        0000000000000000000000000000000000000000 \
        "$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/Info.plist"
    akuo_assert_rejected 'candidate source revision does not match committed HEAD' \
        akuo_verify
}

# Production mutation caught: accepting a runtime compiled without the exact
# snapshotted source revision even though its plist label matches HEAD.
test_verifier_rejects_runtime_source_revision_drift() {
    akuo_reset_fixture
    akuo_build >/dev/null
    AKUO_RUNTIME_SOURCE_REVISION=0000000000000000000000000000000000000000 \
        akuo_assert_rejected 'runtime source revision does not match committed HEAD' \
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
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v9.9.9
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
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_build >/dev/null
    akuo_verify >/dev/null
}

# Production mutation caught: comparing an exact modern release against later
# descendants and thereby making an already-published tag impossible to rebuild.
test_allows_modern_exact_tag_rebuild_after_later_build() {
    akuo_reset_fixture
    local tagged_commit
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    tagged_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "6"'
    akuo_commit 'later descendant build 6'
    git -C "$AKUO_FIXTURE_ROOT" checkout -q --detach "$tagged_commit"
    akuo_build >/dev/null
    akuo_verify >/dev/null
}

# Production mutation caught: applying modern same-pair uniqueness to a legacy
# merge-tagged release whose feature parent necessarily carries the release
# plist identity, making the real v0.3.0 topology impossible to rebuild.
test_allows_legacy_merge_tagged_release() {
    akuo_reset_fixture
    local released_commit
    released_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse 'v0.3.0^{commit}')"
    git -C "$AKUO_FIXTURE_ROOT" tag -d v0.3.0 >/dev/null
    git -C "$AKUO_FIXTURE_ROOT" push -q origin :refs/tags/v0.3.0

    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b legacy-release-feature "$released_commit"
    akuo_write_file "$AKUO_FIXTURE_ROOT/feature.txt" 'legacy release feature'
    akuo_commit 'legacy release feature carrying 0.3.0 build 3'
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b legacy-release-main "$released_commit"
    akuo_write_file "$AKUO_FIXTURE_ROOT/integration.txt" 'legacy integration change'
    akuo_commit 'legacy release integration'
    git -C "$AKUO_FIXTURE_ROOT" merge -q --no-ff legacy-release-feature \
        -m 'legacy v0.3.0 release merge'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.3.0 -m 'fixture legacy merge release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.3.0

    akuo_validate_history_at_head
}

# Production mutation caught: treating a tag on a later source commit as
# permission to reuse the identity already assigned to its parent candidate.
test_rejects_exact_tag_laundering() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'later tagged source'
    akuo_commit 'later source with reused identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_assert_rejected 'candidate identity 0.4.0 (4) is assigned to another source revision' \
        akuo_build
}

# Production mutation caught: letting an exact tag disable build advancement
# when a new marketing version reuses a lower build than its ancestor.
test_rejects_cross_version_lower_build_exact_tag() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "6"'
    akuo_commit 'advance prior candidate to build 6'
    akuo_write_identity_source \
        'public static let current = "0.5.0"' \
        'public static let build = "3"'
    akuo_commit 'reuse lower build under new version'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.5.0 -m 'invalid lower-build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.5.0
    AKUO_RUNTIME_IDENTITY=$'0.5.0\t3' \
        akuo_assert_rejected 'build identity 3 is already assigned to another source revision' \
        akuo_build
}

# Production mutation caught: treating equality as build advancement merely
# because an exact tag changes the marketing version.
test_rejects_cross_version_equal_build_exact_tag() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "6"'
    akuo_commit 'advance prior candidate to build 6'
    akuo_write_identity_source \
        'public static let current = "0.5.0"' \
        'public static let build = "6"'
    akuo_commit 'reuse equal build under new version'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.5.0 -m 'invalid equal-build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.5.0
    AKUO_RUNTIME_IDENTITY=$'0.5.0\t6' \
        akuo_assert_rejected 'build identity 6 is already assigned to another source revision' \
        akuo_build
}

# Production mutation caught: allowing the legacy exact-tag exception to hide
# the same released pair on a different live-origin release tag.
test_rejects_legacy_pair_reuse_across_release_tags() {
    akuo_reset_fixture
    local released_commit
    released_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse 'v0.3.0^{commit}')"
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b duplicate-legacy-release "$released_commit"
    akuo_write_file "$AKUO_FIXTURE_ROOT/duplicate-release.txt" 'different release source'
    akuo_commit 'different legacy source with released pair'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.3.0-copy -m 'duplicate fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.3.0-copy
    git -C "$AKUO_FIXTURE_ROOT" checkout -q --detach "$released_commit"
    akuo_assert_rejected 'candidate identity 0.3.0 (3) was already released by v0.3.0-copy' \
        akuo_validate_history_at_head
}

# Production mutation caught: treating a new source commit with an unchanged
# build identity as a rebuild of the previous candidate.
test_rejects_new_source_with_same_build() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'new distributable source revision'
    akuo_commit 'new source without build advance'
    akuo_assert_rejected 'build identity 4 is already assigned to another source revision' \
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

# Production mutation caught: compiling tracked source edits that do not belong
# to the committed candidate revision.
test_rejects_dirty_tracked_source() {
    akuo_reset_fixture
    printf '\n// dirty candidate source\n' >>\
        "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift"
    akuo_assert_rejected 'candidate source worktree must be clean' akuo_build
}

# Production mutation caught: compiling an untracked source file under the same
# committed version/build identity.
test_rejects_dirty_untracked_source() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/Injected.swift" \
        'public let injectedCandidateBehavior = true'
    akuo_assert_rejected 'candidate source worktree must be clean' akuo_build
}

# Production mutation caught: allowing an ignored Swift file in the caller
# worktree to enter compilation under the clean committed HEAD identity.
test_build_ignores_ignored_swift_input() {
    akuo_reset_fixture
    printf 'Sources/AkuoCore/Ignored.swift\n' >>"$AKUO_FIXTURE_ROOT/.git/info/exclude"
    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/Ignored.swift" \
        'public let ignoredCandidateBehavior = true'
    akuo_build >/dev/null
    [[ "$(cat "$AKUO_BUILD_CWD_LOG")" != "$AKUO_FIXTURE_ROOT" ]]
    [[ "$(cat "$AKUO_BUILD_INPUT_LOG")" != *ignored-input* ]]
}

# Production mutation caught: independently verifying a previously built bundle
# against a dirty checkout rather than the exact committed source revision.
test_verifier_rejects_dirty_source() {
    akuo_reset_fixture
    akuo_build >/dev/null
    printf '\ndirty verifier checkout\n' >>"$AKUO_FIXTURE_ROOT/README.md"
    AKUO_SOURCE_REVISION="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" \
        akuo_assert_rejected 'candidate source worktree must be clean' akuo_verify
}

# Production mutation caught: trusting only a pre-build clean check when source
# changes while Swift compilation is running.
test_rejects_source_change_during_build() {
    akuo_reset_fixture
    AKUO_MUTATE_DURING_BUILD=true \
        akuo_assert_rejected 'candidate source changed during packaging' akuo_build
}

# Production mutation caught: compiling transient caller-worktree bytes that are
# restored before the post-build clean check can observe them.
test_build_uses_snapshot_during_transient_mutation() {
    akuo_reset_fixture
    AKUO_MUTATE_THEN_RESTORE=true akuo_build >/dev/null
    [[ "$(cat "$AKUO_BUILD_CWD_LOG")" != "$AKUO_FIXTURE_ROOT" ]]
    [[ "$(cat "$AKUO_BUILD_INPUT_LOG")" != *'transient build mutation'* ]]
    [[ -z "$(git -C "$AKUO_FIXTURE_ROOT" status --porcelain=v1 --untracked-files=all)" ]]
}

# Test-harness mutation caught: making the fake runtime discover repository HEAD
# dynamically instead of retaining the source revision consumed at fake compile
# time, which would hide a removed or corrupted snapshot injection.
test_fake_runtime_retains_compiled_source_revision() {
    akuo_reset_fixture
    local built_revision
    local runtime_revision
    built_revision="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    akuo_build >/dev/null
    akuo_write_file "$AKUO_FIXTURE_ROOT/post-build.txt" 'new source after packaging'
    akuo_commit 'advance source after packaging'
    runtime_revision="$(
        AKUO_SYSTEM_GIT="$AKUO_SYSTEM_GIT" \
            AKUO_FIXTURE_ROOT_ENV="$AKUO_FIXTURE_ROOT" \
            "$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/MacOS/Akuo" \
            --candidate-source-revision
    )"
    if [[ "$runtime_revision" != "$built_revision" ]]; then
        printf 'FAIL: fake runtime did not retain compiled source revision\n' >&2
        return 1
    fi
}

# Production mutation caught: allowing dirty source merely because HEAD is an
# exact release-tag commit.
test_rejects_dirty_exact_tagged_release() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    printf '\n// dirty tagged source\n' >>\
        "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift"
    akuo_assert_rejected 'candidate source worktree must be clean' akuo_build
}

# Production mutation caught: treating an absent local release tag as proof that
# no released pair exists even when origin advertises the missing tag.
test_rejects_incomplete_local_tags() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -d v0.3.0 >/dev/null
    akuo_assert_rejected 'local release tags do not match origin' akuo_build
}

# Production mutation caught: treating a successful but empty live origin query
# as sufficient released-tag provenance.
test_rejects_no_tag_provenance() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -d v0.3.0 >/dev/null
    git -C "$AKUO_FIXTURE_ROOT" push -q origin :refs/tags/v0.3.0
    akuo_assert_rejected 'origin has no release tags' akuo_build
}

# Production mutation caught: trusting a stale caller-created inventory that
# matches stale local tags after origin has gained another release tag.
test_rejects_stale_matching_tag_evidence() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'remote-only fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    git -C "$AKUO_FIXTURE_ROOT" tag -d v0.4.0 >/dev/null
    AKUO_RELEASE_TAGS_EVIDENCE="$AKUO_TAG_EVIDENCE" \
        akuo_assert_rejected 'local release tags do not match origin' akuo_build
}

# Production mutation caught: accepting caller evidence when the live read-only
# origin tag query cannot establish current provenance.
test_rejects_remote_tag_query_failure() {
    akuo_reset_fixture
    AKUO_FAIL_REMOTE_TAG_QUERY=true \
        akuo_assert_rejected 'cannot query release tags from origin' akuo_build
}

# Production mutation caught: losing a tag-enumeration failure through process
# substitution and continuing with an empty release set.
test_rejects_failed_local_tag_enumeration() {
    akuo_reset_fixture
    AKUO_FAIL_LOCAL_TAG_ENUMERATION=true \
        akuo_assert_rejected 'cannot enumerate local release tags' akuo_build
}

# Production mutation caught: accepting malformed ref output from the live
# origin query as complete released-tag provenance.
test_rejects_malformed_remote_tags() {
    akuo_reset_fixture
    AKUO_MALFORMED_REMOTE_TAGS=true \
        akuo_assert_rejected 'malformed origin response' akuo_build
}

# Production mutation caught: treating a depth-one checkout with unavailable
# ancestors and tags as a root repository.
test_rejects_shallow_history() {
    akuo_reset_fixture
    local shallow_root="$AKUO_TEST_TMP/shallow-project"
    git clone -q --depth 1 "file://$AKUO_ORIGIN_ROOT" "$shallow_root"
    AKUO_FIXTURE_ROOT="$shallow_root"
    akuo_assert_rejected 'candidate packaging requires complete, non-shallow history' \
        akuo_build
}

# Production mutation caught: reusing one build identity on two commits from
# divergent local branches even though neither is the current commit's parent.
test_rejects_divergent_identity_reuse() {
    akuo_reset_fixture
    local candidate_branch
    local candidate_commit
    local base_commit
    candidate_branch="$(git -C "$AKUO_FIXTURE_ROOT" branch --show-current)"
    candidate_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    base_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD^)"
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b divergent-candidate "$base_commit"
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "4"'
    akuo_write_template
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'divergent candidate source'
    akuo_commit 'divergent candidate with reused build'
    git -C "$AKUO_FIXTURE_ROOT" checkout -q "$candidate_branch"
    [[ "$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" == "$candidate_commit" ]]
    akuo_assert_rejected 'build identity 4 is already assigned to another source revision' \
        akuo_build
}

# Production mutation caught: checking only the first parent of a merge whose
# second parent already used the candidate build identity.
test_rejects_merge_parent_identity_reuse() {
    akuo_reset_fixture
    local candidate_commit
    local base_commit
    candidate_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    base_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD^)"
    git -C "$AKUO_FIXTURE_ROOT" branch existing-candidate "$candidate_commit"
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b integration "$base_commit"
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'independent landed change'
    akuo_commit 'independent landed change'
    git -C "$AKUO_FIXTURE_ROOT" merge -q --no-ff existing-candidate \
        -m 'merge existing candidate source'
    akuo_assert_rejected 'build identity 4 is already assigned to another source revision' \
        akuo_build
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
    source-revision-drift) test_verifier_rejects_source_revision_drift ;;
    runtime-source-revision-drift) test_verifier_rejects_runtime_source_revision_drift ;;
    released-reuse) test_rejects_released_pair_reuse ;;
    exact-tag) test_allows_exact_tagged_release ;;
    modern-tag-later-build) test_allows_modern_exact_tag_rebuild_after_later_build ;;
    legacy-merge-tag) test_allows_legacy_merge_tagged_release ;;
    exact-tag-laundering) test_rejects_exact_tag_laundering ;;
    cross-version-lower-tag) test_rejects_cross_version_lower_build_exact_tag ;;
    cross-version-equal-tag) test_rejects_cross_version_equal_build_exact_tag ;;
    legacy-tag-pair-reuse) test_rejects_legacy_pair_reuse_across_release_tags ;;
    new-source-reuse) test_rejects_new_source_with_same_build ;;
    same-commit) test_allows_same_commit_rebuild ;;
    dirty-tracked) test_rejects_dirty_tracked_source ;;
    dirty-untracked) test_rejects_dirty_untracked_source ;;
    ignored-input) test_build_ignores_ignored_swift_input ;;
    dirty-verifier) test_verifier_rejects_dirty_source ;;
    dirty-during-build) test_rejects_source_change_during_build ;;
    transient-mutation) test_build_uses_snapshot_during_transient_mutation ;;
    compiled-source-revision) test_fake_runtime_retains_compiled_source_revision ;;
    dirty-tag) test_rejects_dirty_exact_tagged_release ;;
    incomplete-tags) test_rejects_incomplete_local_tags ;;
    no-tags) test_rejects_no_tag_provenance ;;
    stale-evidence) test_rejects_stale_matching_tag_evidence ;;
    remote-query-failure) test_rejects_remote_tag_query_failure ;;
    failed-local-enumeration) test_rejects_failed_local_tag_enumeration ;;
    malformed-remote-tags) test_rejects_malformed_remote_tags ;;
    shallow) test_rejects_shallow_history ;;
    divergent) test_rejects_divergent_identity_reuse ;;
    merge-parent) test_rejects_merge_parent_identity_reuse ;;
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
        test_verifier_rejects_source_revision_drift
        test_verifier_rejects_runtime_source_revision_drift
        test_rejects_released_pair_reuse
        test_allows_exact_tagged_release
        test_allows_modern_exact_tag_rebuild_after_later_build
        test_allows_legacy_merge_tagged_release
        test_rejects_exact_tag_laundering
        test_rejects_cross_version_lower_build_exact_tag
        test_rejects_cross_version_equal_build_exact_tag
        test_rejects_legacy_pair_reuse_across_release_tags
        test_rejects_new_source_with_same_build
        test_allows_same_commit_rebuild
        test_rejects_dirty_tracked_source
        test_rejects_dirty_untracked_source
        test_build_ignores_ignored_swift_input
        test_verifier_rejects_dirty_source
        test_rejects_source_change_during_build
        test_build_uses_snapshot_during_transient_mutation
        test_fake_runtime_retains_compiled_source_revision
        test_rejects_dirty_exact_tagged_release
        test_rejects_incomplete_local_tags
        test_rejects_no_tag_provenance
        test_rejects_stale_matching_tag_evidence
        test_rejects_remote_tag_query_failure
        test_rejects_failed_local_tag_enumeration
        test_rejects_malformed_remote_tags
        test_rejects_shallow_history
        test_rejects_divergent_identity_reuse
        test_rejects_merge_parent_identity_reuse
        ;;
    *)
        printf 'unknown test case: %s\n' "$1" >&2
        exit 2
        ;;
esac

printf 'PASS: candidate version source, packaging, runtime, and reuse contracts\n'
