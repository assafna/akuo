# Stable Local Code Signing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Akuo's Accessibility authorization across local application updates by installing only builds with a stable certificate-backed code identity.

**Architecture:** Packaging remains usable in CI with its current ad-hoc default, while an environment-selected certificate enables stable developer builds. A read-only verifier owns the signing policy, and a separate installer enforces it plus update compatibility before changing `/Applications/Akuo.app`.

**Tech Stack:** Bash, macOS `codesign`, `plutil`, Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-09-03-stable-local-code-signing-design.md`

## Global Constraints

- Keep `CFBundleIdentifier = app.akuo.Akuo`.
- Keep `/Applications/Akuo.app` as the only installation target.
- Default builds remain ad-hoc for CI compatibility.
- Local installation refuses ad-hoc identities and any designated requirement
  other than Akuo's controlled Apple-anchor, identifier, and team policy.
- Installed and staged signed apps must have mutually compatible requirements.
- A failed restore must preserve its recovery backup.

---

### Task 1: Executable signing-policy regression

**Files:**
- Create: `Tests/PackagingTests/LocalSigningContractTests.sh`
- Create: `Scripts/verify-local-signing.sh`
- Create: `Scripts/lib/signing-policy.sh`

**Interfaces:**
- Consumes: a macOS `.app` path
- Produces: `Scripts/verify-local-signing.sh APP_PATH`, returning zero only for a stable Akuo identity

- [ ] **Step 1: Write the failing test**

  Create a minimal `app.akuo.Akuo` fixture, sign it with `codesign --sign -`,
  invoke the absent verifier, and require a nonzero result explaining that an
  ad-hoc identity is unstable.

- [ ] **Step 2: Run test to verify it fails**

  Run: `bash Tests/PackagingTests/LocalSigningContractTests.sh`

  Expected: FAIL because `Scripts/verify-local-signing.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

  Implement argument/path validation, strict `codesign` verification, exact
  bundle-ID validation, rejection of `Signature=adhoc`, exact comparison with
  Akuo's controlled requirement, and an independent Apple-anchor/team check.

- [ ] **Step 4: Run test to verify it passes**

  Run: `bash Tests/PackagingTests/LocalSigningContractTests.sh`

  Expected: PASS with the fixture rejected for the intended reason.

### Task 2: Certificate-aware build and installation

**Files:**
- Modify: `Scripts/build-app.sh`
- Create: `Scripts/install-local.sh`
- Create: `Scripts/lib/install-safety.sh`
- Modify: `Tests/PackagingTests/LocalSigningContractTests.sh`

**Interfaces:**
- Consumes: `AKUO_CODE_SIGN_IDENTITY` and `debug|release`
- Produces: an explicitly signed bundle and a guarded `/Applications` installer

- [ ] **Step 1: Write the failing tests**

  Add command-contract cases proving installation refuses a missing identity
  and the explicit `-` ad-hoc identity without building or modifying the target.

- [ ] **Step 2: Run tests to verify they fail**

  Run: `bash Tests/PackagingTests/LocalSigningContractTests.sh`

  Expected: FAIL because `Scripts/install-local.sh` does not exist.

- [ ] **Step 3: Implement the build and installer changes**

  Read `AKUO_CODE_SIGN_IDENTITY` in the build script, derive the Apple team,
  embed and print Akuo's controlled requirement, require a certificate identity
  in the installer, validate mutual compatibility with an existing stable
  install, stage on the `/Applications` volume, and preserve the recovery
  backup if rollback cannot restore it.

- [ ] **Step 4: Run focused checks**

  Run: `bash -n Scripts/*.sh Scripts/lib/*.sh`

  Run: `bash Tests/PackagingTests/LocalSigningContractTests.sh`

  Expected: both commands pass.

### Task 3: Documentation and complete verification

**Files:**
- Modify: `README.md`
- Modify: `docs/manual-acceptance.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the scripts from Tasks 1 and 2
- Produces: setup and migration instructions that distinguish CI, local development, and distribution signing

- [ ] **Step 1: Update documentation**

  Replace the ad-hoc stability claim, document certificate creation and the
  `AKUO_CODE_SIGN_IDENTITY` installer command, explain the one-time permission
  migration, and add signature/requirement evidence to manual acceptance.

- [ ] **Step 2: Run complete verification**

  Run the script syntax and contract checks, `swift test`,
  `Scripts/build-app.sh release`, and strict `codesign` verification of the
  produced ad-hoc CI bundle.

  Expected: 0 failures; the default artifact remains explicitly identified as
  ad-hoc and cannot pass the local-install verifier.

- [ ] **Step 3: Review the diff and working tree**

  Run: `git diff --check && git status --short && git diff --stat`

  Expected: no whitespace errors and only the planned files changed.
