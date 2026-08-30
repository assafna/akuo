import CoreGraphics
import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

final class LiveRecognitionPipelineTests: XCTestCase {
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

    func testProductionRecognitionCompositionStillCorrectsRequiredExamples() {
        for (language, input, passThrough, deleteCount, replacement, targetIdentifier) in [
            (Language.english, "akuo ", "akuo", 4, "שלום", "com.apple.keylayout.Hebrew"),
            (Language.hebrew, "יקךךם ", "יקךךם", 5, "hello", "com.apple.keylayout.ABC"),
        ] {
            let fixture = makeFixture(language: language)

            XCTAssertEqual(fixture.passThrough(input), passThrough)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: deleteCount,
                    replacement: replacement,
                    boundary: " "
                ),
            ])
            XCTAssertEqual(fixture.counter.incrementCount, 1)
            XCTAssertEqual(fixture.undo.registered.count, 1)
            XCTAssertEqual(fixture.backend.selectedIdentifiers, [targetIdentifier])
        }
    }

    func testLayoutLetterPunctuationWaitsForBoundaryThenCorrectsCompleteToken() {
        let boundaries: [(String, CGKeyCode)] = [(" ", 49), ("\r", 36)]

        for (boundary, keyCode) in boundaries {
            let fixture = makeFixture(
                language: .english,
                fallback: .init(english: [], hebrew: ["עברית"])
            )

            XCTAssertEqual(fixture.passThrough("gcrh,"), "gcrh,")
            XCTAssertEqual(fixture.monitor.currentTokenForTesting, "gcrh,")
            XCTAssertTrue(fixture.replacer.calls.isEmpty)
            XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)

            XCTAssertNil(fixture.process(boundary, keyCode: keyCode))

            XCTAssertEqual(fixture.document.text, "עברית\(boundary)")
            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: 5,
                    replacement: "עברית",
                    boundary: boundary
                ),
            ])
            XCTAssertEqual(
                fixture.backend.selectedIdentifiers,
                ["com.apple.keylayout.Hebrew"]
            )
            XCTAssertEqual(fixture.inputSources.currentLanguage, .hebrew)
            XCTAssertEqual(fixture.counter.incrementCount, 1)
            XCTAssertEqual(fixture.undo.registered.count, 1)
        }
    }

    func testRecognizedEnglishWordFollowedByLayoutPunctuationStaysUnchanged() {
        let fixture = makeFixture(
            language: .english,
            fallback: .init(
                english: ["hello,"],
                hebrew: ["יקךךםת"]
            )
        )

        XCTAssertEqual(fixture.passThrough("hello, "), "hello, ")
        XCTAssertEqual(fixture.document.text, "hello, ")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
        XCTAssertTrue(fixture.undo.registered.isEmpty)
    }

    func testFallbackOnlyOriginalVetoesSeedCandidate() {
        let fixture = makeFixture(
            language: .english,
            fallback: LiveRecognitionFallback(english: ["akuo"], hebrew: [])
        )

        XCTAssertEqual(fixture.passThrough("akuo "), "akuo ")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
        XCTAssertTrue(fixture.undo.registered.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
    }

    func testProductionRecognitionCompositionCorrectsLeadingMappedPunctuation() {
        let fixture = makeFixture(language: .hebrew)

        XCTAssertTrue(fixture.process("/", keyCode: 12) === fixture.nativeEvent)
        XCTAssertEqual(fixture.passThrough("וןבל"), "וןבל")
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 5, replacement: "quick", boundary: " "),
        ])
        XCTAssertEqual(fixture.counter.incrementCount, 1)
        XCTAssertEqual(fixture.undo.registered.count, 1)
        XCTAssertEqual(
            fixture.backend.selectedIdentifiers,
            ["com.apple.keylayout.ABC"]
        )
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
    }

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

        _ = fixture.passThrough("ואני לא בטוח למה ")

        XCTAssertEqual(
            fixture.document.text,
            "this is not always עובד ואני לא בטוח למה "
        )
    }

    private func makeFixture(
        language: Language,
        fallback: LiveRecognitionFallback = .init(english: [], hebrew: [])
    ) -> LiveRecognitionFixture {
        let backend = LiveRecognitionInputSourceBackend(language: language)
        let inputSources = InputSourceController(backend: backend)
        let document = LiveRecognitionDocument()
        let replacer = LiveRecognitionTextReplacer(document: document)
        let counter = LiveRecognitionCounter()
        let undo = LiveRecognitionUndoRecorder()
        let coordinator = CorrectionCoordinator(
            policy: AppModel.makeRecognitionPolicy(fallback: fallback),
            textReplacer: replacer,
            inputSourceSelector: inputSources,
            counter: counter,
            clock: LiveRecognitionClock(),
            undoController: undo
        )
        let decoder = LiveRecognitionEventDecoder()
        let nativeEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        let monitor = KeyboardEventMonitor(
            decoder: decoder,
            coordinator: coordinator,
            permission: LiveRecognitionPermission(),
            secureInput: LiveRecognitionSecureInput(),
            focusContextProvider: LiveRecognitionFocusProvider(),
            inputSources: inputSources,
            tapManager: LiveRecognitionTapManager(),
            isAkuoEnabled: { true }
        )
        return .init(
            monitor: monitor,
            decoder: decoder,
            nativeEvent: nativeEvent,
            document: document,
            replacer: replacer,
            backend: backend,
            inputSources: inputSources,
            counter: counter,
            undo: undo
        )
    }
}

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

private struct LiveRecognitionReplacement: Equatable {
    let deleteCount: Int
    let replacement: String
    let boundary: String
}

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

private final class LiveRecognitionCounter: CorrectionCounting {
    private(set) var incrementCount = 0

    func incrementCorrectionCount() {
        incrementCount += 1
    }
}

private final class LiveRecognitionUndoRecorder: UndoRecording {
    private(set) var registered: [UndoRecord] = []

    func register(_ record: UndoRecord) {
        registered.append(record)
    }

    func eligibleRecord(context: FocusContext, now: Date) -> UndoRecord? {
        nil
    }

    func invalidate() {}
}

private struct LiveRecognitionClock: RuntimeClock {
    let now = Date(timeIntervalSinceReferenceDate: 100)
}

private final class LiveRecognitionInputSourceBackend: InputSourceBackend {
    let sources: [InputSourceDescriptor] = [
        .init(identifier: "com.apple.keylayout.ABC"),
        .init(identifier: "com.apple.keylayout.Hebrew"),
    ]
    private(set) var currentIdentifier: String?
    private(set) var selectedIdentifiers: [String] = []

    init(language: Language) {
        currentIdentifier = language == .english
            ? "com.apple.keylayout.ABC"
            : "com.apple.keylayout.Hebrew"
    }

    func select(identifier: String) -> Bool {
        selectedIdentifiers.append(identifier)
        currentIdentifier = identifier
        return true
    }
}

private final class LiveRecognitionEventDecoder: NativeEventDecoding {
    var event: DecodedKeyboardEvent = .unhandled(marker: 0)

    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent {
        self.event
    }
}

private struct LiveRecognitionFocusProvider: FocusContextProviding {
    func current() -> FocusContext? {
        .init(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )
    }
}

private struct LiveRecognitionPermission: AccessibilityPermissionChecking {
    let isGranted = true

    func request() {}
}

private struct LiveRecognitionSecureInput: SecureInputChecking {
    let isSecureInputEnabled = false
}

private final class LiveRecognitionTapManager: NativeEventTapManaging {
    private(set) var isInstalled = false

    func install(
        userInfo: UnsafeMutableRawPointer,
        callback: CGEventTapCallBack
    ) -> Bool {
        isInstalled = true
        return true
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        isInstalled && enabled
    }

    func remove() {
        isInstalled = false
    }
}

private struct LiveRecognitionFixture {
    let monitor: KeyboardEventMonitor
    let decoder: LiveRecognitionEventDecoder
    let nativeEvent: CGEvent
    let document: LiveRecognitionDocument
    let replacer: LiveRecognitionTextReplacer
    let backend: LiveRecognitionInputSourceBackend
    let inputSources: InputSourceController
    let counter: LiveRecognitionCounter
    let undo: LiveRecognitionUndoRecorder

    func process(_ text: String, keyCode: CGKeyCode? = nil) -> CGEvent? {
        let inferredKeyCode: CGKeyCode? = switch text {
        case " ": 49
        case "\t": 48
        case "\n", "\r": 36
        default: nil
        }
        let resolvedKeyCode = keyCode ?? inferredKeyCode
        decoder.event = .text(text, keyCode: resolvedKeyCode, marker: 0)
        return monitor.process(nativeEvent)
    }

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
}
