import CoreGraphics
import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

final class LiveExclusionPipelineTests: XCTestCase {
    func testEnglishStructuredShapesPassThroughUnchangedWithoutSelectingSource() {
        for input in [
            "https://akuo.app ",
            "akuo.app ",
            "akuo@example.com ",
            "/tmp/akuo ",
            "file_name ",
            "abc123 ",
            "camelCase ",
        ] {
            let fixture = makeFixture(language: .english)

            XCTAssertEqual(fixture.passThrough(input), input, "Unexpected interception for \(input)")
            XCTAssertTrue(fixture.replacer.calls.isEmpty, "Unexpected replacement for \(input)")
            XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty, "Unexpected source selection for \(input)")
            XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
            XCTAssertEqual(fixture.counter.incrementCount, 0)
        }
    }

    func testExactLiveEnglishSequencePassesThroughAndLeavesSourceEnglish() {
        let fixture = makeFixture(language: .english)
        let input = "hello go zzzz abc123 file_name camelCase me@example.com https://akuo.app /tmp/file "

        XCTAssertEqual(fixture.passThrough(input), input)
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
    }

    func testWrongLayoutWordFollowedByPunctuationPassesThroughUnchanged() {
        let fixture = makeFixture(language: .english)
        let input = "akuo. "

        XCTAssertEqual(fixture.passThrough(input), input)
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
    }

    func testWhitespaceClearsExcludedTokenBeforeFreshCorrectableWord() {
        let fixture = makeFixture(language: .english)

        XCTAssertEqual(fixture.passThrough("akuo.app "), "akuo.app ")
        XCTAssertTrue(fixture.process("a") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("k") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("u") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("o") === fixture.nativeEvent)
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(fixture.backend.selectedIdentifiers, ["com.apple.keylayout.Hebrew"])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .hebrew)
        XCTAssertEqual(fixture.counter.incrementCount, 1)
    }

    func testReturnClearsExcludedTokenBeforeFreshCorrectableWord() {
        let fixture = makeFixture(language: .english)

        XCTAssertEqual(fixture.passThrough("akuo.app\n"), "akuo.app\n")
        XCTAssertTrue(fixture.process("a") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("k") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("u") === fixture.nativeEvent)
        XCTAssertTrue(fixture.process("o") === fixture.nativeEvent)
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(fixture.backend.selectedIdentifiers, ["com.apple.keylayout.Hebrew"])
    }

    func testHebrewWrongLayoutSegmentInsideDomainPassesThroughAndLeavesSourceHebrew() {
        let fixture = makeFixture(language: .hebrew)
        let input = "יקךךם.בםצ "

        XCTAssertEqual(fixture.passThrough(input), input)
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .hebrew)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
    }

    func testLeadingHebrewLayoutPunctuationTokensRemainCorrectable() {
        for (leadingText, keyCode, remainder, replacement) in [
            ("/", CGKeyCode(12), "וןבל", "quick"),
            ("'", CGKeyCode(13), "ן", "wi"),
        ] {
            let fixture = makeFixture(language: .hebrew)

            XCTAssertTrue(fixture.process(leadingText, keyCode: keyCode) === fixture.nativeEvent)
            XCTAssertEqual(fixture.passThrough(remainder), remainder)
            XCTAssertNil(fixture.process(" "))

            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: leadingText.count + remainder.count,
                    replacement: replacement,
                    boundary: " "
                ),
            ])
            XCTAssertEqual(fixture.backend.selectedIdentifiers, ["com.apple.keylayout.ABC"])
            XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
            XCTAssertEqual(fixture.counter.incrementCount, 1)
        }
    }

    private func makeFixture(language: Language) -> LiveExclusionFixture {
        let backend = LiveExclusionInputSourceBackend(language: language)
        let inputSources = InputSourceController(backend: backend)
        let replacer = LiveExclusionTextReplacer()
        let counter = LiveExclusionCounter()
        let scorer = WordScorer(recognizer: LiveExclusionRecognizer())
        let coordinator = CorrectionCoordinator(
            policy: CorrectionPolicy(
                layoutMap: KeyboardLayoutMap(),
                originalScorer: scorer,
                candidateScorer: scorer,
                excluder: TokenExcluder()
            ),
            textReplacer: replacer,
            inputSourceSelector: inputSources,
            counter: counter,
            clock: LiveExclusionClock(),
            undoController: UndoController(),
            previousTextValidator: LiveExclusionPreviousTextValidator()
        )
        let decoder = LiveExclusionEventDecoder()
        let nativeEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        let monitor = KeyboardEventMonitor(
            decoder: decoder,
            coordinator: coordinator,
            permission: LiveExclusionPermission(),
            secureInput: LiveExclusionSecureInput(),
            focusContextProvider: LiveExclusionFocusProvider(),
            inputSources: inputSources,
            tapManager: LiveExclusionTapManager(),
            isAkuoEnabled: { true }
        )
        return .init(
            monitor: monitor,
            decoder: decoder,
            nativeEvent: nativeEvent,
            replacer: replacer,
            backend: backend,
            inputSources: inputSources,
            counter: counter
        )
    }
}

private struct LiveExclusionPreviousTextValidator: PreviousTextValidating {
    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        context: FocusContext
    ) -> Bool {
        true
    }
}

private struct LiveExclusionReplacement: Equatable {
    let deleteCount: Int
    let replacement: String
    let boundary: String
}

private final class LiveExclusionTextReplacer: TextReplacing {
    private(set) var calls: [LiveExclusionReplacement] = []

    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: String,
        boundaryKeyCode: Int?
    ) -> Bool {
        calls.append(.init(
            deleteCount: deleteCount,
            replacement: replacement,
            boundary: boundary
        ))
        return true
    }
}

private final class LiveExclusionCounter: CorrectionCounting {
    private(set) var incrementCount = 0

    func incrementCorrectionCount() {
        incrementCount += 1
    }
}

private struct LiveExclusionRecognizer: WordRecognizing {
    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let isRecognized = switch language {
        case .english:
            ["go", "hello", "me", "quick", "wi"].contains(word.lowercased())
        case .hebrew:
            word == "שלום"
        }
        return isRecognized ? .recognized : .unknown
    }
}

private struct LiveExclusionClock: RuntimeClock {
    let now = Date(timeIntervalSinceReferenceDate: 100)
}

private final class LiveExclusionInputSourceBackend: InputSourceBackend {
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

private final class LiveExclusionEventDecoder: NativeEventDecoding {
    var event: DecodedKeyboardEvent = .unhandled(marker: 0)

    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent {
        self.event
    }
}

private struct LiveExclusionFocusProvider: FocusContextProviding {
    func current() -> FocusContext? {
        .init(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )
    }
}

private struct LiveExclusionPermission: AccessibilityPermissionChecking {
    let isGranted = true

    func request() {}
}

private struct LiveExclusionSecureInput: SecureInputChecking {
    let isSecureInputEnabled = false
}

private final class LiveExclusionTapManager: NativeEventTapManaging {
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

private struct LiveExclusionFixture {
    let monitor: KeyboardEventMonitor
    let decoder: LiveExclusionEventDecoder
    let nativeEvent: CGEvent
    let replacer: LiveExclusionTextReplacer
    let backend: LiveExclusionInputSourceBackend
    let inputSources: InputSourceController
    let counter: LiveExclusionCounter

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
            let text = String(character)
            if process(text) === nativeEvent {
                passedThrough.append(character)
            }
        }
        return passedThrough
    }
}
