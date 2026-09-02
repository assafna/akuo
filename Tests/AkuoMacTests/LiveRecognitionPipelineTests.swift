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

    func testTabPassesThroughWithoutCorrectingBufferedWord() {
        let fixture = makeFixture(language: .english)

        XCTAssertEqual(fixture.passThrough("akuo\t"), "akuo\t")

        XCTAssertEqual(fixture.document.text, "akuo\t")
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertEqual(fixture.counter.incrementCount, 0)
        XCTAssertTrue(fixture.undo.registered.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
        XCTAssertEqual(fixture.inputSources.currentLanguage, .english)
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

    func testHebrewLayoutWordWithTrailingExclamationCorrectsCompleteToken() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["hello"], hebrew: []),
            layoutTranslator: LiveTargetLayoutTranslator()
        )

        for (text, keyCode, flags) in [
            ("י", CGKeyCode(4), CGEventFlags()),
            ("ק", CGKeyCode(14), CGEventFlags()),
            ("ך", CGKeyCode(37), CGEventFlags()),
            ("ך", CGKeyCode(37), CGEventFlags()),
            ("ם", CGKeyCode(31), CGEventFlags()),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
        ] {
            XCTAssertEqual(
                fixture.passThroughStroke(text, keyCode: keyCode, flags: flags),
                text
            )
        }

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "יקךךם!")
        XCTAssertNil(fixture.process(" "))
        XCTAssertEqual(fixture.document.text, "hello! ")
    }

    func testEnglishLayoutWordWithTrailingQuestionCorrectsCompleteToken() {
        let fixture = makeFixture(
            language: .english,
            fallback: .init(english: [], hebrew: ["למה"]),
            layoutTranslator: LiveTargetLayoutTranslator()
        )

        for (text, keyCode, flags) in [
            ("k", CGKeyCode(40), CGEventFlags()),
            ("n", CGKeyCode(45), CGEventFlags()),
            ("v", CGKeyCode(9), CGEventFlags()),
            ("?", CGKeyCode(44), CGEventFlags.maskShift),
        ] {
            XCTAssertEqual(
                fixture.passThroughStroke(text, keyCode: keyCode, flags: flags),
                text
            )
        }

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "knv?")
        XCTAssertNil(fixture.process(" "))
        XCTAssertEqual(fixture.document.text, "למה? ")
    }

    func testPunctuationOnlyPhysicalKeysStayUnchangedWhenTargetLettersAreRecognized() {
        let cases: [(source: String, keyCode: CGKeyCode, target: String)] = [
            (".", 47, "ץ"),
            (",", 43, "ת"),
            (";", 41, "ף"),
        ]

        for testCase in cases {
            for boundary in [" ", "\r"] {
                let fixture = makeFixture(
                    language: .english,
                    fallback: .init(english: [], hebrew: [testCase.target]),
                    layoutTranslator: ScriptedTargetLayoutTranslator(
                        outputs: [testCase.target]
                    )
                )

                XCTAssertEqual(
                    fixture.passThroughStroke(
                        testCase.source,
                        keyCode: testCase.keyCode
                    ),
                    testCase.source
                )
                XCTAssertEqual(fixture.passThrough(boundary), boundary)
                XCTAssertEqual(
                    fixture.document.text,
                    "\(testCase.source)\(boundary)"
                )
                XCTAssertTrue(fixture.replacer.calls.isEmpty)
                XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
                XCTAssertEqual(fixture.counter.incrementCount, 0)
                XCTAssertTrue(fixture.undo.registered.isEmpty)
            }
        }
    }

    func testCompletePhysicalWordOutranksMalformedRecognizedHebrewShape() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["wow"], hebrew: ["׳ם׳"]),
            layoutTranslator: LiveTargetLayoutTranslator()
        )

        for (text, keyCode) in [
            ("׳", CGKeyCode(13)),
            ("ם", CGKeyCode(31)),
            ("׳", CGKeyCode(13)),
        ] {
            XCTAssertEqual(fixture.passThroughStroke(text, keyCode: keyCode), text)
        }

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "׳ם׳")
        XCTAssertNil(fixture.process(" "))
        XCTAssertEqual(fixture.document.text, "wow ")
    }

    func testPhysicalTranslationCoversRemappedTerminalAndMirroredPunctuation() {
        let cases: [(
            language: Language,
            strokes: [(String, CGKeyCode, CGEventFlags)],
            fallback: LiveRecognitionFallback,
            expected: String
        )] = [
            (
                .english,
                [("a", 0, []), ("k", 40, []), ("u", 32, []),
                 ("o", 31, []), ("'", 39, [])],
                .init(english: [], hebrew: ["שלום"]),
                "שלום,"
            ),
            (
                .english,
                [("a", 0, []), ("k", 40, []), ("u", 32, []),
                 ("o", 31, []), ("/", 44, [])],
                .init(english: [], hebrew: ["שלום"]),
                "שלום."
            ),
            (
                .english,
                [(")", 29, .maskShift), ("k", 40, []), ("n", 45, []),
                 ("v", 9, []), ("?", 44, .maskShift),
                 ("(", 25, .maskShift)],
                .init(english: [], hebrew: ["למה"]),
                "(למה?)"
            ),
            (
                .hebrew,
                [("י", 4, []), ("ק", 14, []), ("ך", 37, []),
                 ("ך", 37, []), ("ם", 31, []), ("ת", 43, [])],
                .init(english: ["hello"], hebrew: []),
                "hello,"
            ),
            (
                .hebrew,
                [("י", 4, []), ("ק", 14, []), ("ך", 37, []),
                 ("ך", 37, []), ("ם", 31, []), ("ץ", 47, [])],
                .init(english: ["hello"], hebrew: []),
                "hello."
            ),
            (
                .hebrew,
                [(")", 25, .maskShift), ("׳", 13, []), ("ם", 31, []),
                 ("׳", 13, []), ("?", 44, .maskShift),
                 ("(", 29, .maskShift)],
                .init(english: ["wow"], hebrew: []),
                "(wow?)"
            ),
        ]

        for testCase in cases {
            let fixture = makeFixture(
                language: testCase.language,
                fallback: testCase.fallback,
                layoutTranslator: LiveTargetLayoutTranslator()
            )
            for (text, keyCode, flags) in testCase.strokes {
                XCTAssertEqual(
                    fixture.passThroughStroke(text, keyCode: keyCode, flags: flags),
                    text,
                    testCase.expected
                )
            }

            XCTAssertNil(fixture.process(" "), testCase.expected)
            XCTAssertEqual(
                fixture.document.text,
                "\(testCase.expected) ",
                testCase.expected
            )
        }
    }

    func testUnavailableTargetLayoutTranslationClearsPartialPhysicalTrace() {
        let translator = ScriptedTargetLayoutTranslator(outputs: ["ש", nil])
        let fixture = makeFixture(
            language: .english,
            fallback: .init(english: [], hebrew: ["שלום"]),
            layoutTranslator: translator
        )

        XCTAssertEqual(fixture.passThroughStroke("a", keyCode: 0), "a")
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "a")
        XCTAssertEqual(fixture.passThroughStroke("k", keyCode: 40), "k")
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")

        XCTAssertTrue(fixture.process(" ") === fixture.nativeEvent)
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
    }

    func testPunctuationDominatedPhysicalCandidateStaysUnchanged() {
        let fixture = makeFixture(
            language: .hebrew,
            fallback: .init(english: ["hello"], hebrew: []),
            layoutTranslator: LiveTargetLayoutTranslator()
        )

        for (text, keyCode, flags) in [
            ("י", CGKeyCode(4), CGEventFlags()),
            ("ק", CGKeyCode(14), CGEventFlags()),
            ("ך", CGKeyCode(37), CGEventFlags()),
            ("ך", CGKeyCode(37), CGEventFlags()),
            ("ם", CGKeyCode(31), CGEventFlags()),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
            ("!", CGKeyCode(18), CGEventFlags.maskShift),
        ] {
            XCTAssertEqual(
                fixture.passThroughStroke(text, keyCode: keyCode, flags: flags),
                text
            )
        }

        XCTAssertEqual(fixture.passThrough(" "), " ")
        XCTAssertEqual(fixture.document.text, "יקךךם!!!!!! ")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
    }

    func testTargetTranslationFailureSuppressesCorrectionUntilBoundary() {
        let translator = ScriptedTargetLayoutTranslator(
            outputs: [nil, "ש", "ל", "ו", "ם"]
        )
        let fixture = makeFixture(
            language: .english,
            fallback: .init(english: [], hebrew: ["שלום"]),
            layoutTranslator: translator
        )

        for (text, keyCode) in [
            ("x", CGKeyCode(7)),
            ("a", CGKeyCode(0)),
            ("k", CGKeyCode(40)),
            ("u", CGKeyCode(32)),
            ("o", CGKeyCode(31)),
        ] {
            XCTAssertEqual(fixture.passThroughStroke(text, keyCode: keyCode), text)
        }

        XCTAssertEqual(fixture.passThrough(" "), " ")
        XCTAssertEqual(fixture.document.text, "xakuo ")
        XCTAssertTrue(fixture.replacer.calls.isEmpty)
        XCTAssertTrue(fixture.backend.selectedIdentifiers.isEmpty)
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
                english: ["hello"],
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

    func testRepeatedPhysicalSequenceUsesCurrentLayoutAfterEveryCorrection() {
        let fixture = makePhysicalFixture(
            fallback: .init(
                english: ["hello", "world"],
                hebrew: ["שלום", "עולם"]
            )
        )

        fixture.typePhysical(
            "Hello world akuo guko hello world akuo guko "
        )

        XCTAssertEqual(
            fixture.document.text,
            "Hello world שלום עולם hello world שלום עולם "
        )
        XCTAssertEqual(
            fixture.replacer.calls.map(\.replacement),
            ["שלום", "hello", "שלום"]
        )
        XCTAssertEqual(
            fixture.backend.selectedIdentifiers,
            [
                "com.apple.keylayout.Hebrew",
                "com.apple.keylayout.ABC",
                "com.apple.keylayout.Hebrew",
            ]
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
        fallback: LiveRecognitionFallback = .init(english: [], hebrew: []),
        layoutTranslator: (any KeyboardLayoutTextTranslating)? = nil
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
            layoutTranslator: layoutTranslator,
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

    private func makePhysicalFixture(
        fallback: LiveRecognitionFallback
    ) -> PhysicalLayoutFixture {
        let backend = LiveRecognitionInputSourceBackend(language: .english)
        let inputSources = InputSourceController(backend: backend)
        let document = LiveRecognitionDocument()
        let replacer = LiveRecognitionTextReplacer(document: document)
        let retranslator = PhysicalCurrentLayoutRetranslator(backend: backend)
        let coordinator = CorrectionCoordinator(
            policy: AppModel.makeRecognitionPolicy(fallback: fallback),
            textReplacer: replacer,
            inputSourceSelector: inputSources,
            counter: LiveRecognitionCounter(),
            clock: LiveRecognitionClock(),
            undoController: LiveRecognitionUndoRecorder()
        )
        let monitor = KeyboardEventMonitor(
            decoder: SystemNativeEventDecoder(retranslator: retranslator),
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
            retranslator: retranslator,
            document: document,
            replacer: replacer,
            backend: backend
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

private final class PhysicalCurrentLayoutRetranslator: CurrentKeyboardTextRetranslating {
    private static let englishKeyCode: [Character: CGKeyCode] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
        "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
        "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    ]
    private static let englishCharacter = Dictionary(
        uniqueKeysWithValues: englishKeyCode.map { ($0.value, $0.key) }
    )

    private let backend: LiveRecognitionInputSourceBackend

    init(backend: LiveRecognitionInputSourceBackend) {
        self.backend = backend
    }

    func characters(for event: CGEvent) -> String? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == 49 { return " " }
        guard let english = Self.englishCharacter[keyCode] else { return nil }
        if backend.currentIdentifier == "com.apple.keylayout.Hebrew" {
            return KeyboardLayoutMap.englishToHebrew[english].map(String.init)
        }
        return event.flags.contains(.maskShift)
            ? String(english).uppercased()
            : String(english)
    }

    func event(for physicalCharacter: Character) -> CGEvent? {
        if physicalCharacter == " " {
            return event(keyCode: 49, flags: [], staleCharacters: " ")
        }
        let lowercase = Character(String(physicalCharacter).lowercased())
        guard let keyCode = Self.englishKeyCode[lowercase],
              let staleCharacters = KeyboardLayoutMap.englishToHebrew[lowercase]
                .map(String.init) else {
            return nil
        }
        let flags: CGEventFlags = physicalCharacter.isUppercase ? [.maskShift] : []
        return event(
            keyCode: keyCode,
            flags: flags,
            staleCharacters: staleCharacters
        )
    }

    private func event(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        staleCharacters: String
    ) -> CGEvent? {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        ) else {
            return nil
        }
        event.flags = flags
        let characters = Array(staleCharacters.utf16)
        characters.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }
}

private struct LiveTargetLayoutTranslator: KeyboardLayoutTextTranslating {
    private static let englishCharacter: [Int: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g",
        4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s",
        17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]

    func characters(
        keyCode: Int,
        modifiers: ObservedKeyModifiers,
        inputSourceIdentifier: String
    ) -> String? {
        let shifted = modifiers.contains(.shift)
        if keyCode == 18, shifted { return "!" }
        if keyCode == 44, shifted { return "?" }
        if inputSourceIdentifier == "com.apple.keylayout.Hebrew" {
            switch (keyCode, shifted) {
            case (29, true): return "("
            case (25, true): return ")"
            case (39, false): return ","
            case (44, false): return "."
            default: break
            }
        } else {
            switch (keyCode, shifted) {
            case (25, true): return "("
            case (29, true): return ")"
            case (39, false): return "'"
            case (43, false): return ","
            case (47, false): return "."
            case (44, false): return "/"
            default: break
            }
        }
        guard let english = Self.englishCharacter[keyCode] else { return nil }
        if inputSourceIdentifier == "com.apple.keylayout.Hebrew" {
            return KeyboardLayoutMap.englishToHebrew[english].map(String.init)
        }
        return shifted
            ? String(english).uppercased()
            : String(english)
    }
}

private final class ScriptedTargetLayoutTranslator: KeyboardLayoutTextTranslating {
    private var outputs: [String?]

    init(outputs: [String?]) {
        self.outputs = outputs
    }

    func characters(
        keyCode: Int,
        modifiers: ObservedKeyModifiers,
        inputSourceIdentifier: String
    ) -> String? {
        guard !outputs.isEmpty else { return nil }
        return outputs.removeFirst()
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

    func passThroughStroke(
        _ text: String,
        keyCode: CGKeyCode,
        flags: CGEventFlags = []
    ) -> String {
        nativeEvent.flags = flags
        defer { nativeEvent.flags = [] }
        guard process(text, keyCode: keyCode) === nativeEvent else { return "" }
        document.append(text)
        return text
    }
}

private struct PhysicalLayoutFixture {
    let monitor: KeyboardEventMonitor
    let retranslator: PhysicalCurrentLayoutRetranslator
    let document: LiveRecognitionDocument
    let replacer: LiveRecognitionTextReplacer
    let backend: LiveRecognitionInputSourceBackend

    func typePhysical(_ input: String) {
        for character in input {
            guard let event = retranslator.event(for: character),
                  let visibleText = retranslator.characters(for: event) else {
                XCTFail("No physical-key fixture for \(character)")
                return
            }
            if monitor.process(event) === event {
                document.append(visibleText)
            }
        }
    }
}
