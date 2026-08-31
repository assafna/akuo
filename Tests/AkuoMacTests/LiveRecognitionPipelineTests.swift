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

    func testInternalApostropheWaitsForBoundaryThenCorrectsContraction() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["don't"], hebrew: [])
        )

        for (text, keyCode) in [
            ("ג", CGKeyCode(2)),
            ("ם", CGKeyCode(31)),
            ("מ", CGKeyCode(45)),
            (",", CGKeyCode(39)),
            ("א", CGKeyCode(17)),
        ] {
            XCTAssertEqual(fixture.passThroughStroke(text, keyCode: keyCode), text)
        }

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "גםמ,א")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.document.text, "don't ")
        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 5, replacement: "don't", boundary: " "),
        ])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 1)
        XCTAssertEqual(fixture.undo.registered.count, 1)
    }

    func testHebrewGereshWOutputCorrectsLowercaseContraction() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["we're"], hebrew: [])
        )

        for (text, keyCode) in [
            ("׳", CGKeyCode(13)),
            ("ק", CGKeyCode(14)),
            (",", CGKeyCode(39)),
            ("ר", CGKeyCode(15)),
            ("ק", CGKeyCode(14)),
        ] {
            XCTAssertEqual(fixture.passThroughStroke(text, keyCode: keyCode), text)
        }

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "׳ק,רק")
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.document.text, "we're ")
        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 5, replacement: "we're", boundary: " "),
        ])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 1)
        XCTAssertEqual(fixture.undo.registered.count, 1)
    }

    func testInternalApostrophePreservesSilentShiftedCapitalization() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["we're"], hebrew: ["ק,רק"])
        )

        for (text, keyCode) in [
            ("", CGKeyCode(13)),
            ("ק", CGKeyCode(14)),
            (",", CGKeyCode(39)),
            ("ר", CGKeyCode(15)),
            ("ק", CGKeyCode(14)),
        ] {
            XCTAssertEqual(fixture.passThroughStroke(text, keyCode: keyCode), text)
        }

        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.document.text, "We're ")
        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 4, replacement: "We're", boundary: " "),
        ])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
        XCTAssertEqual(fixture.counter.incrementCount, 1)
        XCTAssertEqual(fixture.undo.registered.count, 1)
    }

    func testCompletePhysicalTraceCorrectsCapitalizedJoinedEnglishWords() {
        let cases: [([(String, CGKeyCode)], String, String, Int)] = [
            ([
                ("„", 2), ("ם", 31), ("מ", 45), (",", 39), ("א", 17),
            ], "„םמ,א", "Don't", 5),
            ([
                ("שׁ", 0), ("ן", 34), ("מ", 45), (",", 39), ("א", 17),
            ], "שׁןמ,א", "Ain't", 6),
            ([
                ("לֹ", 8), ("ש", 0), ("מ", 45), (",", 39), ("א", 17),
            ], "לֹשמ,א", "Can't", 6),
            ([
                ("לֹ", 40), ("ש", 0), ("א", 17), ("ק", 14), (",", 39), ("ד", 1),
            ], "לֹשאק,ד", "Kate's", 7),
            ([
                ("וֹ", 32), ("מ", 45), ("ב", 8), ("ך", 37), ("ק", 14), (",", 39), ("ד", 1),
            ], "וֹמבךק,ד", "Uncle's", 8),
            ([
                ("", 46), ("ב", 8), ("„", 2), ("ם", 31), ("מ", 45),
                ("ש", 0), ("ך", 37), ("ג", 2), (",", 39), ("ד", 1),
            ], "ב„םמשךג,ד", "McDonald's", 9),
            ([
                ("„", 2), ("", 31), ("", 45), (",", 39), ("", 17),
            ], "„,", "DON'T", 2),
        ]

        for (keyStrokes, visibleToken, candidate, deleteCount) in cases {
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(english: [candidate.lowercased()], hebrew: [])
            )

            for (text, keyCode) in keyStrokes {
                XCTAssertEqual(
                    fixture.passThroughStroke(text, keyCode: keyCode),
                    text,
                    candidate
                )
            }
            XCTAssertEqual(fixture.monitor.currentTokenForTesting, visibleToken, candidate)
            XCTAssertNil(fixture.process(" "), candidate)

            XCTAssertEqual(fixture.document.text, "\(candidate) ", candidate)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: deleteCount,
                    replacement: candidate,
                    boundary: " "
                ),
            ], candidate)
            XCTAssertEqual(fixture.inputSources.currentLanguage, .english, candidate)
            XCTAssertEqual(fixture.counter.incrementCount, 1, candidate)
            XCTAssertEqual(fixture.undo.registered.count, 1, candidate)
        }
    }

    func testCompletePhysicalTraceStillRejectsMalformedApostrophePlacement() {
        let cases: [([(String, CGKeyCode)], String, String)] = [
            ([
                (",", 39), ("„", 2), ("ם", 31), ("מ", 45), (",", 39), ("א", 17),
            ], ",„םמ,א", "'Don't"),
            ([
                ("„", 2), ("ם", 31), ("מ", 45), (",", 39), (",", 39), ("א", 17),
            ], "„םמ,,א", "Don''t"),
            ([
                ("„", 2), ("ם", 31), ("מ", 45), ("א", 17), (",", 39),
            ], "„םמא,", "Dont'"),
        ]

        for (keyStrokes, visibleToken, candidate) in cases {
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(english: [candidate.lowercased()], hebrew: [])
            )

            for (text, keyCode) in keyStrokes {
                XCTAssertEqual(
                    fixture.passThroughStroke(text, keyCode: keyCode),
                    text,
                    candidate
                )
            }
            XCTAssertEqual(fixture.monitor.currentTokenForTesting, visibleToken, candidate)
            XCTAssertTrue(fixture.process(" ") === fixture.nativeEvent, candidate)

            XCTAssertEqual(fixture.document.text, visibleToken, candidate)
            XCTAssertTrue(fixture.replacer.calls.isEmpty, candidate)
            XCTAssertEqual(fixture.inputSources.currentLanguage, .hebrew, candidate)
            XCTAssertEqual(fixture.counter.incrementCount, 0, candidate)
            XCTAssertTrue(fixture.undo.registered.isEmpty, candidate)
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

    func testSilentShiftedHebrewKeyRestoresLeadingEnglishCapital() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["hello"], hebrew: [])
        )

        XCTAssertEqual(fixture.passThroughStroke("", keyCode: 4), "")
        XCTAssertEqual(fixture.passThroughStroke("ק", keyCode: 14), "ק")
        XCTAssertEqual(fixture.passThroughStroke("ך", keyCode: 37), "ך")
        XCTAssertEqual(fixture.passThroughStroke("ך", keyCode: 37), "ך")
        XCTAssertEqual(fixture.passThroughStroke("ם", keyCode: 31), "ם")
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.document.text, "Hello ")
        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 4, replacement: "Hello", boundary: " "),
        ])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
    }

    func testCompositeShiftedHebrewKeyRestoresLeadingEnglishCapital() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["cool"], hebrew: [])
        )

        XCTAssertEqual(fixture.passThroughStroke("לֹ", keyCode: 8), "לֹ")
        XCTAssertEqual(fixture.passThroughStroke("ם", keyCode: 31), "ם")
        XCTAssertEqual(fixture.passThroughStroke("ם", keyCode: 31), "ם")
        XCTAssertEqual(fixture.passThroughStroke("ך", keyCode: 37), "ך")
        XCTAssertNil(fixture.process(" "))

        XCTAssertEqual(fixture.document.text, "Cool ")
        XCTAssertEqual(fixture.replacer.calls, [
            .init(deleteCount: 5, replacement: "Cool", boundary: " "),
        ])
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
    }

    func testEveryShiftedHebrewLetterKeyRestoresItsEnglishCapital() {
        let cases: [(CGKeyCode, String, String, Int)] = [
            (0, "שׁ", "Abc", 4), (11, "", "Bbc", 2),
            (8, "לֹ", "Cbc", 4), (2, "„", "Dbc", 3),
            (14, "", "Ebc", 2), (3, "", "Fbc", 2),
            (5, "", "Gbc", 2), (4, "", "Hbc", 2),
            (34, "", "Ibc", 2), (38, "", "Jbc", 2),
            (40, "לֹ", "Kbc", 4), (37, "", "Lbc", 2),
            (46, "", "Mbc", 2), (45, "", "Nbc", 2),
            (31, "", "Obc", 2), (35, "", "Pbc", 2),
            (12, "", "Qbc", 2), (15, "", "Rbc", 2),
            (1, "", "Sbc", 2), (17, "", "Tbc", 2),
            (32, "וֹ", "Ubc", 4), (9, "", "Vbc", 2),
            (13, "", "Wbc", 2), (7, "", "Xbc", 2),
            (16, "", "Ybc", 2), (6, "", "Zbc", 2),
        ]

        for (keyCode, shiftedOutput, candidate, deleteCount) in cases {
            let visibleToken = "\(shiftedOutput)נב"
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(
                    english: [candidate.lowercased()],
                    hebrew: [visibleToken]
                )
            )

            XCTAssertEqual(
                fixture.passThroughStroke(shiftedOutput, keyCode: keyCode),
                shiftedOutput,
                candidate
            )
            XCTAssertEqual(fixture.passThroughStroke("נ", keyCode: 11), "נ", candidate)
            XCTAssertEqual(fixture.passThroughStroke("ב", keyCode: 8), "ב", candidate)
            XCTAssertNil(fixture.process(" "), candidate)

            XCTAssertEqual(fixture.document.text, "\(candidate) ", candidate)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(deleteCount: deleteCount, replacement: candidate, boundary: " "),
            ], candidate)
        }
    }

    func testSilentShiftedInitialOutranksRecognizedVisibleHebrewSuffix() {
        let cases: [([ObservedKeyStroke], String, String)] = [
            ([
                .init(text: "", keyCode: 16),
                .init(text: "ק", keyCode: 14),
                .init(text: "ד", keyCode: 1),
            ], "קד", "Yes"),
            ([
                .init(text: "", keyCode: 45),
                .init(text: "ם", keyCode: 31),
            ], "ם", "No"),
        ]

        for (keyStrokes, visibleToken, candidate) in cases {
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(
                    english: [candidate.lowercased()],
                    hebrew: [visibleToken]
                )
            )

            for keyStroke in keyStrokes {
                XCTAssertEqual(
                    fixture.passThroughStroke(
                        keyStroke.text,
                        keyCode: CGKeyCode(keyStroke.keyCode)
                    ),
                    keyStroke.text,
                    candidate
                )
            }
            XCTAssertNil(fixture.process(" "), candidate)

            XCTAssertEqual(fixture.document.text, "\(candidate) ", candidate)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: visibleToken.unicodeScalars.count,
                    replacement: candidate,
                    boundary: " "
                ),
            ], candidate)
        }
    }

    func testAllSilentShiftedKeysRestoreUppercaseEnglishWord() {
        let cases: [([CGKeyCode], String)] = [
            ([16, 14, 1], "YES"),
            ([45, 31], "NO"),
        ]

        for (keyCodes, candidate) in cases {
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(english: [candidate.lowercased()], hebrew: [])
            )

            for keyCode in keyCodes {
                XCTAssertEqual(
                    fixture.passThroughStroke("", keyCode: keyCode),
                    "",
                    candidate
                )
            }
            XCTAssertNil(fixture.process(" "), candidate)

            XCTAssertEqual(fixture.document.text, "\(candidate) ", candidate)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(deleteCount: 0, replacement: candidate, boundary: " "),
            ], candidate)
        }
    }

    func testStandaloneEnglishLetterWordsAreRecoveredWithAndWithoutShift() {
        let cases: [(String, CGKeyCode, String)] = [
            ("ש", 0, "a"),
            ("שׁ", 0, "A"),
            ("ן", 34, "i"),
            ("", 34, "I"),
        ]

        for (shiftedOutput, keyCode, candidate) in cases {
            let fixture = makeFixture(
                language: .hebrew,
                fallback: .init(
                    english: [candidate.lowercased()],
                    hebrew: [shiftedOutput]
                )
            )

            XCTAssertEqual(
                fixture.passThroughStroke(shiftedOutput, keyCode: keyCode),
                shiftedOutput,
                candidate
            )
            XCTAssertNil(fixture.process(" "), candidate)

            XCTAssertEqual(fixture.document.text, "\(candidate) ", candidate)
            XCTAssertEqual(fixture.replacer.calls, [
                .init(
                    deleteCount: shiftedOutput.unicodeScalars.count,
                    replacement: candidate,
                    boundary: " "
                ),
            ], candidate)
        }
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
        var scalars = Array(text.unicodeScalars)
        guard scalars.count >= deleteCount else { return }
        scalars.removeLast(deleteCount)
        text = scalars.reduce(into: "") { result, scalar in
            result.unicodeScalars.append(scalar)
        }
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

    func passThroughStroke(_ text: String, keyCode: CGKeyCode) -> String {
        guard process(text, keyCode: keyCode) === nativeEvent else { return "" }
        document.append(text)
        return text
    }
}
