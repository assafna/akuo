# macOS Dictionary Candidate Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let local macOS dictionaries, including user-learned words, safely authorize English and Hebrew wrong-layout corrections in both directions.

**Architecture:** Replace Boolean-only recognition with a tri-state result so an unavailable spelling service fails open rather than looking recognized. Compose the deterministic seed lexicon with `NSSpellChecker` for both original and candidate scoring, then retain the existing mapping, exclusion, score-margin, source-selection, and undo pipeline.

**Tech Stack:** Swift 6 compiler in Swift 5 language mode, Swift Package Manager, XCTest, AppKit `NSSpellChecker`, existing AkuoCore/AkuoMac protocol boundaries.

**Spec:** `docs/superpowers/specs/2026-08-30-macos-dictionary-candidate-recognition-design.md`

## Global Constraints

- Support macOS 13 Ventura or newer.
- Use only the standard ABC/U.S. English and `com.apple.keylayout.Hebrew` mappings already supported by Akuo.
- Authorize candidates through `SeedLexicon` plus the selected local macOS dictionary in both directions.
- Treat user-learned macOS words as recognized candidates; do not filter them with `hasLearnedWord`.
- Never correct a recognized original.
- Treat unavailable or indeterminate dictionary results as pass-through, never as positive recognition.
- Preserve all secure-input, editable-context, URL, email, path, numeric, mixed-script, identifier, and punctuation exclusions.
- Keep recognition fully local with no network dependency, telemetry, account, raw-word log, or typed-text persistence.
- Preserve input-source alignment and the one-record, five-second immediate Command-Z path.
- Use TDD for every production behavior change and commit after each independently testable task.

---

## File Structure

### Core recognition and policy

- `Sources/AkuoCore/Recognition/WordRecognizing.swift` owns `RecognitionStatus`, the recognition protocol, and seed/fallback composition rules.
- `Sources/AkuoCore/Recognition/SeedLexicon.swift` returns deterministic recognized/unknown status.
- `Sources/AkuoCore/Recognition/WordScorer.swift` carries recognition status into score evidence.
- `Sources/AkuoCore/Policy/CorrectionPolicy.swift` fails open for unavailable original or candidate recognition.

### macOS recognition adapter and composition

- `Sources/AkuoMac/Recognition/SystemSpellChecker.swift` translates `NSSpellChecker` locale, range, language availability, and word-count results into tri-state status.
- `Sources/AkuoMac/Application/AppModel.swift` gives original and candidate scorers the same seed-plus-macOS recognizer.

### Tests and product documentation

- `Tests/AkuoCoreTests/CorrectionPolicyTests.swift` covers tri-state policy and scoring.
- `Tests/AkuoMacTests/SystemServiceContractTests.swift` covers the spelling adapter without depending on the host dictionary.
- `Tests/AkuoMacTests/LiveRecognitionPipelineTests.swift` covers shipping composition, both directions, learned-word behavior, unavailable recognition, and the reported sentence.
- Existing `WordRecognizing` fakes in coordinator, exclusion, and undo tests migrate mechanically to the tri-state protocol without changing their behavior.
- `README.md` and `docs/manual-acceptance.md` describe broad machine-dependent recognition, learned-word tradeoffs, and release checks.

---

### Task 1: Introduce tri-state recognition and fail-open core policy

**Files:**
- Modify: `Sources/AkuoCore/Recognition/WordRecognizing.swift:1-29`
- Modify: `Sources/AkuoCore/Recognition/SeedLexicon.swift:15-24`
- Modify: `Sources/AkuoCore/Recognition/WordScorer.swift:1-33`
- Modify: `Sources/AkuoCore/Policy/CorrectionPolicy.swift:13-65`
- Modify: `Sources/AkuoMac/Recognition/SystemSpellChecker.swift:22-45`
- Modify: `Tests/AkuoCoreTests/CorrectionPolicyTests.swift:1-143`
- Modify: `Tests/AkuoCoreTests/CorrectionCoordinatorTests.swift:473-485`
- Modify: `Tests/AkuoMacTests/LiveExclusionPipelineTests.swift:198-210`
- Modify: `Tests/AkuoMacTests/LiveRecognitionPipelineTests.swift:123-135`
- Modify: `Tests/AkuoMacTests/LiveUndoIntegrationTests.swift:116-128`
- Modify: `Tests/AkuoMacTests/SystemServiceContractTests.swift:175-183,229-235`

**Interfaces:**
- Consumes: `Language`, the existing English/Hebrew normalization rules, and `KeyboardLayoutMap.hebrewLetters`.
- Produces: `public enum RecognitionStatus: Equatable, Sendable { case recognized, unknown, unavailable }`.
- Produces: `WordRecognizing.recognitionStatus(for:as:) -> RecognitionStatus`.
- Produces: `RecognitionEvidence.status: RecognitionStatus`.
- Produces: `KeepReason.recognitionUnavailable`.

- [ ] **Step 1: Add failing policy tests for unavailable recognition**

Add status-aware cases to `CorrectionPolicyTests` before changing production types:

```swift
func testKeepsWhenOriginalRecognitionIsUnavailable() {
    let policy = makePolicy(recognizer: StubRecognizer(
        english: [],
        hebrew: ["שלום"],
        unavailableEnglish: ["akuo"]
    ))

    XCTAssertEqual(policy.decision(for: "akuo"), .keep(.recognitionUnavailable))
}

func testKeepsWhenCandidateRecognitionIsUnavailable() {
    let policy = makePolicy(recognizer: StubRecognizer(
        english: [],
        hebrew: [],
        unavailableHebrew: ["שלום"]
    ))

    XCTAssertEqual(policy.decision(for: "akuo"), .keep(.recognitionUnavailable))
}

func testUnavailableRecognitionCarriesNoRecognitionWeight() {
    let scorer = WordScorer(recognizer: StubRecognizer(
        english: [],
        hebrew: [],
        unavailableEnglish: ["unknown"]
    ))

    XCTAssertEqual(
        scorer.evidence(for: "unknown", language: .english),
        .init(
            language: .english,
            scriptMatches: true,
            status: .unavailable,
            score: 20
        )
    )
}
```

Replace the test recognizer with an exact status-aware fake:

```swift
private struct StubRecognizer: WordRecognizing {
    let english: Set<String>
    let hebrew: Set<String>
    let unavailableEnglish: Set<String>
    let unavailableHebrew: Set<String>

    init(
        english: Set<String>,
        hebrew: Set<String>,
        unavailableEnglish: Set<String> = [],
        unavailableHebrew: Set<String> = []
    ) {
        self.english = english
        self.hebrew = hebrew
        self.unavailableEnglish = unavailableEnglish
        self.unavailableHebrew = unavailableHebrew
    }

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        switch language {
        case .english:
            if unavailableEnglish.contains(word.lowercased()) { return .unavailable }
            return english.contains(word.lowercased()) ? .recognized : .unknown
        case .hebrew:
            if unavailableHebrew.contains(word) { return .unavailable }
            return hebrew.contains(word) ? .recognized : .unknown
        }
    }
}
```

- [ ] **Step 2: Run the focused test and verify the red state**

Run:

```bash
swift test --filter CorrectionPolicyTests
```

Expected: compilation fails because `RecognitionStatus`, `recognitionUnavailable`, and the status-based `RecognitionEvidence` initializer do not exist.

- [ ] **Step 3: Implement the tri-state recognition contract**

Replace the Boolean protocol and composite implementation in `WordRecognizing.swift` with:

```swift
public enum RecognitionStatus: Equatable, Sendable {
    case recognized
    case unknown
    case unavailable
}

public protocol WordRecognizing {
    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus
}

public struct CompositeWordRecognizer: WordRecognizing {
    private let primary: any WordRecognizing
    private let fallback: any WordRecognizing

    public init(
        primary: some WordRecognizing,
        fallback: some WordRecognizing
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let normalizedWord = language == .english ? word.lowercased() : word

        switch primary.recognitionStatus(for: normalizedWord, as: language) {
        case .recognized:
            return .recognized
        case .unknown:
            return fallback.recognitionStatus(for: normalizedWord, as: language)
        case .unavailable:
            return .unavailable
        }
    }
}
```

Change `SeedLexicon` to return `.recognized` or `.unknown`:

```swift
public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
    let isRecognized = switch language {
    case .english:
        Self.english.contains(word.lowercased())
    case .hebrew:
        Self.hebrew.contains(word)
    }
    return isRecognized ? .recognized : .unknown
}
```

Change `RecognitionEvidence` and `WordScorer` to carry status and award the 80-point recognition weight only to `.recognized`:

```swift
public struct RecognitionEvidence: Equatable, Sendable {
    public let language: Language
    public let scriptMatches: Bool
    public let status: RecognitionStatus
    public let score: Int

    public init(
        language: Language,
        scriptMatches: Bool,
        status: RecognitionStatus,
        score: Int
    ) {
        self.language = language
        self.scriptMatches = scriptMatches
        self.status = status
        self.score = score
    }
}

public func evidence(for word: String, language: Language) -> RecognitionEvidence {
    let scriptMatches = Self.matchesScript(word, language: language)
    let status = recognizer.recognitionStatus(for: word, as: language)
    let score = (scriptMatches ? 20 : 0) + (status == .recognized ? 80 : 0)

    return RecognitionEvidence(
        language: language,
        scriptMatches: scriptMatches,
        status: status,
        score: score
    )
}
```

Add `recognitionUnavailable` to `KeepReason` and replace the recognition guards in `CorrectionPolicy.decision(for:)` with explicit state switches:

```swift
switch original.status {
case .recognized:
    return .keep(.originalRecognized)
case .unavailable:
    return .keep(.recognitionUnavailable)
case .unknown:
    break
}

let candidate = candidateScorer.evidence(
    for: conversion.candidate,
    language: conversion.target
)
switch candidate.status {
case .recognized:
    break
case .unknown:
    return .keep(.candidateUnknown)
case .unavailable:
    return .keep(.recognitionUnavailable)
}
guard candidate.score - original.score >= 60 else { return .keep(.ambiguous) }
```

- [ ] **Step 4: Migrate every remaining recognizer conformance**

Rename `recognizes(_:as:) -> Bool` to `recognitionStatus(for:as:) -> RecognitionStatus` in these exact types:

- `SystemSpellChecker`
- `CorrectionCoordinatorTests.StubRecognizer`
- `LiveExclusionRecognizer`
- `LiveRecognitionFallback`
- `LiveUndoRecognizer`
- `SystemServiceContractTests.LiteralRecognizer`

For set-backed test fakes, return `.recognized` on membership and `.unknown` otherwise:

```swift
func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
    let isRecognized = switch language {
    case .english:
        english.contains(word.lowercased())
    case .hebrew:
        hebrew.contains(word)
    }
    return isRecognized ? .recognized : .unknown
}
```

For `LiteralRecognizer`, keep its language-qualified lookup:

```swift
func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
    recognized.contains("\(language.rawValue):\(word)") ? .recognized : .unknown
}
```

For the temporary Task 1 `SystemSpellChecker` implementation, preserve current range behavior and return only recognized/unknown. Task 2 adds unavailable service detection:

```swift
public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
    guard !word.isEmpty else { return .unknown }
    let languageCode = language == .english ? "en_US" : "he_IL"
    return backend.misspelledRange(in: word, language: languageCode).location == NSNotFound
        ? .recognized
        : .unknown
}
```

Update all `RecognitionEvidence` expectations to use `status: .recognized` or `status: .unknown` instead of `recognized: true/false`.

- [ ] **Step 5: Add composite propagation tests**

Update `testCompositeRecognizerUsesNormalizedPrimaryThenFallback` to assert statuses and add an unavailable-primary assertion:

```swift
XCTAssertEqual(
    recognizer.recognitionStatus(for: "HELLO", as: .english),
    .recognized
)
XCTAssertEqual(
    recognizer.recognitionStatus(for: "שלום", as: .hebrew),
    .recognized
)
XCTAssertEqual(
    recognizer.recognitionStatus(for: "unknown", as: .english),
    .unknown
)
```

Use a status-map fake to prove `.unavailable` is propagated rather than falling through:

```swift
let unavailable = StatusRecognizer(statuses: ["english:hello": .unavailable])
let acceptingFallback = StatusRecognizer(statuses: ["english:hello": .recognized])
let composite = CompositeWordRecognizer(primary: unavailable, fallback: acceptingFallback)

XCTAssertEqual(
    composite.recognitionStatus(for: "HELLO", as: .english),
    .unavailable
)
```

Define the fake in the same test file:

```swift
private struct StatusRecognizer: WordRecognizing {
    let statuses: [String: RecognitionStatus]

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        statuses["\(language.rawValue):\(word)"] ?? .unknown
    }
}
```

- [ ] **Step 6: Run focused and full tests**

Run:

```bash
swift test --filter CorrectionPolicyTests
swift test --filter SystemServiceContractTests/testCompositeRecognizerUsesNormalizedPrimaryThenFallback
swift test
```

Expected: all commands exit 0 with no failures. Then confirm no obsolete Boolean conformances remain:

```bash
rg -n 'func recognizes\(' Sources Tests
```

Expected: no matches.

- [ ] **Step 7: Commit the core contract**

```bash
git add Sources/AkuoCore/Recognition/WordRecognizing.swift \
  Sources/AkuoCore/Recognition/SeedLexicon.swift \
  Sources/AkuoCore/Recognition/WordScorer.swift \
  Sources/AkuoCore/Policy/CorrectionPolicy.swift \
  Sources/AkuoMac/Recognition/SystemSpellChecker.swift \
  Tests/AkuoCoreTests/CorrectionPolicyTests.swift \
  Tests/AkuoCoreTests/CorrectionCoordinatorTests.swift \
  Tests/AkuoMacTests/LiveExclusionPipelineTests.swift \
  Tests/AkuoMacTests/LiveRecognitionPipelineTests.swift \
  Tests/AkuoMacTests/LiveUndoIntegrationTests.swift \
  Tests/AkuoMacTests/SystemServiceContractTests.swift
git commit -m "refactor: add tri-state word recognition"
```

---

### Task 2: Make the macOS spelling adapter report unavailability

**Files:**
- Modify: `Sources/AkuoMac/Recognition/SystemSpellChecker.swift:1-50`
- Modify: `Tests/AkuoMacTests/SystemServiceContractTests.swift:7-32,186-198`

**Interfaces:**
- Consumes: `RecognitionStatus` and `WordRecognizing.recognitionStatus(for:as:)` from Task 1.
- Produces: internal `SpellingCheckResult { misspelledRange: NSRange; wordCount: Int }`.
- Produces: `SpellCheckerBackend.availableLanguages: Set<String>` and `checkSpelling(in:language:) -> SpellingCheckResult`.
- Produces: `.unavailable` for missing language resources or negative word-count results.

- [ ] **Step 1: Add failing spelling-service availability tests**

Add these cases to `SystemServiceContractTests`:

```swift
func testSpellCheckerReportsUnavailableWhenRequestedLanguageIsMissing() {
    let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
        availableLanguages: ["en_US"],
        recognized: []
    ))

    XCTAssertEqual(
        checker.recognitionStatus(for: "שלום", as: .hebrew),
        .unavailable
    )
}

func testSpellCheckerReportsUnavailableWhenBackendCheckFails() {
    let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
        availableLanguages: ["en_US", "he_IL"],
        recognized: [],
        failed: ["he_IL:שלום"]
    ))

    XCTAssertEqual(
        checker.recognitionStatus(for: "שלום", as: .hebrew),
        .unavailable
    )
}

func testSpellCheckerReportsUnknownForCompletedMisspelling() {
    let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
        availableLanguages: ["en_US", "he_IL"],
        recognized: []
    ))

    XCTAssertEqual(
        checker.recognitionStatus(for: "notaword", as: .english),
        .unknown
    )
}
```

- [ ] **Step 2: Run the adapter tests and verify the red state**

Run:

```bash
swift test --filter SystemServiceContractTests
```

Expected: compilation fails because `SpellCheckerBackend` has no language-availability or word-count result contract.

- [ ] **Step 3: Implement the backend result contract**

Replace the range-only backend with:

```swift
struct SpellingCheckResult: Equatable {
    let misspelledRange: NSRange
    let wordCount: Int
}

protocol SpellCheckerBackend {
    var availableLanguages: Set<String> { get }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult
}

private struct AppKitSpellCheckerBackend: SpellCheckerBackend {
    var availableLanguages: Set<String> {
        Set(NSSpellChecker.shared.availableLanguages)
    }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult {
        var wordCount = 0
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        return .init(misspelledRange: range, wordCount: wordCount)
    }
}
```

Change `SystemSpellChecker` to fail open on unavailable language resources or a negative word count:

```swift
public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
    guard !word.isEmpty else { return .unknown }

    let languageCode = language == .english ? "en_US" : "he_IL"
    guard backend.availableLanguages.contains(languageCode) else {
        return .unavailable
    }

    let result = backend.checkSpelling(in: word, language: languageCode)
    guard result.wordCount >= 0 else { return .unavailable }
    return result.misspelledRange.location == NSNotFound ? .recognized : .unknown
}
```

Do not call `hasLearnedWord`: learned entries must remain indistinguishable from built-in recognized entries by product decision.

- [ ] **Step 4: Replace the adapter fake with controlled availability and failures**

Use this exact fake in `SystemServiceContractTests`:

```swift
private struct LocaleSpellCheckerBackend: SpellCheckerBackend {
    let availableLanguages: Set<String>
    let recognized: Set<String>
    let failed: Set<String>

    init(
        availableLanguages: Set<String> = ["en_US", "he_IL"],
        recognized: [(String, String)],
        failed: Set<String> = []
    ) {
        self.availableLanguages = availableLanguages
        self.recognized = Set(recognized.map { "\($0.1):\($0.0)" })
        self.failed = failed
    }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult {
        let key = "\(language):\(word)"
        if failed.contains(key) {
            return .init(
                misspelledRange: NSRange(location: NSNotFound, length: 0),
                wordCount: -1
            )
        }
        let range = recognized.contains(key)
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (word as NSString).length)
        return .init(misspelledRange: range, wordCount: 1)
    }
}
```

Keep the locale tests and update their assertions to `.recognized` and `.unknown`. Keep the empty-word tests and assert `.unknown`; an empty word must return before backend availability is consulted.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
swift test --filter SystemServiceContractTests
swift test
```

Expected: both commands exit 0 with no failures, including missing-language and negative-word-count pass-through coverage.

- [ ] **Step 6: Commit the reliable macOS adapter**

```bash
git add Sources/AkuoMac/Recognition/SystemSpellChecker.swift Tests/AkuoMacTests/SystemServiceContractTests.swift
git commit -m "fix: fail open when spelling is unavailable"
```

---

### Task 3: Authorize macOS-recognized candidates in both directions

**Files:**
- Modify: `Sources/AkuoMac/Application/AppModel.swift:266-280`
- Modify: `Tests/AkuoCoreTests/CorrectionPolicyTests.swift:43-57`
- Modify: `Tests/AkuoMacTests/LiveRecognitionPipelineTests.swift:1-289`

**Interfaces:**
- Consumes: tri-state `CompositeWordRecognizer`, `SystemSpellChecker`, and fail-open `CorrectionPolicy` from Tasks 1-2.
- Produces: `AppModel.makeRecognitionPolicy(fallback:)` with one seed-plus-fallback recognizer used by both scorers.
- Produces: shipping integration coverage for non-seed, learned, unavailable, and mixed-sentence behavior.

- [ ] **Step 1: Add failing bidirectional shipping-policy tests**

Add this table-driven test to `LiveRecognitionPipelineTests`:

```swift
func testProductionRecognitionCompositionCorrectsSystemCandidatesInBothDirections() {
    let cases: [(Language, String, LiveRecognitionFallback, String, Language)] = [
        (.english, "gucs ", .init(english: [], hebrew: ["עובד"]), "עובד", .hebrew),
        (.english, "utbh ", .init(english: [], hebrew: ["ואני"]), "ואני", .hebrew),
        (.hebrew, "בםצפואקר ", .init(english: ["computer"], hebrew: []), "computer", .english),
    ]

    for (language, input, fallback, replacement, target) in cases {
        let fixture = makeFixture(language: language, fallback: fallback)

        _ = fixture.passThrough(input)

        XCTAssertEqual(fixture.replacer.calls.map(\.replacement), [replacement], input)
        XCTAssertEqual(fixture.inputSources.currentLanguage, target, input)
        XCTAssertEqual(fixture.counter.incrementCount, 1, input)
        XCTAssertEqual(fixture.undo.registered.count, 1, input)
    }
}
```

The literal Hebrew-layout token `בםצפואקר` maps to `computer`; do not derive this expected value with `KeyboardLayoutMap` inside the test.

- [ ] **Step 2: Reverse the obsolete learned-candidate safety assertion**

Replace `testExactLiveHebrewGibberishSequencePassesThroughWithoutSideEffects` with the selected learned-word behavior:

```swift
func testLearnedSystemCandidateCanAuthorizeCorrection() {
    let fixture = makeFixture(
        language: .hebrew,
        fallback: LiveRecognitionFallback(english: ["zzzz"], hebrew: [])
    )

    XCTAssertEqual(fixture.passThrough("שלום עם זזזז "), "שלום עם זזזז")
    XCTAssertEqual(fixture.replacer.calls.map(\.replacement), ["zzzz"])
    XCTAssertEqual(fixture.counter.incrementCount, 1)
    XCTAssertEqual(fixture.undo.registered.count, 1)
    XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
}
```

The fake represents either a built-in or learned macOS recognition result; production intentionally treats both the same. Remove `testLocalFallbackCannotAuthorizeCandidateOutsideSeedLexicon` from `CorrectionPolicyTests` because it asserts the superseded seed-only product decision.

- [ ] **Step 3: Add a failing unavailable-candidate integration test**

Extend `LiveRecognitionFallback` with unavailable sets and add:

```swift
func testUnavailableCandidateRecognitionPassesThroughWithoutSideEffects() {
    let fixture = makeFixture(
        language: .english,
        fallback: LiveRecognitionFallback(
            english: [],
            hebrew: [],
            unavailableHebrew: ["עובד"]
        )
    )

    XCTAssertEqual(fixture.passThrough("gucs "), "gucs ")
    XCTAssertTrue(fixture.replacer.calls.isEmpty)
    XCTAssertEqual(fixture.counter.incrementCount, 0)
    XCTAssertTrue(fixture.undo.registered.isEmpty)
    XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
    XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
}
```

Use the same four-set shape as the Task 1 `StubRecognizer` so unavailable status is explicit and defaults remain source-compatible:

```swift
private struct LiveRecognitionFallback: WordRecognizing {
    let english: Set<String>
    let hebrew: Set<String>
    let unavailableEnglish: Set<String>
    let unavailableHebrew: Set<String>

    init(
        english: Set<String>,
        hebrew: Set<String>,
        unavailableEnglish: Set<String> = [],
        unavailableHebrew: Set<String> = []
    ) {
        self.english = english
        self.hebrew = hebrew
        self.unavailableEnglish = unavailableEnglish
        self.unavailableHebrew = unavailableHebrew
    }

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        switch language {
        case .english:
            if unavailableEnglish.contains(word.lowercased()) { return .unavailable }
            return english.contains(word.lowercased()) ? .recognized : .unknown
        case .hebrew:
            if unavailableHebrew.contains(word) { return .unavailable }
            return hebrew.contains(word) ? .recognized : .unknown
        }
    }
}
```

- [ ] **Step 4: Add a failing full-sentence document test**

Add a small in-memory document to the live fixture so the test observes visible text rather than only mock calls:

```swift
private final class LiveRecognitionDocument {
    private(set) var text = ""

    func append(_ value: String) {
        text.append(contentsOf: value)
    }

    func applyReplacement(deleteCount: Int, replacement: String, boundary: String) {
        guard text.count >= deleteCount else { return }
        text.removeLast(deleteCount)
        text.append(contentsOf: replacement)
        text.append(contentsOf: boundary)
    }
}
```

Give `LiveRecognitionTextReplacer` the document and call `applyReplacement` after recording each replacement. Give `LiveRecognitionFixture` the same document and append each event that passes through in `passThrough(_:)`. Keep replacement success independent of the document helper so existing focused event tests that call `process(_:)` directly retain their current behavior.

Use this wiring in the replacer:

```swift
private final class LiveRecognitionTextReplacer: TextReplacing {
    private let document: LiveRecognitionDocument
    private(set) var calls: [LiveRecognitionReplacement] = []

    init(document: LiveRecognitionDocument) {
        self.document = document
    }

    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: String,
        boundaryKeyCode: Int
    ) -> Bool {
        calls.append(.init(
            deleteCount: deleteCount,
            replacement: replacement,
            boundary: boundary
        ))
        document.applyReplacement(
            deleteCount: deleteCount,
            replacement: replacement,
            boundary: boundary
        )
        return true
    }
}
```

Create and share the document in `makeFixture`:

```swift
let document = LiveRecognitionDocument()
let replacer = LiveRecognitionTextReplacer(document: document)
```

Add `document: LiveRecognitionDocument` to `LiveRecognitionFixture`, pass it in
the fixture initializer, and update `passThrough(_:)` to model every event the
host editor receives:

```swift
func passThrough(_ input: String) -> String {
    var passedThrough = ""
    for character in input {
        let value = String(character)
        if process(value) === nativeEvent {
            passedThrough.append(contentsOf: value)
            document.append(value)
        }
    }
    return passedThrough
}
```

Then add:

```swift
func testReportedSentenceProducesExpectedTextAcrossSourceSwitch() {
    let fixture = makeFixture(
        language: .english,
        fallback: LiveRecognitionFallback(
            english: ["not", "always"],
            hebrew: ["עובד", "ואני", "בטוח", "למה"]
        )
    )

    _ = fixture.passThrough("this is not always gucs ")
    XCTAssertEqual(fixture.inputSources.currentLanguage, .hebrew)

    // After the correction, macOS decodes the remaining physical keys through
    // the Hebrew source, so the event stream contains Hebrew text.
    _ = fixture.passThrough("ואני לא בטוח למה ")

    XCTAssertEqual(
        fixture.document.text,
        "this is not always עובד ואני לא בטוח למה "
    )
}
```

- [ ] **Step 5: Run the new tests and verify the red state**

Run:

```bash
swift test --filter LiveRecognitionPipelineTests
```

Expected: the new non-seed and learned-candidate cases fail because the shipping candidate scorer still uses `SeedLexicon`; the unavailable and document tests may compile but must not be used as evidence that symmetric authorization already works.

- [ ] **Step 6: Compose one recognizer for both scoring roles**

Replace `AppModel.makeRecognitionPolicy(fallback:)` with:

```swift
nonisolated static func makeRecognitionPolicy(
    fallback: some WordRecognizing
) -> CorrectionPolicy {
    let recognizer = CompositeWordRecognizer(
        primary: SeedLexicon(),
        fallback: fallback
    )
    let scorer = WordScorer(recognizer: recognizer)
    return CorrectionPolicy(
        layoutMap: KeyboardLayoutMap(),
        originalScorer: scorer,
        candidateScorer: scorer,
        excluder: TokenExcluder()
    )
}
```

Do not inspect or filter learned words. Do not change mapping, exclusion, replacement, source-selection, counter, or undo components.

- [ ] **Step 7: Run focused and full tests**

Run:

```bash
swift test --filter LiveRecognitionPipelineTests
swift test --filter CorrectionPolicyTests
swift test
```

Expected: all commands exit 0 with no failures. The reported sentence ends with exactly one boundary Space, learned `zzzz` authorizes the selected correction, unavailable recognition produces no side effects, and all pre-existing safety suites remain green.

- [ ] **Step 8: Commit symmetric dictionary authorization**

```bash
git add Sources/AkuoMac/Application/AppModel.swift Tests/AkuoCoreTests/CorrectionPolicyTests.swift Tests/AkuoMacTests/LiveRecognitionPipelineTests.swift
git commit -m "feat: authorize macOS dictionary candidates"
```

---

### Task 4: Document machine-dependent and learned-word behavior

**Files:**
- Modify: `README.md:3-9,57-75`
- Modify: `docs/manual-acceptance.md:5-24,67-88`

**Interfaces:**
- Consumes: the approved product behavior and automated evidence from Tasks 1-3.
- Produces: user-facing recognition, privacy, learned-word tradeoff, and exact manual acceptance instructions.

- [ ] **Step 1: Record the machine-dependent dictionary environment**

Add this row to the Release identity and evidence table in
`docs/manual-acceptance.md`:

```markdown
| macOS spelling languages (`en_US`, `he_IL`) | |
```

Immediately below the evidence-table instructions, add this local inspection
command and require the tester to record whether both exact language codes are
present:

```bash
xcrun swift -e 'import AppKit; print(NSSpellChecker.shared.availableLanguages.sorted())'
```

If either `en_US` or `he_IL` is absent, the corresponding non-seed recognition
checks are `BLOCKED`; seed recognition remains testable, but the release cannot
claim general dictionary coverage for the missing language.

- [ ] **Step 2: Replace the seed-only README contract**

Update the opening behavior description to state all of the following explicitly:

```markdown
At a whitespace or Return boundary, Akuo maps the same physical keys through
the other layout and corrects only when the original is unknown and the mapped
candidate is recognized by Akuo's seed vocabulary or the selected local macOS
spelling dictionary. macOS user-learned words participate in both directions.
Recognition remains local, but exact coverage can vary by macOS version,
installed language resources, and learned vocabulary.
```

Replace the seed-vocabulary limitation paragraph with the accepted tradeoff:

```markdown
Akuo remains conservative about token shape, editing context, and unavailable
recognition, but trusting learned words increases correction coverage and false-
positive risk. A learned mapped candidate can authorize an unwanted correction;
use immediate Command-Z to restore the original word and input source.
```

Keep the existing privacy statements: no network path, typed-text storage, correction history, or telemetry.

- [ ] **Step 3: Replace the obsolete host-dictionary rejection item**

Remove **Host-dictionary candidate cannot authorize correction** from manual acceptance. Add these checks under Core English/Hebrew correction:

```markdown
- [ ] **Non-seed Hebrew dictionary correction.** Select English, type `gucs `,
  and confirm the visible result is exactly `עובד ` with one Space and the
  active input source changes to standard Hebrew. Record the macOS version and
  confirm `עובד` is recognized by that Mac's Hebrew spelling dictionary.
- [ ] **Non-seed English dictionary correction.** Select standard Hebrew, type
  the physical keys that produce `בםצפואקר `, and confirm the visible result is
  exactly `computer ` with one Space and the active input source changes to
  English.
- [ ] **Reported mixed sentence.** Start with English and continuously press the
  physical keys for `this is not always gucs utbh kt cyuj knv `, including the
  final Space. Confirm the visible result is exactly
  `this is not always עובד ואני לא בטוח למה ` and the active source is Hebrew.
```

- [ ] **Step 4: Add learned-word acceptance with safe cleanup**

Add a subsection that uses disposable values and records their precondition:

```markdown
### Learned-word candidate authority

Use TextEdit's spelling menu to learn and later unlearn only the disposable
values below. Before learning, confirm macOS marks each value unknown. If either
value is already built in or previously learned, choose a new harmless value
whose physical-key mapping contains only letters and record both forms.

- [ ] **Learned Hebrew candidate.** Learn `אבזח`, select English, type `tczj `,
  and confirm Akuo changes it to `אבזח ` and selects Hebrew.
- [ ] **Learned English candidate.** Learn `blorf`, select Hebrew, type the
  physical keys that produce `נךםרכ `, and confirm Akuo changes it to `blorf `
  and selects English.
- [ ] **Learned original veto.** Type each learned value using its correct input
  source and confirm Akuo leaves it unchanged.
- [ ] **Learned-word cleanup.** Unlearn both disposable values, repeat their
  wrong-layout forms, and confirm neither correction occurs unless macOS now
  recognizes the value independently of the learned entry.
```

Retain PASS/FAIL/BLOCKED evidence fields for every added checkbox.

- [ ] **Step 5: Verify documentation consistency**

Run:

```bash
rg -n 'seed vocabulary|bundled vocabulary|Host-dictionary candidate cannot authorize|zzzz' README.md docs/manual-acceptance.md
```

Expected: no stale seed-only authority claim or obsolete host-dictionary rejection remains. A `zzzz` occurrence is allowed only when it describes the accepted learned-word false-positive tradeoff rather than the old required pass-through behavior.

Review the exact physical mappings independently:

```bash
swift test --filter KeyboardLayoutMapTests
```

Expected: exit 0 with no failures.

- [ ] **Step 6: Commit product documentation**

```bash
git add README.md docs/manual-acceptance.md
git commit -m "docs: explain macOS dictionary recognition"
```

---

### Task 5: Run release verification and prepare live acceptance

**Files:**
- Verify only: all files changed in Tasks 1-4
- Build output: `dist/Akuo.app`

**Interfaces:**
- Consumes: completed implementation and documentation commits.
- Produces: fresh automated-test output, a verified local release bundle, executable digest, and an explicit live-acceptance handoff.

- [ ] **Step 1: Run final source and test verification**

Run from the repository root:

```bash
git diff --check
swift test
```

Expected: `git diff --check` emits no output; `swift test` exits 0 with no failures.

- [ ] **Step 2: Build and verify the release bundle**

Run:

```bash
Scripts/build-app.sh release
```

Expected: exit 0, `dist/Akuo.app` exists, property-list validation passes, ad-hoc signing verification passes, and the script prints the SHA-256 digest of the final executable.

Record the exact digest without modifying the acceptance checklist's evidence fields in source control.

- [ ] **Step 3: Review the final committed change set**

Run:

```bash
git status --short --branch
git log --oneline --decorate -6
```

Expected: the worktree is clean and the recent history contains separate commits for tri-state recognition, spelling-service failure handling, symmetric candidate authorization, and documentation.

- [ ] **Step 4: Hand off the installed-app acceptance boundary**

Do not replace `/Applications/Akuo.app`, modify learned words, or claim live acceptance without explicit user authorization. Report:

- the exact implementation commit;
- the passing test command and failure count;
- the release executable SHA-256;
- the local bundle path;
- the exact manual subset in `docs/manual-acceptance.md` covering non-seed words, the reported sentence, learned Hebrew, learned English, learned-original veto, cleanup, immediate undo, unknown pass-through, secure field, and Secure Input.

If the user authorizes installation and live testing, preserve the current installed executable hash, install only the verified bundle, and mark the release accepted only after every required manual item has recorded PASS evidence. Otherwise report implementation and build verification as complete while stating that installed-app acceptance remains pending.

---

## Plan Completion Checklist

- [ ] Every production behavior change has a test that was observed failing before implementation.
- [ ] `RecognitionStatus` reaches the policy without Boolean collapse.
- [ ] Missing language resources and negative word counts fail open.
- [ ] Built-in and learned macOS results authorize candidates in both directions.
- [ ] The reported sentence and its trailing boundary are verified exactly.
- [ ] Existing exclusions, source selection, correction count, and immediate undo remain covered.
- [ ] README and manual acceptance describe the selected learned-word tradeoff without stale seed-only claims.
- [ ] Full tests and release build have fresh successful evidence.
- [ ] Installed-app acceptance is either evidenced or explicitly reported pending.
