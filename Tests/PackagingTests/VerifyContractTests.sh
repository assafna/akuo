#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-verify-tests.XXXXXX")"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

AKUO_CONTRACT_PROJECT="$AKUO_TEST_TMP/contract-project"
AKUO_CONTRACT_BIN="$AKUO_TEST_TMP/contract-bin"
AKUO_STAGE_LOG="$AKUO_TEST_TMP/stages.log"
mkdir -p \
    "$AKUO_CONTRACT_PROJECT/Scripts" \
    "$AKUO_CONTRACT_PROJECT/Tests/PackagingTests" \
    "$AKUO_CONTRACT_BIN"

if [[ ! -x "$AKUO_TEST_ROOT/Scripts/verify.sh" ]]; then
    echo "FAIL: Scripts/verify.sh is missing or not executable" >&2
    exit 1
fi
cp "$AKUO_TEST_ROOT/Scripts/verify.sh" "$AKUO_CONTRACT_PROJECT/Scripts/verify.sh"

akuo_write_stub() {
    local stub_path="$1"
    shift

    printf '%s\n' "$@" >"$stub_path"
    chmod +x "$stub_path"
}

# Stub bodies are single-quoted so their variables expand when each generated
# command runs, not while this test writes the command.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Tests/PackagingTests/VerifyContractTests.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "verify-contract\n" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != verify-contract ]] || exit 40'
# Production mutation caught: omitting the executable candidate-version contract
# suite from the unified verifier or running later stages after it fails.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Tests/PackagingTests/CandidateVersionContractTests.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "candidate-version-contract\n" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != candidate-version-contract ]] || exit 44'
# Production mutation caught: omitting the executable build-manifest contract
# suite from the unified verifier or running later stages after it fails.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Tests/PackagingTests/BuildManifestContractTests.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "build-manifest-contract\n" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != build-manifest-contract ]] || exit 46'
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_BIN/swift" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "swift %s\n" "$*" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != swift ]] || exit 41'
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Tests/PackagingTests/LocalSigningContractTests.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "local-signing\n" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != local-signing ]] || exit 42'
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Scripts/build-app.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "build %s\n" "$*" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != build ]] || exit 43'
# Production mutation caught: trusting packaging's self-check instead of
# independently comparing the final app plist and runtime identity after build.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Scripts/verify-candidate-version.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "candidate-version-verify %s\n" "$*" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != candidate-version-verify ]] || exit 45'
# Production mutation caught: omitting independent manifest verification after
# the candidate has been built and its candidate version has been checked.
# shellcheck disable=SC2016
akuo_write_stub "$AKUO_CONTRACT_PROJECT/Scripts/verify-build-manifest.sh" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "build-manifest-verify %s\n" "$*" >>"${AKUO_STAGE_LOG:?}"' \
    '[[ "${AKUO_FAIL_STAGE:-}" != build-manifest-verify ]] || exit 47'

akuo_assert_run() {
    local failure_stage="$1"
    local expected_status="$2"
    local expected_log="$3"
    local status
    local actual_log

    rm -f "$AKUO_STAGE_LOG"
    set +e
    (
        cd "$AKUO_TEST_TMP"
        env \
            PATH="$AKUO_CONTRACT_BIN:$PATH" \
            AKUO_FAIL_STAGE="$failure_stage" \
            AKUO_STAGE_LOG="$AKUO_STAGE_LOG" \
            "$AKUO_CONTRACT_PROJECT/Scripts/verify.sh"
    )
    status=$?
    set -e

    if [[ "$status" -ne "$expected_status" ]]; then
        printf 'FAIL: stage %q returned %d, expected %d\n' \
            "$failure_stage" "$status" "$expected_status" >&2
        exit 1
    fi
    actual_log="$(<"$AKUO_STAGE_LOG")"
    if [[ "$actual_log" != "$expected_log" ]]; then
        printf 'FAIL: stage %q produced the wrong execution log\nexpected:\n%s\nactual:\n%s\n' \
            "$failure_stage" "$expected_log" "$actual_log" >&2
        exit 1
    fi
}

akuo_assert_run "" 0 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing\nswift test\nbuild release\ncandidate-version-verify dist/Akuo.app\nbuild-manifest-verify dist/Akuo.app dist/Akuo.build-manifest.json'
akuo_assert_run verify-contract 40 'verify-contract'
akuo_assert_run candidate-version-contract 44 $'verify-contract\ncandidate-version-contract'
akuo_assert_run build-manifest-contract 46 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract'
akuo_assert_run local-signing 42 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing'
akuo_assert_run swift 41 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing\nswift test'
akuo_assert_run build 43 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing\nswift test\nbuild release'
akuo_assert_run candidate-version-verify 45 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing\nswift test\nbuild release\ncandidate-version-verify dist/Akuo.app'
akuo_assert_run build-manifest-verify 47 $'verify-contract\ncandidate-version-contract\nbuild-manifest-contract\nlocal-signing\nswift test\nbuild release\ncandidate-version-verify dist/Akuo.app\nbuild-manifest-verify dist/Akuo.app dist/Akuo.build-manifest.json'

printf 'PASS: unified verification order and fail-fast propagation\n'
