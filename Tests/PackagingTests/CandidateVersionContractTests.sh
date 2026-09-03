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
        "$AKUO_FIXTURE_ROOT" "$AKUO_ORIGIN_ROOT" "$AKUO_FAKE_BIN" "$AKUO_BUILD_BIN"
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
        'if [[ "${AKUO_MUTATE_DURING_BUILD:-}" == true && " $* " != *" --show-bin-path "* ]]; then' \
        '    printf "mutated during build\n" >>"${AKUO_FIXTURE_ROOT_ENV:?}/README.md"' \
        'fi' \
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
        AKUO_BUILD_BIN="$AKUO_BUILD_BIN" \
        AKUO_FIXTURE_ROOT_ENV="$AKUO_FIXTURE_ROOT" \
        AKUO_RELEASE_TAGS_EVIDENCE="$AKUO_TAG_EVIDENCE" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        "$AKUO_FIXTURE_ROOT/Scripts/build-app.sh" release
}

akuo_verify() {
    env \
        PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_RELEASE_TAGS_EVIDENCE="$AKUO_TAG_EVIDENCE" \
        AKUO_RUNTIME_IDENTITY="${AKUO_RUNTIME_IDENTITY:-0.4.0	4}" \
        AKUO_SOURCE_REVISION="${AKUO_SOURCE_REVISION:-}" \
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

# Production mutation caught: trusting a v-tag name instead of inspecting the
# tagged source/plist identity and rejecting its released pair on a later commit.
test_rejects_released_pair_reuse() {
    akuo_reset_fixture
    akuo_write_identity_source 'public static let current = "0.4.0"' ''
    akuo_write_template 0.4.0 4
    akuo_commit 'legacy tagged source identity'
    git -C "$AKUO_FIXTURE_ROOT" tag -a v9.9.9 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v9.9.9
    akuo_refresh_tag_evidence
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
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_refresh_tag_evidence
    akuo_build >/dev/null
    akuo_verify >/dev/null
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

# Production mutation caught: allowing dirty source merely because HEAD is an
# exact release-tag commit.
test_rejects_dirty_exact_tagged_release() {
    akuo_reset_fixture
    git -C "$AKUO_FIXTURE_ROOT" tag -a v0.4.0 -m 'fixture release'
    git -C "$AKUO_FIXTURE_ROOT" push -q origin v0.4.0
    akuo_refresh_tag_evidence
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

# Production mutation caught: accepting a checkout that has neither release tags
# nor explicit remote provenance proving the tag set is complete.
test_rejects_no_tag_provenance() {
    akuo_reset_fixture
    AKUO_TAG_EVIDENCE="$AKUO_TEST_TMP/missing-release-tags.evidence" \
        akuo_assert_rejected 'cannot prove complete released-tag provenance' akuo_build
}

# Production mutation caught: losing a tag-enumeration failure through process
# substitution and continuing with an empty release set.
test_rejects_failed_local_tag_enumeration() {
    akuo_reset_fixture
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_FAKE_BIN/git" \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'if [[ " $* " == *" tag --list "* ]]; then exit 71; fi' \
        'exec "${AKUO_SYSTEM_GIT:?}" "$@"'
    chmod +x "$AKUO_FAKE_BIN/git"
    AKUO_SYSTEM_GIT="$AKUO_SYSTEM_GIT" \
        akuo_assert_rejected 'cannot enumerate local release tags' akuo_build
}

# Production mutation caught: accepting local tags when the explicit complete
# inventory evidence is malformed and cannot prove provenance.
test_rejects_malformed_tag_evidence() {
    akuo_reset_fixture
    akuo_write_file "$AKUO_TAG_EVIDENCE" 'not-a-valid-tag-inventory'
    akuo_assert_rejected 'cannot prove complete released-tag provenance' akuo_build
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
    released-reuse) test_rejects_released_pair_reuse ;;
    exact-tag) test_allows_exact_tagged_release ;;
    new-source-reuse) test_rejects_new_source_with_same_build ;;
    same-commit) test_allows_same_commit_rebuild ;;
    dirty-tracked) test_rejects_dirty_tracked_source ;;
    dirty-untracked) test_rejects_dirty_untracked_source ;;
    dirty-verifier) test_verifier_rejects_dirty_source ;;
    dirty-during-build) test_rejects_source_change_during_build ;;
    dirty-tag) test_rejects_dirty_exact_tagged_release ;;
    incomplete-tags) test_rejects_incomplete_local_tags ;;
    no-tags) test_rejects_no_tag_provenance ;;
    failed-local-enumeration) test_rejects_failed_local_tag_enumeration ;;
    malformed-tag-evidence) test_rejects_malformed_tag_evidence ;;
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
        test_rejects_released_pair_reuse
        test_allows_exact_tagged_release
        test_rejects_new_source_with_same_build
        test_allows_same_commit_rebuild
        test_rejects_dirty_tracked_source
        test_rejects_dirty_untracked_source
        test_verifier_rejects_dirty_source
        test_rejects_source_change_during_build
        test_rejects_dirty_exact_tagged_release
        test_rejects_incomplete_local_tags
        test_rejects_no_tag_provenance
        test_rejects_failed_local_tag_enumeration
        test_rejects_malformed_tag_evidence
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
