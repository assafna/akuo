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
AKUO_VERIFIER_MUTATION_MARKER="$AKUO_TEST_TMP/verifier-mutation.started"
AKUO_VERIFIER_RESTORE_MARKER="$AKUO_TEST_TMP/verifier-mutation.restored"
AKUO_VERIFIER_SOURCE_BACKUP="$AKUO_TEST_TMP/verifier-version.backup"

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
    local fixture_mode="${1:-candidate}"

    if [[ "$fixture_mode" != candidate && "$fixture_mode" != legacy ]]; then
        printf 'unknown fixture mode: %s\n' "$fixture_mode" >&2
        return 2
    fi
    rm -rf -- \
        "$AKUO_FIXTURE_ROOT" "$AKUO_ORIGIN_ROOT" "$AKUO_FAKE_BIN" "$AKUO_BUILD_BIN" \
        "$AKUO_BUILD_INPUT_LOG" "$AKUO_BUILD_CWD_LOG" \
        "$AKUO_VERIFIER_MUTATION_MARKER" "$AKUO_VERIFIER_RESTORE_MARKER" \
        "$AKUO_VERIFIER_SOURCE_BACKUP"
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
    akuo_write_file "$AKUO_FIXTURE_ROOT/Package.swift" \
        '// executable packaging-contract fixture manifest'
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
        '        cat Package.swift' \
        '        if [[ -f Sources/AkuoCore/Ignored.swift ]]; then printf "ignored-input\n"; fi' \
        '        cat Sources/AkuoCore/AkuoCoreVersion.swift' \
        '        cat Sources/AkuoCore/AkuoSourceRevision.swift' \
        '        cat Sources/AkuoMac/AkuoMacVersion.swift' \
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
        'if [[ "${AKUO_VERIFIER_MUTATE_THEN_RESTORE:-}" == true && " $* " == *" ls-tree -r --full-tree "* && ! -e "${AKUO_VERIFIER_MUTATION_MARKER:?}" ]]; then' \
        '    source_path="${AKUO_FIXTURE_ROOT_ENV:?}/Sources/AkuoCore/AkuoCoreVersion.swift"' \
        '    cp "$source_path" "${AKUO_VERIFIER_SOURCE_BACKUP:?}"' \
        '    printf '\''public enum AkuoCoreVersion {\n    public static let current = "0.5.0"\n    public static let build = "5"\n}\n'\'' >"$source_path"' \
        '    : >"${AKUO_VERIFIER_MUTATION_MARKER:?}"' \
        'fi' \
        'if [[ "${AKUO_VERIFIER_MUTATE_THEN_RESTORE:-}" == true && " $* " == *" show "* && -e "${AKUO_VERIFIER_MUTATION_MARKER:?}" && ! -e "${AKUO_VERIFIER_RESTORE_MARKER:?}" ]]; then' \
        '    cp "${AKUO_VERIFIER_SOURCE_BACKUP:?}" "${AKUO_FIXTURE_ROOT_ENV:?}/Sources/AkuoCore/AkuoCoreVersion.swift"' \
        '    : >"${AKUO_VERIFIER_RESTORE_MARKER:?}"' \
        'fi' \
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
    if [[ "$fixture_mode" == legacy ]]; then
        akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoMac/AkuoMacVersion.swift" \
            'import AkuoCore' \
            'public enum AkuoMacVersion {' \
            '    public static let current = AkuoCoreVersion.current' \
            '}'
    fi
    akuo_write_template 0.3.0 3
    akuo_commit 'released fixture identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.3.0 -m 'fixture release'
    if [[ "$fixture_mode" == candidate ]]; then
        akuo_write_identity_source \
            'public static let current = "0.4.0"' \
            'public static let build = "4"'
        akuo_write_template
        akuo_commit 'fixture candidate identity'
    fi

    git init -q --bare "$AKUO_ORIGIN_ROOT"
    git -C "$AKUO_FIXTURE_ROOT" remote add origin "$AKUO_ORIGIN_ROOT"
    git -C "$AKUO_FIXTURE_ROOT" push -q --set-upstream origin HEAD
    git -C "$AKUO_FIXTURE_ROOT" push -q origin --tags
    akuo_refresh_tag_evidence
}

akuo_replace_tracked_file_with_symlink() {
    local tracked_path="$1"
    local outside_path="$2"

    mkdir -p -- "$(dirname -- "$outside_path")"
    cp "$AKUO_FIXTURE_ROOT/$tracked_path" "$outside_path"
    rm -- "$AKUO_FIXTURE_ROOT/$tracked_path"
    ln -s "$outside_path" "$AKUO_FIXTURE_ROOT/$tracked_path"
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
        AKUO_VERIFIER_MUTATE_THEN_RESTORE="${AKUO_VERIFIER_MUTATE_THEN_RESTORE:-}" \
        AKUO_VERIFIER_MUTATION_MARKER="$AKUO_VERIFIER_MUTATION_MARKER" \
        AKUO_VERIFIER_RESTORE_MARKER="$AKUO_VERIFIER_RESTORE_MARKER" \
        AKUO_VERIFIER_SOURCE_BACKUP="$AKUO_VERIFIER_SOURCE_BACKUP" \
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

# Production mutation caught: treating an explicit Swift type annotation as an
# absent build declaration and falling back to plist-backed legacy metadata.
test_rejects_typed_build_instead_of_falling_back() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build: String = "8"'
    akuo_write_template 0.4.0 8
    akuo_commit 'typed build declaration'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'typed build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t8' \
        akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: accepting an attributed declaration that is not
# the one exact auditable Swift literal form required by candidate packaging.
test_rejects_attributed_build_instead_of_falling_back() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        '@available(*, deprecated) public static let build = "8"'
    akuo_write_template 0.4.0 8
    akuo_commit 'attributed build declaration'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'attributed build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t8' \
        akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: accepting an attribute on the line before an
# otherwise canonical literal and silently broadening the strict source form.
test_rejects_multiline_attributed_build() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        $'@available(*, deprecated)\n    public static let build = "8"'
    akuo_commit 'multiline attributed build declaration'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t8' \
        akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: reporting a typed marketing-version declaration
# as absent instead of rejecting the present but noncanonical declaration.
test_rejects_typed_version() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current: String = "0.4.0"' \
        'public static let build = "8"'
    akuo_commit 'typed version declaration'
    akuo_assert_rejected 'malformed authoritative current declaration' akuo_build
}

# Production mutation caught: allowing a typed build on a visible historical
# revision to become plist-backed legacy history and evade strict parsing.
test_rejects_typed_build_in_visible_history() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.5.0"' \
        'public static let build: String = "5"'
    akuo_write_template 0.5.0 5
    akuo_commit 'typed build in candidate history'
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "6"'
    akuo_write_template
    akuo_commit 'strict candidate after typed history'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t6' \
        akuo_assert_rejected 'malformed authoritative build declaration' akuo_build
}

# Production mutation caught: treating a present but invalid `var build`
# declaration in visible history as genuine pre-contract absence.
test_rejects_malformed_build_in_visible_history() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.5.0"' \
        'public static var build = "5"'
    akuo_write_template 0.5.0 5
    akuo_commit 'malformed build in candidate history'
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "6"'
    akuo_write_template
    akuo_commit 'strict candidate after malformed history'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t6' \
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

# Production mutation caught: reading version/build from mutable worktree bytes
# after capturing HEAD, so a transient edit can validate a mismatched bundle and
# then disappear before history inspection completes.
test_verifier_reads_identity_from_captured_head_object() {
    akuo_reset_fixture
    akuo_build >/dev/null
    local plist="$AKUO_FIXTURE_ROOT/dist/Akuo.app/Contents/Info.plist"
    local original_source
    original_source="$(cat "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift")"
    plutil -replace CFBundleShortVersionString -string 0.5.0 "$plist"
    plutil -replace CFBundleVersion -string 5 "$plist"

    AKUO_VERIFIER_MUTATE_THEN_RESTORE=true \
    AKUO_RUNTIME_IDENTITY=$'0.5.0\t5' \
        akuo_assert_rejected \
            'candidate plist identity does not match authoritative declaration' \
            akuo_verify
    [[ -e "$AKUO_VERIFIER_MUTATION_MARKER" ]]
    [[ -e "$AKUO_VERIFIER_RESTORE_MARKER" ]]
    [[ "$(cat "$AKUO_FIXTURE_ROOT/Sources/AkuoCore/AkuoCoreVersion.swift")" == \
        "$original_source" ]]
    [[ -z "$(git -C "$AKUO_FIXTURE_ROOT" status --porcelain=v1 --untracked-files=all)" ]]
}

# Production mutation caught: ignoring the Swift marketing version in a
# declaration-free release tag and later reusing that released version.
test_rejects_declaration_free_released_version_reuse() {
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
    akuo_assert_rejected 'candidate marketing version 0.4.0 was already released by v9.9.9' \
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

# Production mutation caught: letting the current pipeline package any source
# without both strict Swift identity declarations, even when a live tag and
# legacy plist happen to agree.
test_current_pipeline_rejects_legacy_source() {
    akuo_reset_fixture legacy
    AKUO_RUNTIME_IDENTITY=$'0.3.0\t3' \
        akuo_assert_rejected 'missing authoritative build declaration' akuo_build
}

# Production mutation caught: allowing a later declaration-free linear commit
# to retain its parent's plist identity merely because the matching release tag
# was moved to the later source revision.
test_rejects_legacy_linear_tag_laundering() {
    akuo_reset_fixture legacy
    akuo_write_file "$AKUO_FIXTURE_ROOT/later-legacy-source.txt" \
        'later declaration-free source with unchanged plist identity'
    akuo_commit 'later legacy source with reused identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -f -a v0.3.0 -m 'moved legacy release tag'
    git -C "$AKUO_FIXTURE_ROOT" push -q --force origin v0.3.0
    AKUO_RUNTIME_IDENTITY=$'0.3.0\t3' \
        akuo_assert_rejected 'missing authoritative build declaration' akuo_build
}

# Production mutation caught: moving a historical tag onto a later strict
# modern declaration with the same pair, then treating that exact tag as proof
# that the legacy release identity was never used by another source revision.
test_rejects_modern_tag_moved_from_legacy_pair() {
    akuo_reset_fixture legacy
    akuo_write_identity_source \
        'public static let current = "0.3.0"' \
        'public static let build = "3"'
    akuo_write_file "$AKUO_FIXTURE_ROOT/Sources/AkuoMac/AkuoMacVersion.swift" \
        'import AkuoCore' \
        'public enum AkuoMacVersion {' \
        '    public static let current = AkuoCoreVersion.current' \
        '    public static let build = AkuoCoreVersion.build' \
        '}'
    akuo_write_template
    akuo_write_file "$AKUO_FIXTURE_ROOT/modernized-release.txt" \
        'later strict source retaining the historical release pair'
    akuo_commit 'later strict source with historical identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -f -a v0.3.0 -m 'moved to strict source'
    git -C "$AKUO_FIXTURE_ROOT" push -q --force origin v0.3.0
    AKUO_RUNTIME_IDENTITY=$'0.3.0\t3' \
        akuo_assert_rejected \
            'candidate marketing version 0.3.0 is assigned to declaration-free historical source' \
            akuo_build
}

# Production mutation caught: replacing the immutable v0.3.0 tag's own build
# script with the modern pipeline or claiming modern runtime probes verified a
# release whose source never contained them.
test_real_v030_rebuilds_with_historical_tag_script() {
    local origin_tag
    local local_tag_object
    local historical_root="$AKUO_TEST_TMP/historical-v0.3.0"
    if ! origin_tag="$(
        "$AKUO_SYSTEM_GIT" -C "$AKUO_TEST_ROOT" \
            ls-remote --tags --refs origin refs/tags/v0.3.0
    )" || [[ ! "$origin_tag" =~ ^([0-9a-f]{40})[[:space:]]+refs/tags/v0\.3\.0$ ]]; then
        printf 'FAIL: cannot authenticate the live-origin v0.3.0 tag object\n' >&2
        return 1
    fi
    local_tag_object="$("$AKUO_SYSTEM_GIT" -C "$AKUO_TEST_ROOT" \
        rev-parse --verify refs/tags/v0.3.0)"
    if [[ "$local_tag_object" != "${BASH_REMATCH[1]}" || \
        "$("$AKUO_SYSTEM_GIT" -C "$AKUO_TEST_ROOT" cat-file -t refs/tags/v0.3.0)" != tag ]]; then
        printf 'FAIL: local annotated v0.3.0 tag does not match live origin\n' >&2
        return 1
    fi

    mkdir -p -- "$historical_root"
    "$AKUO_SYSTEM_GIT" -C "$AKUO_TEST_ROOT" archive --format=tar \
        "${local_tag_object}^{commit}" | tar -xf - -C "$historical_root"
    (
        cd "$historical_root"
        Scripts/build-app.sh release >/dev/null
    )
    local plist="$historical_root/dist/Akuo.app/Contents/Info.plist"
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == 0.3.0 ]]
    [[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == 3 ]]
    codesign --verify --deep --strict "$historical_root/dist/Akuo.app"
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

# Production mutation caught: treating a force-moved modern release tag as
# authority to reuse the same pair on a later linear source revision.
test_rejects_moved_modern_tag_laundering() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'initial fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_write_file "$AKUO_FIXTURE_ROOT/later-tagged-source.txt" \
        'later source retaining the released pair'
    akuo_commit 'later source with released identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -f -a v0.4.0 -m 'moved fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q --force origin v0.4.0
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

# Production mutation caught: ignoring a greater build on a visible divergent
# branch merely because the lower-build candidate is an exact modern tag.
test_rejects_divergent_lower_build_exact_tag() {
    akuo_reset_fixture
    local candidate_branch
    local candidate_commit
    local base_commit
    candidate_branch="$(git -C "$AKUO_FIXTURE_ROOT" branch --show-current)"
    candidate_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    base_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD^)"
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b divergent-higher-build "$base_commit"
    akuo_write_identity_source \
        'public static let current = "0.6.0"' \
        'public static let build = "7"'
    akuo_write_template
    akuo_commit 'divergent source with higher build'
    git -C "$AKUO_FIXTURE_ROOT" checkout -q "$candidate_branch"
    [[ "$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" == "$candidate_commit" ]]
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'invalid lower-build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_assert_rejected 'build identity 4 is already assigned to another source revision' \
        akuo_build
}

# Production mutation caught: treating an equal build on divergent visible
# history as advancement when an exact modern tag changes marketing version.
test_rejects_divergent_equal_build_exact_tag() {
    akuo_reset_fixture
    local candidate_branch
    local candidate_commit
    local base_commit
    candidate_branch="$(git -C "$AKUO_FIXTURE_ROOT" branch --show-current)"
    candidate_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    base_commit="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD^)"
    git -C "$AKUO_FIXTURE_ROOT" checkout -q -b divergent-equal-build "$base_commit"
    akuo_write_identity_source \
        'public static let current = "0.6.0"' \
        'public static let build = "4"'
    akuo_write_template
    akuo_commit 'divergent source with equal build'
    git -C "$AKUO_FIXTURE_ROOT" checkout -q "$candidate_branch"
    [[ "$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)" == "$candidate_commit" ]]
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'invalid equal-build release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_assert_rejected 'build identity 4 is already assigned to another source revision' \
        akuo_build
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

# Production mutation caught: resolving the runtime source revision from mutable
# repository state instead of compiling the snapshot-injected revision into Akuo.
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

# Production mutation caught: extracting and overwriting a tracked source-
# revision symlink, which can modify bytes outside the immutable snapshot.
test_rejects_tracked_source_revision_symlink() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "5"'
    local outside_path="$AKUO_TEST_TMP/outside/source-revision.swift"
    local outside_before="$AKUO_TEST_TMP/outside-before/source-revision.swift"
    akuo_replace_tracked_file_with_symlink \
        Sources/AkuoCore/AkuoSourceRevision.swift "$outside_path"
    mkdir -p -- "$(dirname -- "$outside_before")"
    cp "$outside_path" "$outside_before"
    akuo_commit 'tracked source-revision symlink'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t5' \
        akuo_assert_rejected 'tracked symlink' akuo_build
    if ! cmp -s "$outside_before" "$outside_path"; then
        printf 'FAIL: source-revision symlink target changed before rejection\n' >&2
        return 1
    fi
}

# Production mutation caught: letting SwiftPM resolve a tracked manifest symlink
# to mutable bytes outside the captured commit.
test_rejects_tracked_manifest_symlink() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "5"'
    local outside_path="$AKUO_TEST_TMP/outside/Package.swift"
    local outside_before="$AKUO_TEST_TMP/outside-before/Package.swift"
    akuo_replace_tracked_file_with_symlink Package.swift "$outside_path"
    mkdir -p -- "$(dirname -- "$outside_before")"
    cp "$outside_path" "$outside_before"
    akuo_commit 'tracked package manifest symlink'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t5' \
        akuo_assert_rejected 'tracked symlink' akuo_build
    if ! cmp -s "$outside_before" "$outside_path"; then
        printf 'FAIL: manifest symlink target changed before rejection\n' >&2
        return 1
    fi
}

# Production mutation caught: reading candidate configuration through a tracked
# symlink whose external target is not part of the committed archive.
test_rejects_tracked_configuration_symlink() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "5"'
    local outside_path="$AKUO_TEST_TMP/outside/Akuo-Info.plist"
    local outside_before="$AKUO_TEST_TMP/outside-before/Akuo-Info.plist"
    akuo_replace_tracked_file_with_symlink Configuration/Akuo-Info.plist "$outside_path"
    mkdir -p -- "$(dirname -- "$outside_before")"
    cp "$outside_path" "$outside_before"
    akuo_commit 'tracked configuration symlink'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t5' \
        akuo_assert_rejected 'tracked symlink' akuo_build
    if ! cmp -s "$outside_before" "$outside_path"; then
        printf 'FAIL: configuration symlink target changed before rejection\n' >&2
        return 1
    fi
}

# Production mutation caught: compiling a tracked source symlink whose external
# target can change without changing the candidate Git object.
test_rejects_tracked_source_symlink() {
    akuo_reset_fixture
    akuo_write_identity_source \
        'public static let current = "0.4.0"' \
        'public static let build = "5"'
    local outside_path="$AKUO_TEST_TMP/outside/AkuoMacVersion.swift"
    local outside_before="$AKUO_TEST_TMP/outside-before/AkuoMacVersion.swift"
    akuo_replace_tracked_file_with_symlink Sources/AkuoMac/AkuoMacVersion.swift \
        "$outside_path"
    mkdir -p -- "$(dirname -- "$outside_before")"
    cp "$outside_path" "$outside_before"
    akuo_commit 'tracked Swift source symlink'
    AKUO_RUNTIME_IDENTITY=$'0.4.0\t5' \
        akuo_assert_rejected 'tracked symlink' akuo_build
    if ! cmp -s "$outside_before" "$outside_path"; then
        printf 'FAIL: Swift-source symlink target changed before rejection\n' >&2
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
    typed-build) test_rejects_typed_build_instead_of_falling_back ;;
    attributed-build) test_rejects_attributed_build_instead_of_falling_back ;;
    multiline-attributed-build) test_rejects_multiline_attributed_build ;;
    typed-version) test_rejects_typed_version ;;
    history-typed-build) test_rejects_typed_build_in_visible_history ;;
    history-malformed-build) test_rejects_malformed_build_in_visible_history ;;
    runtime-drift) test_rejects_runtime_drift ;;
    plist-drift) test_verifier_rejects_candidate_plist_drift ;;
    source-revision-drift) test_verifier_rejects_source_revision_drift ;;
    runtime-source-revision-drift) test_verifier_rejects_runtime_source_revision_drift ;;
    verifier-captured-identity) test_verifier_reads_identity_from_captured_head_object ;;
    released-reuse) test_rejects_declaration_free_released_version_reuse ;;
    exact-tag) test_allows_exact_tagged_release ;;
    modern-tag-later-build) test_allows_modern_exact_tag_rebuild_after_later_build ;;
    current-rejects-legacy) test_current_pipeline_rejects_legacy_source ;;
    legacy-linear-laundering) test_rejects_legacy_linear_tag_laundering ;;
    legacy-to-modern-tag-laundering) test_rejects_modern_tag_moved_from_legacy_pair ;;
    historical-v030-build) test_real_v030_rebuilds_with_historical_tag_script ;;
    exact-tag-laundering) test_rejects_exact_tag_laundering ;;
    moved-modern-tag-laundering) test_rejects_moved_modern_tag_laundering ;;
    cross-version-lower-tag) test_rejects_cross_version_lower_build_exact_tag ;;
    cross-version-equal-tag) test_rejects_cross_version_equal_build_exact_tag ;;
    divergent-lower-tag) test_rejects_divergent_lower_build_exact_tag ;;
    divergent-equal-tag) test_rejects_divergent_equal_build_exact_tag ;;
    new-source-reuse) test_rejects_new_source_with_same_build ;;
    same-commit) test_allows_same_commit_rebuild ;;
    dirty-tracked) test_rejects_dirty_tracked_source ;;
    dirty-untracked) test_rejects_dirty_untracked_source ;;
    ignored-input) test_build_ignores_ignored_swift_input ;;
    dirty-verifier) test_verifier_rejects_dirty_source ;;
    dirty-during-build) test_rejects_source_change_during_build ;;
    transient-mutation) test_build_uses_snapshot_during_transient_mutation ;;
    compiled-source-revision) test_fake_runtime_retains_compiled_source_revision ;;
    symlink-source-revision) test_rejects_tracked_source_revision_symlink ;;
    symlink-manifest) test_rejects_tracked_manifest_symlink ;;
    symlink-configuration) test_rejects_tracked_configuration_symlink ;;
    symlink-source) test_rejects_tracked_source_symlink ;;
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
        test_rejects_typed_build_instead_of_falling_back
        test_rejects_attributed_build_instead_of_falling_back
        test_rejects_multiline_attributed_build
        test_rejects_typed_version
        test_rejects_typed_build_in_visible_history
        test_rejects_malformed_build_in_visible_history
        test_rejects_runtime_drift
        test_verifier_rejects_candidate_plist_drift
        test_verifier_rejects_source_revision_drift
        test_verifier_rejects_runtime_source_revision_drift
        test_verifier_reads_identity_from_captured_head_object
        test_rejects_declaration_free_released_version_reuse
        test_allows_exact_tagged_release
        test_allows_modern_exact_tag_rebuild_after_later_build
        test_current_pipeline_rejects_legacy_source
        test_rejects_legacy_linear_tag_laundering
        test_rejects_modern_tag_moved_from_legacy_pair
        test_real_v030_rebuilds_with_historical_tag_script
        test_rejects_exact_tag_laundering
        test_rejects_moved_modern_tag_laundering
        test_rejects_cross_version_lower_build_exact_tag
        test_rejects_cross_version_equal_build_exact_tag
        test_rejects_divergent_lower_build_exact_tag
        test_rejects_divergent_equal_build_exact_tag
        test_rejects_new_source_with_same_build
        test_allows_same_commit_rebuild
        test_rejects_dirty_tracked_source
        test_rejects_dirty_untracked_source
        test_build_ignores_ignored_swift_input
        test_verifier_rejects_dirty_source
        test_rejects_source_change_during_build
        test_build_uses_snapshot_during_transient_mutation
        test_fake_runtime_retains_compiled_source_revision
        test_rejects_tracked_source_revision_symlink
        test_rejects_tracked_manifest_symlink
        test_rejects_tracked_configuration_symlink
        test_rejects_tracked_source_symlink
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
