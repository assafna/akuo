#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-build-manifest-tests.XXXXXX")"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

AKUO_GENERATOR="$AKUO_TEST_ROOT/Scripts/generate-build-manifest.sh"
AKUO_VERIFIER="$AKUO_TEST_ROOT/Scripts/verify-build-manifest.sh"
AKUO_DIGEST="$AKUO_TEST_ROOT/Scripts/lib/bundle-content-digest.sh"
AKUO_FIXTURE_ROOT="$AKUO_TEST_TMP/project"
AKUO_APP_PATH="$AKUO_FIXTURE_ROOT/dist/Akuo.app"
AKUO_MANIFEST_PATH="$AKUO_FIXTURE_ROOT/dist/Akuo.build-manifest.json"
AKUO_FAKE_BIN="$AKUO_TEST_TMP/fake-bin"
AKUO_REQUIREMENT='designated => cdhash H"0123456789abcdef"'

for required_script in "$AKUO_GENERATOR" "$AKUO_VERIFIER" "$AKUO_DIGEST"; do
    if [[ ! -x "$required_script" ]]; then
        printf 'FAIL: required build-manifest script is missing or not executable: %s\n' \
            "$required_script" >&2
        exit 1
    fi
done

akuo_write_file() {
    local path="$1"
    shift

    mkdir -p -- "$(dirname -- "$path")"
    printf '%s\n' "$@" >"$path"
}

akuo_reset_fixture() {
    rm -rf -- "$AKUO_FIXTURE_ROOT" "$AKUO_FAKE_BIN"
    mkdir -p \
        "$AKUO_APP_PATH/Contents/MacOS" \
        "$AKUO_APP_PATH/Contents/Resources" \
        "$AKUO_FAKE_BIN"
    akuo_write_file "$AKUO_FIXTURE_ROOT/.gitignore" 'dist/'
    akuo_write_file "$AKUO_FIXTURE_ROOT/README.md" 'manifest contract fixture'
    akuo_write_file "$AKUO_APP_PATH/Contents/Info.plist" \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' \
        '  <key>CFBundleExecutable</key><string>Akuo</string>' \
        '  <key>CFBundleIdentifier</key><string>app.akuo.Akuo</string>' \
        '  <key>CFBundleShortVersionString</key><string>0.4.0</string>' \
        '  <key>CFBundleVersion</key><string>10</string>' \
        '  <key>AkuoSourceRevision</key><string>__SOURCE_REVISION__</string>' \
        '</dict></plist>'
    akuo_write_file "$AKUO_APP_PATH/Contents/MacOS/Akuo" '#!/usr/bin/env bash' 'exit 0'
    chmod 755 "$AKUO_APP_PATH/Contents/MacOS/Akuo"
    akuo_write_file "$AKUO_APP_PATH/Contents/Resources/notice.txt" 'fixture resource'

    git -C "$AKUO_FIXTURE_ROOT" init -q
    git -C "$AKUO_FIXTURE_ROOT" config user.name 'Akuo Manifest Contract'
    git -C "$AKUO_FIXTURE_ROOT" config user.email manifest-contract@example.invalid
    git -C "$AKUO_FIXTURE_ROOT" add .
    git -C "$AKUO_FIXTURE_ROOT" commit -q -m 'manifest fixture source'
    AKUO_SOURCE_REVISION="$(git -C "$AKUO_FIXTURE_ROOT" rev-parse HEAD)"
    sed -i '' "s/__SOURCE_REVISION__/$AKUO_SOURCE_REVISION/" \
        "$AKUO_APP_PATH/Contents/Info.plist"

    akuo_write_file "$AKUO_FAKE_BIN/swift" \
        '#!/usr/bin/env bash' \
        'printf '\''Swift version 6.1-dev "manifest"\ntarget: arm64-apple-macosx15.0\n'\'''
    akuo_write_file "$AKUO_FAKE_BIN/xcodebuild" \
        '#!/usr/bin/env bash' \
        'printf '\''Xcode 16.4\nBuild version 16F6\n'\'''
    # shellcheck disable=SC2016
    akuo_write_file "$AKUO_FAKE_BIN/codesign" \
        '#!/usr/bin/env bash' \
        'if [[ " $* " == *" -d -r- "* ]]; then' \
        '    printf '\''Executable=fixture\n# designated => cdhash H"0123456789abcdef"\n'\'' >&2' \
        'elif [[ " $* " == *" --verify --deep --strict "* && "${AKUO_CODESIGN_VERIFY_FAIL:-}" == true ]]; then' \
        '    printf '\''strict signature verification failed\n'\'' >&2' \
        '    exit 91' \
        'fi'
    chmod +x "$AKUO_FAKE_BIN/swift" "$AKUO_FAKE_BIN/xcodebuild" \
        "$AKUO_FAKE_BIN/codesign"
}

akuo_generate() {
    env PATH="$AKUO_FAKE_BIN:$PATH" \
        "$AKUO_GENERATOR" \
        "$AKUO_APP_PATH" \
        "$AKUO_MANIFEST_PATH" \
        "$AKUO_SOURCE_REVISION" \
        clean
}

akuo_verify() {
    env PATH="$AKUO_FAKE_BIN:$PATH" \
        "$AKUO_VERIFIER" "$AKUO_APP_PATH" "$AKUO_MANIFEST_PATH"
}

akuo_generate_with_invalid_signature() {
    env PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_CODESIGN_VERIFY_FAIL=true \
        "$AKUO_GENERATOR" \
        "$AKUO_APP_PATH" \
        "$AKUO_MANIFEST_PATH" \
        "$AKUO_SOURCE_REVISION" \
        clean
}

akuo_verify_with_invalid_signature() {
    env PATH="$AKUO_FAKE_BIN:$PATH" \
        AKUO_CODESIGN_VERIFY_FAIL=true \
        "$AKUO_VERIFIER" "$AKUO_APP_PATH" "$AKUO_MANIFEST_PATH"
}

akuo_verify_app_path() {
    local app_path="$1"

    env PATH="$AKUO_FAKE_BIN:$PATH" \
        "$AKUO_VERIFIER" "$app_path" "$AKUO_MANIFEST_PATH"
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

# Production mutation caught: changing the documented canonical digest stream,
# omitting file path/mode/size/content, or accidentally including bundle mtime.
test_canonical_digest_has_a_literal_contract() {
    local digest_root="$AKUO_TEST_TMP/digest-fixture"
    rm -rf -- "$digest_root"
    mkdir -p "$digest_root"
    printf x >"$digest_root/payload"
    chmod 644 "$digest_root/payload"

    [[ "$("$AKUO_DIGEST" "$digest_root")" == \
        0fc9bfa84cda150e0ad3e0b9689b4b6f5565b266ddd980af402d7ed3f2b6577a ]]
    touch -t 202001020304 "$digest_root/payload"
    [[ "$("$AKUO_DIGEST" "$digest_root")" == \
        0fc9bfa84cda150e0ad3e0b9689b4b6f5565b266ddd980af402d7ed3f2b6577a ]]
}

# Production mutation caught: normalizing JSON through plutil before checking
# duplicate top-level keys, allowing an ambiguous manifest to be accepted.
test_rejects_duplicate_json_keys_before_normalization() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    cp "$AKUO_MANIFEST_PATH" "$AKUO_TEST_TMP/canonical-manifest.json"
    sed 's/^{/{"schemaVersion":1,/' "$AKUO_MANIFEST_PATH" \
        >"$AKUO_TEST_TMP/duplicate-manifest.json"
    mv "$AKUO_TEST_TMP/duplicate-manifest.json" "$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'manifest contains a duplicate JSON key: schemaVersion' \
        akuo_verify

    sed 's/^{/{"\\u0073chemaVersion":1,/' \
        "$AKUO_TEST_TMP/canonical-manifest.json" \
        >"$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'manifest JSON keys must use canonical ASCII spelling' \
        akuo_verify
}

# Production mutation caught: omitting a required provenance field, emitting a
# wrong JSON type, or interpolating quotes/newlines without JSON escaping.
test_emits_complete_typed_manifest_and_verifies_it() {
    akuo_reset_fixture
    akuo_generate >/dev/null

    [[ "$(plutil -type schemaVersion "$AKUO_MANIFEST_PATH")" == integer ]]
    [[ "$(plutil -extract schemaVersion raw -o - "$AKUO_MANIFEST_PATH")" == 1 ]]
    [[ "$(plutil -extract gitHead raw -o - "$AKUO_MANIFEST_PATH")" == \
        "$AKUO_SOURCE_REVISION" ]]
    [[ "$(plutil -extract sourceState raw -o - "$AKUO_MANIFEST_PATH")" == clean ]]
    [[ "$(plutil -extract swiftVersion raw -o - "$AKUO_MANIFEST_PATH")" == \
        $'Swift version 6.1-dev "manifest"\ntarget: arm64-apple-macosx15.0' ]]
    [[ "$(plutil -extract xcodeVersion raw -o - "$AKUO_MANIFEST_PATH")" == \
        $'Xcode 16.4\nBuild version 16F6' ]]
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "$AKUO_MANIFEST_PATH")" == \
        app.akuo.Akuo ]]
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$AKUO_MANIFEST_PATH")" == \
        0.4.0 ]]
    [[ "$(plutil -extract CFBundleVersion raw -o - "$AKUO_MANIFEST_PATH")" == 10 ]]
    [[ "$(plutil -extract designatedRequirement raw -o - "$AKUO_MANIFEST_PATH")" == \
        "$AKUO_REQUIREMENT" ]]
    [[ "$(plutil -extract executableSHA256 raw -o - "$AKUO_MANIFEST_PATH")" =~ \
        ^[0-9a-f]{64}$ ]]
    [[ "$(plutil -extract bundleContentSHA256 raw -o - "$AKUO_MANIFEST_PATH")" =~ \
        ^[0-9a-f]{64}$ ]]
    akuo_verify >/dev/null
}

# Production mutation caught: trusting a recorded executable digest instead of
# independently hashing the final executable during verification.
test_rejects_executable_tampering() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    printf '\n# tampered\n' >>"$AKUO_APP_PATH/Contents/MacOS/Akuo"
    akuo_assert_rejected 'executable SHA-256 does not match manifest' akuo_verify
}

# Production mutation caught: hashing only the executable rather than every
# regular file and directory record in the app bundle.
test_rejects_non_executable_bundle_tampering() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    printf '\ntampered\n' >>"$AKUO_APP_PATH/Contents/Resources/notice.txt"
    akuo_assert_rejected 'bundle content SHA-256 does not match manifest' akuo_verify
}

# Production mutation caught: omitting permission modes from the canonical
# bundle digest.
test_rejects_bundle_mode_tampering() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    chmod 600 "$AKUO_APP_PATH/Contents/Resources/notice.txt"
    akuo_assert_rejected 'bundle content SHA-256 does not match manifest' akuo_verify
}

# Production mutation caught: excluding the bundle root directory's permission
# mode from the canonical digest.
test_rejects_bundle_root_mode_tampering() {
    akuo_reset_fixture
    chmod 755 "$AKUO_APP_PATH"
    akuo_generate >/dev/null
    chmod 700 "$AKUO_APP_PATH"
    akuo_assert_rejected 'bundle content SHA-256 does not match manifest' akuo_verify
}

# Production mutation caught: resolving a symlink supplied as the bundle root
# and hashing its target as though the requested root were an ordinary directory.
test_rejects_bundle_root_symlink() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    local linked_app="$AKUO_TEST_TMP/LinkedAkuo.app"
    ln -s "$AKUO_APP_PATH" "$linked_app"
    akuo_assert_rejected 'bundle root must not be a symbolic link' \
        akuo_verify_app_path "$linked_app"
}

# Production mutation caught: following or ignoring a newly introduced bundle
# symlink instead of failing closed on an unsupported entry type.
test_rejects_bundle_symlinks() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    ln -s notice.txt "$AKUO_APP_PATH/Contents/Resources/linked-notice"
    akuo_assert_rejected 'unsupported symbolic link in bundle' akuo_verify
}

# Production mutation caught: trusting manifest metadata rather than reading the
# produced bundle's Info.plist during independent verification.
test_rejects_bundle_metadata_mismatch() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    plutil -replace CFBundleVersion -string 11 "$AKUO_APP_PATH/Contents/Info.plist"
    akuo_assert_rejected 'CFBundleVersion does not match bundle metadata' akuo_verify
}

# Production mutation caught: trusting the manifest's designated requirement
# instead of independently extracting it from the produced bundle signature.
test_rejects_designated_requirement_mismatch() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    plutil -replace designatedRequirement \
        -string 'designated => cdhash H"fedcba9876543210"' \
        "$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'designatedRequirement does not match bundle signature' \
        akuo_verify
}

# Production mutation caught: extracting a displayed designated requirement
# without first requiring the bundle to pass deep, strict signature verification.
test_generator_and_verifier_reject_invalid_signature() {
    akuo_reset_fixture
    local displayed_requirement
    displayed_requirement="$(
        env PATH="$AKUO_FAKE_BIN:$PATH" \
            AKUO_CODESIGN_VERIFY_FAIL=true \
            codesign -d -r- "$AKUO_APP_PATH" 2>&1
    )"
    [[ "$displayed_requirement" == *"$AKUO_REQUIREMENT"* ]]
    akuo_assert_rejected 'bundle failed strict code-signature verification' \
        akuo_generate_with_invalid_signature

    akuo_generate >/dev/null
    akuo_assert_rejected 'bundle failed strict code-signature verification' \
        akuo_verify_with_invalid_signature
}

# Production mutation caught: narrowing sourceState to clean even though schema
# 1 represents either captured state at the low-level manifest contract.
test_dirty_source_state_round_trips() {
    akuo_reset_fixture
    env PATH="$AKUO_FAKE_BIN:$PATH" \
        "$AKUO_GENERATOR" \
        "$AKUO_APP_PATH" \
        "$AKUO_MANIFEST_PATH" \
        "$AKUO_SOURCE_REVISION" \
        dirty >/dev/null
    [[ "$(plutil -extract sourceState raw -o - "$AKUO_MANIFEST_PATH")" == dirty ]]
    [[ "$(akuo_verify)" == *"Source: $AKUO_SOURCE_REVISION (dirty)"* ]]
}

# Production mutation caught: permissive dictionary decoding that ignores
# missing, additional, or wrong-typed manifest fields.
test_rejects_non_exact_manifest_schema() {
    akuo_reset_fixture
    akuo_generate >/dev/null
    cp "$AKUO_MANIFEST_PATH" "$AKUO_TEST_TMP/original-manifest.json"

    plutil -remove swiftVersion "$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'manifest keys do not exactly match schema' akuo_verify
    cp "$AKUO_TEST_TMP/original-manifest.json" "$AKUO_MANIFEST_PATH"

    plutil -insert unexpectedField -string surprise "$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'manifest keys do not exactly match schema' akuo_verify
    cp "$AKUO_TEST_TMP/original-manifest.json" "$AKUO_MANIFEST_PATH"

    plutil -replace schemaVersion -string 1 "$AKUO_MANIFEST_PATH"
    akuo_assert_rejected 'manifest field schemaVersion must have type integer' \
        akuo_verify
}

case "${1:-all}" in
    canonical-digest) test_canonical_digest_has_a_literal_contract ;;
    duplicate-json-keys) test_rejects_duplicate_json_keys_before_normalization ;;
    complete-manifest) test_emits_complete_typed_manifest_and_verifies_it ;;
    executable-tampering) test_rejects_executable_tampering ;;
    bundle-tampering) test_rejects_non_executable_bundle_tampering ;;
    bundle-mode) test_rejects_bundle_mode_tampering ;;
    bundle-root-mode) test_rejects_bundle_root_mode_tampering ;;
    bundle-root-symlink) test_rejects_bundle_root_symlink ;;
    bundle-symlink) test_rejects_bundle_symlinks ;;
    metadata-mismatch) test_rejects_bundle_metadata_mismatch ;;
    requirement-mismatch) test_rejects_designated_requirement_mismatch ;;
    invalid-signature) test_generator_and_verifier_reject_invalid_signature ;;
    dirty-source-state) test_dirty_source_state_round_trips ;;
    exact-schema) test_rejects_non_exact_manifest_schema ;;
    all)
        test_canonical_digest_has_a_literal_contract
        test_rejects_duplicate_json_keys_before_normalization
        test_emits_complete_typed_manifest_and_verifies_it
        test_rejects_executable_tampering
        test_rejects_non_executable_bundle_tampering
        test_rejects_bundle_mode_tampering
        test_rejects_bundle_root_mode_tampering
        test_rejects_bundle_root_symlink
        test_rejects_bundle_symlinks
        test_rejects_bundle_metadata_mismatch
        test_rejects_designated_requirement_mismatch
        test_generator_and_verifier_reject_invalid_signature
        test_dirty_source_state_round_trips
        test_rejects_non_exact_manifest_schema
        ;;
    *)
        printf 'unknown test case: %s\n' "$1" >&2
        exit 2
        ;;
esac

printf 'PASS: build manifest generation, schema, and tamper-detection contracts\n'
