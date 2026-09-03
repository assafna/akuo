import Foundation
import XCTest
@testable import AkuoCore

final class CorrectionCoordinatorTests: XCTestCase {
    private let context = FocusContext(
        processIdentifier: 42,
        elementIdentifier: "field",
        isSecureField: false,
        isEditableTextInput: true
    )
    private let createdAt = Date(timeIntervalSinceReferenceDate: 100)

    func testSuccessfulCorrectionSuppressesBoundaryAndRegistersUndo() {
        let events = RuntimeEvents()
        let replacer = RecordingReplacer()
        replacer.events = events
        let selector = RecordingSelector(events: events)
        let counter = RecordingCounter(events: events)
        let clock = FixedClock(now: createdAt)
        let undoController = RecordingUndoController(events: events)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: clock,
            undoController: undoController
        )

        let handled = coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        )

        XCTAssertEqual(handled, .handled)
        XCTAssertEqual(replacer.calls, [.init(deleteCount: 4, replacement: "שלום", boundary: " ")])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(counter.incrementCount, 1)
        XCTAssertEqual(events.values, [.replace, .select, .count, .registerUndo])

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(
            replacer.calls,
            [
                .init(deleteCount: 4, replacement: "שלום", boundary: " "),
                .init(deleteCount: 5, replacement: "akuo", boundary: " "),
            ]
        )
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testLegacyBoundaryCallStillAppliesCorrectionWithoutExactSourceIdentifier() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(counter.incrementCount, 1)

        XCTAssertEqual(
            coordinator.handleImmediateUndo(
                context: context,
                isContextStillEligible: { true }
            ),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .english)
        )
        XCTAssertTrue(selector.exactIdentifiers.isEmpty)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
    }

    func testReturnBoundaryKeyCodeIsPreservedForCorrectionAndImmediateUndo() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: "\r"),
            boundaryKeyCode: 36,
            context: context,
            priorInputLanguage: .english
        ), .handled)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)

        XCTAssertEqual(replacer.boundaryKeyCodes, [36, 36])
    }

    func testKeepPassesBoundaryThroughWithoutRuntimeOperations() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: [], hebrew: []),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
    }

    func testSafeKeptWordCanBeForcedAfterBoundaryAndImmediatelyUndone() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let validator = RecordingPreviousTextValidator(result: true)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(validator.calls, [
            .init(expectedText: "שמג ", context: context),
        ])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "and", boundary: " "),
        ])
        XCTAssertEqual(selector.selected, [.english])
        XCTAssertEqual(counter.incrementCount, 1)

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "and", boundary: " "),
            .init(deleteCount: 4, replacement: "שמג", boundary: " "),
        ])
        XCTAssertEqual(selector.selected, [.english])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.Hebrew"])
    }

    func testPendingForcedCorrectionRequiresExactOriginalSuffixAtCaret() {
        let replacer = RecordingReplacer()
        let validator = RecordingPreviousTextValidator(result: false)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertEqual(validator.calls, [
            .init(expectedText: "שמג ", context: context),
        ])
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testReturnSubmissionCannotApplyPendingCorrectionInReusedFocusElement() {
        let replacer = RecordingReplacer()
        let validator = RecordingPreviousTextValidator(result: true)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: "\r"),
            boundaryKeyCode: 36,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertTrue(validator.calls.isEmpty)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testPendingForcedCorrectionRejectsChangedInputSourceSnapshot() {
        let changedSources: [(Language, String)] = [
            (.english, "com.apple.keylayout.US"),
            (.hebrew, "com.apple.keylayout.Hebrew"),
        ]

        for (language, identifier) in changedSources {
            let replacer = RecordingReplacer()
            let validator = RecordingPreviousTextValidator(result: true)
            let coordinator = makeCoordinator(
                recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
                replacer: replacer,
                selector: RecordingSelector(),
                counter: RecordingCounter(),
                clock: FixedClock(now: createdAt),
                previousTextValidator: validator
            )
            XCTAssertEqual(coordinator.handleBoundary(
                .init(token: "go", boundary: " "),
                boundaryKeyCode: 49,
                context: context,
                priorInputLanguage: .english,
                priorInputSourceIdentifier: "com.apple.keylayout.ABC",
                isContextStillEligible: { true }
            ), .notHandled)

            XCTAssertEqual(coordinator.handleForcedCorrection(
                context: context,
                priorInputLanguage: language,
                currentInputSourceIdentifier: identifier,
                isContextStillEligible: { true }
            ), .notHandled, identifier)
            XCTAssertTrue(validator.calls.isEmpty, identifier)
            XCTAssertTrue(replacer.calls.isEmpty, identifier)
        }
    }

    func testPendingForcedCorrectionIsNotArmedWithoutExactSourceIdentifier() {
        let replacer = RecordingReplacer()
        let validator = RecordingPreviousTextValidator(result: true)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "go", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertTrue(validator.calls.isEmpty)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testEditedUnfinishedWordCannotUseInvalidatedPhysicalTrace() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: [], hebrew: []),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            .init(
                token: "aku",
                boundary: "",
                physicalTraceIntegrity: .invalidated
            ),
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testUnfinishedForcedCorrectionCanBeImmediatelyUndoneWithoutBoundary() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            .init(token: "go", boundary: ""),
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 2, replacement: "עם", boundary: ""),
        ])
        XCTAssertEqual(replacer.boundaryKeyCodes, [nil])

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 2, replacement: "עם", boundary: ""),
            .init(deleteCount: 2, replacement: "go", boundary: ""),
        ])
        XCTAssertEqual(replacer.boundaryKeyCodes, [nil, nil])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testLegacyForcedCorrectionStillAppliesWithoutExactSourceIdentifier() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            .init(token: "go", boundary: ""),
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 2, replacement: "עם", boundary: ""),
        ])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(counter.incrementCount, 1)
    }

    func testImmediateUndoRestoresExactUSSourceBeforeDeletingText() {
        let events = RuntimeEvents()
        let replacer = RecordingReplacer()
        replacer.events = events
        let selector = RecordingSelector(events: events)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.US",
            isContextStillEligible: { true }
        ), .handled)
        events.values.removeAll()

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.US"])
        XCTAssertEqual(events.values, [.selectExact, .replace])
    }

    func testImmediateUndoExactSourceFailureDoesNotMutateText() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(exactResults: [false])
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.US",
            isContextStillEligible: { true }
        ), .handled)

        XCTAssertEqual(
            coordinator.handleImmediateUndo(context: context),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .english)
        )
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.US"])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    @available(*, deprecated, message: "Exercises the deprecated compatibility initializer.")
    func testImmediateUndoWithLegacyRecordReportsSelectionFailureWithoutMutatingText() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let undoController = UndoController()
        undoController.register(UndoRecord(
            original: "akuo",
            corrected: "שלום",
            boundary: " ",
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            createdAt: createdAt
        ))
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            undoController: undoController
        )

        XCTAssertEqual(
            coordinator.handleImmediateUndo(context: context),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .english)
        )
        XCTAssertTrue(selector.exactIdentifiers.isEmpty)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testForcedToggleWithLegacySelectorReportsUnsupportedExactRestorationBeforeMutation() {
        let replacer = RecordingReplacer()
        let undoController = UndoController()
        undoController.register(UndoRecord(
            original: "akuo",
            corrected: "שלום",
            boundary: " ",
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            createdAt: createdAt
        ))
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: LegacyLanguageOnlySelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            undoController: undoController
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handledWithInputSourceSelectionFailure(expectedLanguage: .english))
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testLegacyForcedToggleStillAppliesWithoutCurrentExactSourceIdentifier() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .handled)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
            .init(deleteCount: 5, replacement: "akuo", boundary: " "),
        ])

        XCTAssertEqual(
            coordinator.handleImmediateUndo(context: context),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .hebrew)
        )
        XCTAssertEqual(replacer.calls.count, 2)
    }

    func testRepeatedForceGesturesToggleBoundarylessConversionWithoutRecounting() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            .init(token: "go", boundary: ""),
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .notHandled)

        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 2, replacement: "עם", boundary: ""),
            .init(deleteCount: 2, replacement: "go", boundary: ""),
            .init(deleteCount: 2, replacement: "עם", boundary: ""),
            .init(deleteCount: 2, replacement: "go", boundary: ""),
        ])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.Hebrew",
            "com.apple.keylayout.ABC",
        ])
        XCTAssertEqual(counter.incrementCount, 1)
    }

    func testRepeatedForceToggleRecordsExactSourceBeforeEachToggle() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleForcedCorrection(
            .init(token: "go", boundary: ""),
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.US",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .english,
            currentInputSourceIdentifier: "com.apple.keylayout.US",
            isContextStillEligible: { true }
        ), .handled)

        XCTAssertEqual(selector.exactIdentifiers, [
            "com.apple.keylayout.US",
            "com.apple.keylayout.Hebrew",
        ])
    }

    func testReverseToggleExactSourceFailureDoesNotMutateText() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(exactResults: [false])
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .handled)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handledWithInputSourceSelectionFailure(expectedLanguage: .english))
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
    }

    func testForceGestureTogglesAnAutomaticCorrection() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handled)

        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
            .init(deleteCount: 5, replacement: "akuo", boundary: " "),
        ])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
        XCTAssertEqual(counter.incrementCount, 1)
    }

    func testForceGestureRejectsAndInvalidatesAnAutomaticCorrectionWhenElapsedIsNegative() {
        let replacer = RecordingReplacer()
        let clock = MutableClock(now: createdAt)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: clock
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)
        clock.now = createdAt.addingTimeInterval(-0.001)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        clock.now = createdAt
        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
    }

    func testForceGestureTogglesAnAutomaticCorrectionAtFiveSecondEligibilityLimit() {
        let replacer = RecordingReplacer()
        let clock = MutableClock(now: createdAt)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: clock
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)
        clock.now = createdAt.addingTimeInterval(5)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
            .init(deleteCount: 5, replacement: "akuo", boundary: " "),
        ])
    }

    func testForceGestureRejectsAnAutomaticCorrectionAfterFiveSecondEligibilityLimit() {
        let replacer = RecordingReplacer()
        let clock = MutableClock(now: createdAt)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: clock
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)
        clock.now = createdAt.addingTimeInterval(5.001)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
    }

    func testImmediateUndoDeletesUnicodeScalarCountForCompositeReplacement() {
        let replacer = RecordingReplacer()
        let undoController = UndoController()
        undoController.register(.init(
            original: "cool",
            corrected: "לֹם",
            boundary: " ",
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            createdAt: createdAt
        ))
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: [], hebrew: []),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt),
            undoController: undoController
        )

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "cool", boundary: " "),
        ])
    }

    func testPendingForcedCorrectionExpiresAfterFiveSeconds() {
        let replacer = RecordingReplacer()
        let clock = MutableClock(now: createdAt)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: clock
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        clock.now = createdAt.addingTimeInterval(5.001)

        XCTAssertEqual(coordinator.handleForcedCorrection(
            context: context,
            priorInputLanguage: .hebrew,
            currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testForcedSourceSelectionFailureKeepsVisibleCorrectionAndUndo() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(results: [false, true])
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "go", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { true }
        ), .notHandled)

        XCTAssertEqual(
            coordinator.handleForcedCorrection(
                context: context,
                priorInputLanguage: .english,
                currentInputSourceIdentifier: "com.apple.keylayout.ABC",
                isContextStillEligible: { true }
            ),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .hebrew)
        )
        XCTAssertEqual(counter.incrementCount, 1)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 3, replacement: "עם", boundary: " "),
            .init(deleteCount: 3, replacement: "go", boundary: " "),
        ])
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testOrdinaryInputInvalidatesPendingForcedCorrection() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)
        coordinator.noteOrdinaryInput()

        XCTAssertEqual(coordinator.handleForcedCorrection(context: context), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testChangedContextInvalidatesPendingForcedCorrectionBeforeFocusReturns() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["and"], hebrew: ["שמג"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "שמג", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .hebrew,
            priorInputSourceIdentifier: "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        ), .notHandled)

        let otherContext = FocusContext(
            processIdentifier: 43,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )
        XCTAssertEqual(
            coordinator.handleForcedCorrection(
                context: otherContext,
                priorInputLanguage: .hebrew,
                currentInputSourceIdentifier: "com.apple.keylayout.Hebrew",
                isContextStillEligible: { true }
            ),
            .notHandled
        )
        XCTAssertEqual(coordinator.handleForcedCorrection(context: context), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testPendingForcedCorrectionRevalidatesContextBeforeArming() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["go"], hebrew: ["עם"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "go", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            priorInputSourceIdentifier: "com.apple.keylayout.ABC",
            isContextStillEligible: { false }
        ), .notHandled)

        XCTAssertEqual(coordinator.handleForcedCorrection(context: context), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
    }

    func testSecureFieldPassesBoundaryThroughWithoutRuntimeOperations() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: .init(processIdentifier: 42, elementIdentifier: "field", isSecureField: true),
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
    }

    func testIneligibleControlPassesBoundaryThroughWithoutRuntimeOperations() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: .init(
                processIdentifier: 42,
                elementIdentifier: "outline",
                isSecureField: false,
                isEditableTextInput: false
            ),
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertTrue(replacer.calls.isEmpty)
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
    }

    func testChangedContextInvalidatesUndoBeforeFocusReturns() {
        let coordinator = correctedCoordinator()
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(coordinator.handleImmediateUndo(context: .init(
            processIdentifier: 43,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )), .notHandled)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    func testSecureBoundaryInvalidatesUndoBeforeFocusReturns() {
        let coordinator = correctedCoordinator()
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: .init(processIdentifier: 42, elementIdentifier: "field", isSecureField: true),
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    func testReplacementFailurePassesBoundaryThroughWithoutSelectionCountOrUndo() {
        let replacer = RecordingReplacer(results: [false])
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertEqual(replacer.calls, [.init(deleteCount: 4, replacement: "שלום", boundary: " ")])
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    func testCorrectionRevalidatesContextImmediatelyBeforeReplacement() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let validator = RecordingPreviousTextValidator(result: true)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { false }
        ), .notHandled)
        XCTAssertTrue(validator.calls.isEmpty)
        XCTAssertTrue(replacer.calls.isEmpty)
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
    }

    func testAutomaticCorrectionRequiresExactVisibleTokenSuffixBeforeReplacement() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector()
        let counter = RecordingCounter()
        let validator = RecordingPreviousTextValidator(result: false)
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt),
            previousTextValidator: validator
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            isContextStillEligible: { true }
        ), .notHandled)
        XCTAssertEqual(validator.calls, [
            .init(expectedText: "akuo", context: context),
        ])
        XCTAssertTrue(replacer.calls.isEmpty)
        XCTAssertTrue(selector.selected.isEmpty)
        XCTAssertEqual(counter.incrementCount, 0)
    }

    func testImmediateUndoRevalidatesContextImmediatelyBeforeReplacement() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(coordinator.handleImmediateUndo(
            context: context,
            isContextStillEligible: { false }
        ), .notHandled)
        XCTAssertEqual(
            replacer.calls,
            [.init(deleteCount: 4, replacement: "שלום", boundary: " ")]
        )
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    func testFailedCorrectionInvalidatesPriorUndoRecord() {
        let replacer = RecordingReplacer(results: [true, false])
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .notHandled)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
    }

    func testSourceSelectionFailureKeepsVisibleCorrectionAndUndoRecord() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(results: [false, true])
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )

        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handledWithInputSourceSelectionFailure(expectedLanguage: .hebrew))
        XCTAssertEqual(counter.incrementCount, 1)
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .handled)
        XCTAssertEqual(
            replacer.calls,
            [
                .init(deleteCount: 4, replacement: "שלום", boundary: " "),
                .init(deleteCount: 5, replacement: "akuo", boundary: " "),
            ]
        )
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testUndoSelectionFailureKeepsVisibleCorrectionWithoutRetry() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(exactResults: [false])
        let counter = RecordingCounter()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: counter,
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(
            coordinator.handleImmediateUndo(context: context),
            .handledWithInputSourceSelectionFailure(expectedLanguage: .english)
        )

        XCTAssertEqual(counter.incrementCount, 1)
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testOrdinaryInputInvalidatesUndoAndPreservesCommandZ() {
        let replacer = RecordingReplacer()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        coordinator.noteOrdinaryInput()

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
        XCTAssertEqual(replacer.calls, [.init(deleteCount: 4, replacement: "שלום", boundary: " ")])
    }

    func testUndoReplacementFailureRestoresSourceBeforePreservingCommandZ() {
        let replacer = RecordingReplacer(results: [true, false])
        let selector = RecordingSelector()
        let coordinator = makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: replacer,
            selector: selector,
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
        XCTAssertEqual(coordinator.handleBoundary(
            .init(token: "akuo", boundary: " "),
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english
        ), .handled)

        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
        XCTAssertEqual(selector.selected, [.hebrew])
        XCTAssertEqual(selector.exactIdentifiers, ["com.apple.keylayout.ABC"])
    }

    private func makeCoordinator(
        recognizer: StubRecognizer,
        replacer: RecordingReplacer,
        selector: any InputSourceSelecting,
        counter: RecordingCounter,
        clock: any RuntimeClock,
        undoController: any UndoRecording = UndoController(),
        previousTextValidator: any PreviousTextValidating = RecordingPreviousTextValidator(
            result: true
        )
    ) -> CorrectionCoordinator {
        let scorer = WordScorer(recognizer: recognizer)
        return CorrectionCoordinator(
            policy: CorrectionPolicy(
                layoutMap: KeyboardLayoutMap(),
                originalScorer: scorer,
                candidateScorer: scorer,
                excluder: TokenExcluder()
            ),
            textReplacer: replacer,
            inputSourceSelector: selector,
            counter: counter,
            clock: clock,
            undoController: undoController,
            previousTextValidator: previousTextValidator
        )
    }

    private func correctedCoordinator() -> CorrectionCoordinator {
        makeCoordinator(
            recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום"]),
            replacer: RecordingReplacer(),
            selector: RecordingSelector(),
            counter: RecordingCounter(),
            clock: FixedClock(now: createdAt)
        )
    }
}

private extension CorrectionCoordinator {
    func handleBoundary(
        _ completedWord: CompletedWord,
        boundaryKeyCode: Int? = nil,
        context: FocusContext,
        priorInputLanguage: Language
    ) -> CorrectionHandlingResult {
        handleBoundary(
            completedWord,
            boundaryKeyCode: boundaryKeyCode,
            context: context,
            priorInputLanguage: priorInputLanguage,
            priorInputSourceIdentifier: priorInputLanguage == .english
                ? "com.apple.keylayout.ABC"
                : "com.apple.keylayout.Hebrew",
            isContextStillEligible: { true }
        )
    }

    func handleImmediateUndo(context: FocusContext) -> CorrectionHandlingResult {
        handleImmediateUndo(
            context: context,
            isContextStillEligible: { true }
        )
    }

    func handleForcedCorrection(context: FocusContext) -> CorrectionHandlingResult {
        handleForcedCorrection(
            context: context,
            isContextStillEligible: { true }
        )
    }
}

private struct ReplacementCall: Equatable {
    let deleteCount: Int
    let replacement: String
    let boundary: String
}

private final class RecordingReplacer: TextReplacing {
    private var results: [Bool]
    private(set) var calls: [ReplacementCall] = []
    private(set) var boundaryKeyCodes: [Int?] = []
    var events: RuntimeEvents?

    init(results: [Bool] = []) {
        self.results = results
    }

    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: String,
        boundaryKeyCode: Int?
    ) -> Bool {
        events?.values.append(.replace)
        calls.append(.init(deleteCount: deleteCount, replacement: replacement, boundary: boundary))
        boundaryKeyCodes.append(boundaryKeyCode)
        return results.isEmpty ? true : results.removeFirst()
    }
}

private struct PreviousTextValidationCall: Equatable {
    let expectedText: String
    let context: FocusContext
}

private final class RecordingPreviousTextValidator: PreviousTextValidating {
    private let result: Bool
    private(set) var calls: [PreviousTextValidationCall] = []

    init(result: Bool) {
        self.result = result
    }

    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        context: FocusContext
    ) -> Bool {
        calls.append(.init(expectedText: expectedText, context: context))
        return result
    }
}

private final class RecordingSelector: InputSourceSelecting {
    private var results: [Bool]
    private var exactResults: [Bool]
    private(set) var selected: [Language] = []
    private(set) var exactIdentifiers: [String] = []
    private let events: RuntimeEvents?

    init(
        results: [Bool] = [],
        exactResults: [Bool] = [],
        events: RuntimeEvents? = nil
    ) {
        self.results = results
        self.exactResults = exactResults
        self.events = events
    }

    func select(_ language: Language) -> Bool {
        events?.values.append(.select)
        selected.append(language)
        return results.isEmpty ? true : results.removeFirst()
    }

    func selectExact(identifier: String) -> Bool {
        events?.values.append(.selectExact)
        exactIdentifiers.append(identifier)
        return exactResults.isEmpty ? true : exactResults.removeFirst()
    }
}

private struct LegacyLanguageOnlySelector: InputSourceSelecting {
    func select(_ language: Language) -> Bool { true }
}

private final class RecordingCounter: CorrectionCounting {
    private(set) var incrementCount = 0
    private let events: RuntimeEvents?

    init(events: RuntimeEvents? = nil) {
        self.events = events
    }

    func incrementCorrectionCount() {
        events?.values.append(.count)
        incrementCount += 1
    }
}

private struct FixedClock: RuntimeClock {
    let now: Date
}

private final class MutableClock: RuntimeClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private enum RuntimeEvent: Equatable {
    case replace
    case select
    case selectExact
    case count
    case registerUndo
}

private final class RuntimeEvents {
    var values: [RuntimeEvent] = []
}

private final class RecordingUndoController: UndoRecording {
    private let controller = UndoController()
    private let events: RuntimeEvents

    init(events: RuntimeEvents) {
        self.events = events
    }

    func register(_ record: UndoRecord) {
        events.values.append(.registerUndo)
        controller.register(record)
    }

    func eligibleRecord(context: FocusContext, now: Date) -> UndoRecord? {
        controller.eligibleRecord(context: context, now: now)
    }

    func invalidate() {
        controller.invalidate()
    }
}

private struct StubRecognizer: WordRecognizing {
    let english: Set<String>
    let hebrew: Set<String>

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let isRecognized = switch language {
        case .english:
            english.contains(word.lowercased())
        case .hebrew:
            hebrew.contains(word)
        }
        return isRecognized ? .recognized : .unknown
    }
}
