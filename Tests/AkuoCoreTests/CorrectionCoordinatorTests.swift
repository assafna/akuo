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
        XCTAssertEqual(selector.selected, [.hebrew, .english])
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
        XCTAssertEqual(selector.selected, [.hebrew, .english])
    }

    func testUndoSelectionFailureKeepsVisibleRestorationWithoutRetry() {
        let replacer = RecordingReplacer()
        let selector = RecordingSelector(results: [true, false])
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
        XCTAssertEqual(selector.selected, [.hebrew, .english])
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
            .init(deleteCount: 5, replacement: "akuo", boundary: " "),
        ])
        XCTAssertEqual(coordinator.handleImmediateUndo(context: context), .notHandled)
        XCTAssertEqual(selector.selected, [.hebrew, .english])
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

    func testUndoReplacementFailurePreservesCommandZAndDoesNotRestoreSource() {
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
    }

    private func makeCoordinator(
        recognizer: StubRecognizer,
        replacer: RecordingReplacer,
        selector: RecordingSelector,
        counter: RecordingCounter,
        clock: FixedClock,
        undoController: any UndoRecording = UndoController()
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
            undoController: undoController
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

private struct ReplacementCall: Equatable {
    let deleteCount: Int
    let replacement: String
    let boundary: String
}

private final class RecordingReplacer: TextReplacing {
    private var results: [Bool]
    private(set) var calls: [ReplacementCall] = []
    private(set) var boundaryKeyCodes: [Int] = []
    var events: RuntimeEvents?

    init(results: [Bool] = []) {
        self.results = results
    }

    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: String,
        boundaryKeyCode: Int
    ) -> Bool {
        events?.values.append(.replace)
        calls.append(.init(deleteCount: deleteCount, replacement: replacement, boundary: boundary))
        boundaryKeyCodes.append(boundaryKeyCode)
        return results.isEmpty ? true : results.removeFirst()
    }
}

private final class RecordingSelector: InputSourceSelecting {
    private var results: [Bool]
    private(set) var selected: [Language] = []
    private let events: RuntimeEvents?

    init(results: [Bool] = [], events: RuntimeEvents? = nil) {
        self.results = results
        self.events = events
    }

    func select(_ language: Language) -> Bool {
        events?.values.append(.select)
        selected.append(language)
        return results.isEmpty ? true : results.removeFirst()
    }
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

private enum RuntimeEvent: Equatable {
    case replace
    case select
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

    func recognizes(_ word: String, as language: Language) -> Bool {
        switch language {
        case .english:
            english.contains(word.lowercased())
        case .hebrew:
            hebrew.contains(word)
        }
    }
}
