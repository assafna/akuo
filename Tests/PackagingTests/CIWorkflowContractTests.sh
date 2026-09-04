#!/usr/bin/env bash
set -euo pipefail

AKUO_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
AKUO_WORKFLOW="$AKUO_TEST_ROOT/.github/workflows/ci.yml"

if [[ ! -f "$AKUO_WORKFLOW" ]]; then
    echo "FAIL: macOS CI workflow is missing: $AKUO_WORKFLOW" >&2
    exit 1
fi

AKUO_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-ci-workflow-tests.XXXXXX")"
AKUO_TEST_TMP="$(cd -- "$AKUO_TEST_TMP" && pwd -P)"
trap 'rm -rf -- "$AKUO_TEST_TMP"' EXIT

AKUO_RUN_SCRIPT="$AKUO_TEST_TMP/verify-step.sh"
AKUO_DEVELOPER_DIR="$AKUO_TEST_TMP/developer-dir.txt"
AKUO_VALIDATOR="$AKUO_TEST_TMP/validate-workflow.rb"

cat >"$AKUO_VALIDATOR" <<'RUBY'
require "yaml"

def fail_contract(message)
  warn "FAIL: #{message}"
  exit 1
end

workflow_path, run_script_path, developer_dir_path = ARGV
workflow = YAML.safe_load(File.read(workflow_path), aliases: false)
fail_contract("workflow root must be a mapping") unless workflow.is_a?(Hash)

fail_contract("workflow name must remain CI") unless workflow["name"] == "CI"

# Psych implements YAML 1.1, where an unquoted `on` key is parsed as true.
triggers = workflow.key?("on") ? workflow["on"] : workflow[true]
fail_contract("workflow must define trigger mappings") unless triggers.is_a?(Hash)
fail_contract("workflow must run only for pull requests and pushes") unless triggers.keys.sort == ["pull_request", "push"]
fail_contract("pull_request trigger must not be restricted") unless triggers["pull_request"].nil?
push = triggers["push"]
fail_contract("push trigger must be a mapping") unless push.is_a?(Hash)
fail_contract("push trigger must be limited to main") unless push == {"branches" => ["main"]}

fail_contract("workflow permissions must be read-only contents") unless workflow["permissions"] == {"contents" => "read"}

concurrency = workflow["concurrency"]
fail_contract("workflow concurrency must be a mapping") unless concurrency.is_a?(Hash)
expected_group = '${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}'
expected_cancel = "${{ github.event_name == 'pull_request' }}"
fail_contract("concurrency group must isolate pull requests and refs") unless concurrency["group"] == expected_group
fail_contract("only superseded pull-request runs may be cancelled") unless concurrency["cancel-in-progress"] == expected_cancel

jobs = workflow["jobs"]
fail_contract("workflow must expose exactly one stable verify job") unless jobs.is_a?(Hash) && jobs.keys == ["verify"]
job = jobs["verify"]
fail_contract("verify job must be a mapping") unless job.is_a?(Hash)
allowed_job_keys = ["env", "name", "runs-on", "steps"]
fail_contract("verify job must not override permissions, failure handling, or gating") unless job.keys.sort == allowed_job_keys
fail_contract("stable job name must remain verify") unless job["name"] == "verify"
fail_contract("verify job must use the supported macos-15 runner") unless job["runs-on"] == "macos-15"

expected_developer_dir = "/Applications/Xcode_16.4.app/Contents/Developer"
fail_contract("verify job must select the pinned Xcode 16.4 toolchain") unless job["env"] == {"DEVELOPER_DIR" => expected_developer_dir}

steps = job["steps"]
fail_contract("verify job must contain checkout and verification steps only") unless steps.is_a?(Array) && steps.length == 2
checkout, verification = steps
expected_checkout_options = {
  "fetch-depth" => 0,
  "persist-credentials" => false,
}
expected_checkout = "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
fail_contract("first step must use pinned checkout v4.2.2 with complete history and no persisted credentials") unless checkout.is_a?(Hash) && checkout["uses"] == expected_checkout && checkout["with"] == expected_checkout_options && checkout.keys.sort == ["name", "uses", "with"]
fail_contract("second step must be the only command step") unless verification.is_a?(Hash) && verification.keys.sort == ["name", "run"]
run_script = verification["run"]
fail_contract("verification command must be a nonempty string") unless run_script.is_a?(String) && !run_script.strip.empty?

File.write(run_script_path, run_script)
File.write(developer_dir_path, expected_developer_dir)
RUBY

ruby "$AKUO_VALIDATOR" "$AKUO_WORKFLOW" "$AKUO_RUN_SCRIPT" "$AKUO_DEVELOPER_DIR"

akuo_assert_job_override_rejected() {
    local override_key="$1"
    local mutant_workflow="$AKUO_TEST_TMP/$override_key.yml"
    local validator_output
    local validator_status

    ruby - "$AKUO_WORKFLOW" "$mutant_workflow" "$override_key" <<'RUBY'
require "yaml"

source_path, destination_path, override_key = ARGV
workflow = YAML.safe_load(File.read(source_path), aliases: false)
workflow["on"] = workflow.delete(true) if workflow.key?(true)
job = workflow.fetch("jobs").fetch("verify")
job[override_key] = case override_key
                    when "permissions" then "write-all"
                    when "continue-on-error" then true
                    when "if" then "always()"
                    else raise "unsupported test mutation: #{override_key}"
                    end
File.write(destination_path, YAML.dump(workflow))
RUBY

    set +e
    validator_output="$(
        ruby "$AKUO_VALIDATOR" "$mutant_workflow" \
            "$AKUO_TEST_TMP/mutant-run.sh" \
            "$AKUO_TEST_TMP/mutant-developer-dir.txt" 2>&1
    )"
    validator_status=$?
    set -e

    if [[ "$validator_status" -eq 0 ]]; then
        printf 'FAIL: workflow contract accepted job-level %s override\n' \
            "$override_key" >&2
        exit 1
    fi
    if [[ "$validator_output" != *"FAIL: verify job must not override permissions, failure handling, or gating"* ]]; then
        printf 'FAIL: job-level %s override failed for the wrong reason:\n%s\n' \
            "$override_key" "$validator_output" >&2
        exit 1
    fi
}

akuo_assert_job_override_rejected permissions
akuo_assert_job_override_rejected continue-on-error
akuo_assert_job_override_rejected if

AKUO_FIXTURE_ROOT="$AKUO_TEST_TMP/project"
AKUO_INVOCATION_LOG="$AKUO_TEST_TMP/invocations.log"
mkdir -p "$AKUO_FIXTURE_ROOT/Scripts"

cat >"$AKUO_FIXTURE_ROOT/Scripts/verify.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s|%s\n' "$PWD" "${DEVELOPER_DIR:-}" "$*" >>"${AKUO_INVOCATION_LOG:?}"
exit "${AKUO_VERIFIER_STATUS:-0}"
SH
chmod +x "$AKUO_FIXTURE_ROOT/Scripts/verify.sh"

akuo_assert_verifier_status() {
    local verifier_status="$1"
    local expected_status="$2"
    local actual_status
    local expected_invocation
    local actual_invocation

    rm -f "$AKUO_INVOCATION_LOG"
    set +e
    (
        cd "$AKUO_FIXTURE_ROOT"
        DEVELOPER_DIR="$(<"$AKUO_DEVELOPER_DIR")" \
            AKUO_INVOCATION_LOG="$AKUO_INVOCATION_LOG" \
            AKUO_VERIFIER_STATUS="$verifier_status" \
            bash -euo pipefail "$AKUO_RUN_SCRIPT"
    )
    actual_status=$?
    set -e

    if [[ "$actual_status" -ne "$expected_status" ]]; then
        printf 'FAIL: workflow verification step returned %d for verifier status %d, expected %d\n' \
            "$actual_status" "$verifier_status" "$expected_status" >&2
        exit 1
    fi

    expected_invocation="$AKUO_FIXTURE_ROOT|/Applications/Xcode_16.4.app/Contents/Developer|"
    actual_invocation="$(<"$AKUO_INVOCATION_LOG")"
    if [[ "$actual_invocation" != "$expected_invocation" ]]; then
        printf 'FAIL: workflow verification step invoked the wrong command\nexpected: %s\nactual: %s\n' \
            "$expected_invocation" "$actual_invocation" >&2
        exit 1
    fi
}

akuo_assert_verifier_status 0 0
akuo_assert_verifier_status 37 37

printf 'PASS: macOS CI workflow semantics and unified verification invocation\n'
