# Window-Stack Focus Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve Akuo's text interaction context for non-activating panels by corroborating the activation owner with public WindowServer ordering and stable Accessibility focus evidence.

**Architecture:** Add a focused WindowServer ordering provider that returns distinct application PIDs ahead of an activation owner using only required, non-content metadata. Extend `FocusContextProvider` to select exactly one ahead process exposing a focused AX element, then make `KeyboardEventMonitor` use and revalidate that resolver for correction, forced correction, and undo.

**Tech Stack:** Swift 6, AppKit, ApplicationServices Accessibility, CoreGraphics Quartz Window Services, XCTest, existing shell provenance and signing contracts.

**Spec:** `docs/superpowers/specs/2026-09-06-window-stack-focus-ownership-design.md`

## Global Constraints

- Never inspect bundle identifiers, application names, window names, window contents, or AX values for ownership discovery.
- Use only WindowServer PID, order, level, and alpha; require no Screen Recording permission.
- Accept positive `Int32` PIDs, finite positive alpha, and public levels from normal through modal-panel level.
- Preserve exact element, secure/editable, suffix, and input-source revalidation before mutation.
- Missing, malformed, ambiguous, or changed evidence fails open and clears transient state.
- Advance the candidate identity to `0.4.0 (27)` and install it locally before merge.

---

### Task 1: WindowServer Process Ordering

**Files:**
- Create: `Sources/AkuoMac/System/WindowProcessOrderingProvider.swift`
- Test: `Tests/AkuoMacTests/SystemServiceContractTests.swift`

**Interfaces:**
- Consumes: `CGWindowListCopyWindowInfo`, `kCGWindowOwnerPID`, `kCGWindowLayer`, and `kCGWindowAlpha`.
- Produces: `WindowProcessSnapshot`, `WindowProcessOrdering`, and `WindowProcessOrderingProviding.processIdentifiersInFront(of:)`.

- [ ] **Step 1: Write failing ordering tests**

Add literal snapshots for ordering, deduplication, Akuo exclusion, and termination at the activation owner's first accepted window:

```swift
func testWindowOrderingReturnsDistinctProcessesAheadOfActivationOwner() {
    let windows = [
        WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 1),
        WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 1),
        WindowProcessSnapshot(processIdentifier: 71, layer: 5, alpha: 1),
        WindowProcessSnapshot(processIdentifier: 42, layer: 0, alpha: 1),
        WindowProcessSnapshot(processIdentifier: 99, layer: 0, alpha: 1),
    ]
    XCTAssertEqual(
        WindowProcessOrdering.processIdentifiersInFront(
            of: 42,
            excluding: 265,
            windows: windows,
            acceptedLevels: 0 ... 8
        ),
        [70, 71]
    )
}
```

Add separate cases for invalid PID conversion, non-finite/zero alpha, out-of-range levels, excluded PID, and a missing owner returning `nil`.

- [ ] **Step 2: Run RED**

Run `swift test --filter 'SystemServiceContractTests.testWindowOrdering'`.
Expected: compilation fails because the ordering types do not exist.

- [ ] **Step 3: Implement the pure ordering unit and system adapter**

Create these exact interfaces:

```swift
struct WindowProcessSnapshot: Equatable {
    let processIdentifier: Int32
    let layer: Int
    let alpha: Double
}

protocol WindowProcessOrderingProviding {
    func processIdentifiersInFront(of activationOwner: Int32) -> [Int32]?
}
```

`WindowProcessOrdering.processIdentifiersInFront` iterates front-to-back, skips invalid alpha/level/self entries, deduplicates PIDs, returns accumulated PIDs when it reaches the owner, and returns `nil` if no owner window is found. `SystemWindowProcessOrderingProvider` injects a window-list closure, parses only PID/layer/alpha, rejects numeric overflow, and uses levels from `CGWindowLevelForKey(.normalWindow)` through `.modalPanelWindow`.

- [ ] **Step 4: Run GREEN**

Run `swift test --filter 'SystemServiceContractTests.testWindowOrdering'`.
Expected: all ordering cases pass with zero failures.

---

### Task 2: AX-Corroborated Interaction Resolver

**Files:**
- Modify: `Sources/AkuoMac/System/FocusContextProvider.swift:377-475`
- Test: `Tests/AkuoMacTests/SystemServiceContractTests.swift`

**Interfaces:**
- Consumes: `WindowProcessOrderingProviding` and existing `current(processIdentifier:)` stable AX inspection.
- Produces: `currentInteractionContext()` and `currentInteractionContext(activationOwnerProcessIdentifier:)`.

- [ ] **Step 1: Write failing resolver tests**

Use injected ordering and per-PID AX fakes to prove a unique focused process ahead wins:

```swift
XCTAssertEqual(
    provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
    FocusContext(
        processIdentifier: 70,
        elementIdentifier: "panel-search",
        isSecureField: false,
        isEditableTextInput: true
    )
)
```

Add independent cases proving no ahead focus falls back to PID 42; two ahead focused elements return `nil`; secure/read-only ahead controls block fallback; ordering failure returns `nil`; and the no-argument resolver rejects a frontmost-PID change.

- [ ] **Step 2: Run RED**

Run `swift test --filter 'SystemServiceContractTests.testInteractionContext'`.
Expected: compilation fails because the resolver and ordering injection do not exist.

- [ ] **Step 3: Implement the resolver**

Store an injected `any WindowProcessOrderingProviding`. The explicit resolver obtains ordered PIDs, queries `current(processIdentifier:)`, ignores candidates with no focused-element identifier, returns `nil` after a second focused candidate, otherwise returns the sole ahead context or the activation-owner context. Secure and non-editable focused contexts count as candidates and are returned, never skipped.

The no-argument overload snapshots the frontmost PID, calls the explicit resolver, and requires the frontmost PID to remain unchanged afterward. Ordering failure (`nil`) remains distinct from successful no-candidate evidence (`[]`).

- [ ] **Step 4: Run GREEN**

Run `swift test --filter SystemServiceContractTests`.
Expected: all service contracts pass with zero failures.

---

### Task 3: Event Monitor Ownership and Revalidation

**Files:**
- Modify: `Sources/AkuoMac/Events/KeyboardEventMonitor.swift:212-235,398-405,555-560,813-845`
- Test: `Tests/AkuoMacTests/KeyboardEventMonitorTests.swift`

**Interfaces:**
- Consumes: the two interaction-context operations.
- Produces: automatic correction, forced correction, and undo resolve and revalidate the same interaction context for the captured activation owner.

- [ ] **Step 1: Write the live-failure regression**

Extend the focus fake with interaction-context maps and call recording:

```swift
func testFocusedPanelAheadOfActivationRoutedEventTargetOwnsCorrection() {
    let fixture = makeFixture()
    let panel = FocusContext(
        processIdentifier: 70,
        elementIdentifier: "panel-search",
        isSecureField: false,
        isEditableTextInput: true
    )
    fixture.focus.interactionContextsByActivationOwner[42] = panel
    fixture.decoder.event = .text("akuo", marker: 0)
    XCTAssertNotNil(fixture.monitor.process(targetedNativeEvent(processIdentifier: 42)))
    fixture.decoder.event = .text(" ", keyCode: 49, marker: 0)
    XCTAssertNotNil(fixture.monitor.process(targetedNativeEvent(processIdentifier: 42)))
    XCTAssertEqual(fixture.coordinator.boundaryCalls.first?.context, panel)
    XCTAssertEqual(fixture.focus.interactionOwnerRequests, [42, 42, 42])
}
```

Add cases for panel disappearance during boundary revalidation, ambiguous resolution, immediate undo, forced correction, and a newly ordered panel whose focused element is initially unavailable feeding the existing bounded recovery path without retaining the activation owner's token.

- [ ] **Step 2: Run RED**

Run `swift test --filter 'KeyboardEventMonitorTests.test(FocusedPanel|AmbiguousInteraction|PanelDisappears|ImmediateUndoUsesInteraction|ForcedCorrectionUsesInteraction)'`.
Expected: PID 42 is observed instead of PID 70, or compilation fails on the wished-for protocol API.

- [ ] **Step 3: Route monitor ownership through the resolver**

Extend `FocusContextProviding` with:

```swift
func currentInteractionContext() -> FocusContext?
func currentInteractionContext(
    activationOwnerProcessIdentifier: Int32
) -> FocusContext?
```

Conservative defaults delegate to `current()` and `current(processIdentifier:)`. `.eventTarget(pid)` calls the explicit resolver; `.frontmostApplication` calls the no-argument resolver. Every coordinator closure keeps the captured `FocusOwner` and repeats the same resolution before mutation.

- [ ] **Step 4: Run GREEN and regression suite**

Run `swift test --filter KeyboardEventMonitorTests`, then `swift test`.
Expected: all monitor tests and the complete Swift suite pass with zero failures.

---

### Task 4: Build 27 and Documentation

**Files:**
- Modify: `Sources/AkuoCore/AkuoCoreVersion.swift`
- Modify: `Tests/AkuoCoreTests/AkuoCoreVersionTests.swift`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `docs/manual-acceptance.md`

**Interfaces:**
- Consumes: completed WindowServer-plus-AX behavior.
- Produces: authoritative build `27` and accurate safety/acceptance contracts.

- [ ] **Step 1: Make build 27 RED**

Change the version test to expect `AkuoCoreVersion.build == "27"` and rename it `testCurrentCandidateIdentityIsPointFourBuildTwentySeven`. Run `swift test --filter AkuoCoreVersionTests`; expected failure is actual `26` versus expected `27`.

- [ ] **Step 2: Advance production identity and docs**

Set the production build to `"27"`. Document that event target/frontmost identify the activation owner, visible windows ahead are corroborated with stable AX focus, and ambiguity/drift fail open. Keep the cold/warm Raycast acceptance procedure as testing, not production specialization.

- [ ] **Step 3: Verify and commit**

Run:

```bash
swift test
git diff --check
git status --short
git diff --stat
```

Expected: all tests pass and only planned files changed. Commit all planned source, tests, version, and docs as `fix: resolve nonactivating panel focus`.

---

### Task 5: Review, Provenance, and Local Installation

**Files:**
- Verify only: committed implementation and `dist/Akuo.app`

**Interfaces:**
- Consumes: clean reviewed build-27 commit.
- Produces: review evidence, complete verifier evidence, and exact stable-signed local installation awaiting user acceptance.

- [ ] **Step 1: Independent review**

Give the reviewer the spec, base `c6d8d60`, and implementation head. Require checks for ambiguity, secure/ineligible overlays, malformed WindowServer metadata, ordering drift, event-tap cost, and test mutations. Resolve Critical and Important findings and rerun affected tests.

- [ ] **Step 2: Full immutable-source verification**

Run `Scripts/verify.sh` from the clean commit. Require exit 0 for unified CI order, candidate version, manifest, signing, all Swift tests, and release build.

- [ ] **Step 3: Stable build and artifact verification**

Run:

```bash
AKUO_CODE_SIGN_IDENTITY='Apple Development: nahum.assaf@gmail.com (95WWB7JCRX)' Scripts/build-app.sh release
Scripts/verify-candidate-version.sh dist/Akuo.app
Scripts/verify-build-manifest.sh dist/Akuo.app dist/Akuo.build-manifest.json
Scripts/verify-local-signing.sh dist/Akuo.app
```

Record the executable SHA-256, exact source revision, `0.4.0 (27)`, and team `JCL87HHD7Q`.

- [ ] **Step 4: Exact local installation**

Resolve and gracefully terminate only `/Applications/Akuo.app/Contents/MacOS/Akuo`. Read `executableSHA256` from `dist/Akuo.build-manifest.json` into `AKUO_CANDIDATE_SHA`, then run `Scripts/install-local.sh --candidate /Users/anahum/.codex/worktrees/3ad4/Akuo-GitHub/dist/Akuo.app --sha256 "$AKUO_CANDIDATE_SHA"`. Independently verify installed plist identity, source revision, executable hash, candidate byte equality, and strict designated requirement. Relaunch when policy permits; otherwise ask the user to launch manually.

- [ ] **Step 5: Hold merge for acceptance**

Require five cold and five warm Raycast `akuo ` attempts plus adjacent-prefix rejection. Do not merge unless every attempt corrects exactly once with no partial, duplicate, or out-of-field mutation.
