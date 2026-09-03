# Stable Local Code Signing Design

## Problem

Akuo's packaging script ad-hoc signs every bundle. An ad-hoc signature gives
the app a designated requirement based on that build's code-directory hash.
The hash changes whenever the executable changes, so macOS does not recognize
the replacement as the application that was previously granted Accessibility
permission.

## Approved behavior

- Keep `app.akuo.Akuo` as the bundle identifier and
  `/Applications/Akuo.app` as the installed path.
- Let ordinary and CI builds continue to use ad-hoc signing when no signing
  identity is selected.
- Let developers select a persistent certificate through
  `AKUO_CODE_SIGN_IDENTITY`.
- For certificate builds, derive the Apple team identifier from a preliminary
  signature and re-sign with Akuo's repository-controlled designated
  requirement: Apple generic anchor, exact bundle identifier, and exact team.
- Provide a local installation command that requires a certificate-signed
  bundle, refuses an ad-hoc or any requirement other than that controlled
  policy, and independently verifies Apple anchoring to the reported team.
- Refuse to replace a certificate-signed installed application unless the new
  staged candidate and installed application satisfy each other's designated
  requirements.
- Treat migration from the existing ad-hoc build as a one-time identity change
  that requires one final Accessibility grant.
- Do not weaken Akuo's designated requirement to the bundle identifier alone.

## Interfaces

`Scripts/build-app.sh debug|release` retains its existing command-line
interface. `AKUO_CODE_SIGN_IDENTITY` defaults to `-` for ad-hoc builds and may
be set to an Apple Development or Developer ID Application identity. The
certificate-backed path embeds the controlled requirement through `codesign`.

`Scripts/verify-local-signing.sh APP_PATH` verifies the bundle, identifier,
signature kind, and designated requirement without changing the filesystem.

`Scripts/install-local.sh debug|release` requires a non-ad-hoc
`AKUO_CODE_SIGN_IDENTITY`, builds and verifies the candidate, checks update
compatibility when an already certificate-signed Akuo is installed, and then
replaces `/Applications/Akuo.app` through a staged same-volume move with
rollback. Candidate, staged, and installed executable hashes must match. A
failed rollback preserves the recovery backup and reports its exact path.

## Verification

- An executable contract test constructs a real ad-hoc-signed Akuo fixture and
  proves that the verifier rejects it specifically because its identity changes
  with its code hash.
- Deterministic policy tests accept the controlled Apple/team requirement and
  reject a weak identifier-only requirement. Adversarial contract cases
  exercise mutual compatibility in both directions and preserve a recovery
  backup when its target is occupied.
- Script syntax checks, the contract test, the complete Swift suite, a default
  ad-hoc release build, and strict signature verification must pass.
- A certificate-signed installation remains pending until a code-signing
  identity exists in the developer's keychain.
