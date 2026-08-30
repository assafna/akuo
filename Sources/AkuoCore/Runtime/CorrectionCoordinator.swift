public final class CorrectionCoordinator {
    private let policy: CorrectionPolicy
    private let textReplacer: any TextReplacing
    private let inputSourceSelector: any InputSourceSelecting
    private let counter: any CorrectionCounting
    private let clock: any RuntimeClock
    private let undoController: any UndoRecording

    public init(
        policy: CorrectionPolicy,
        textReplacer: any TextReplacing,
        inputSourceSelector: any InputSourceSelecting,
        counter: any CorrectionCounting,
        clock: any RuntimeClock,
        undoController: any UndoRecording
    ) {
        self.policy = policy
        self.textReplacer = textReplacer
        self.inputSourceSelector = inputSourceSelector
        self.counter = counter
        self.clock = clock
        self.undoController = undoController
    }

    public func handleBoundary(
        _ completedWord: CompletedWord,
        boundaryKeyCode: Int? = nil,
        context: FocusContext,
        priorInputLanguage: Language
    ) -> CorrectionHandlingResult {
        undoController.invalidate()
        guard context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput else {
            return .notHandled
        }
        guard let boundaryKeyCode else { return .notHandled }
        guard case let .correct(correction) = policy.decision(
            for: completedWord.token,
            sourceHint: priorInputLanguage,
            keyStrokes: completedWord.keyStrokes
        ) else {
            return .notHandled
        }
        guard textReplacer.replacePreviousText(
            deleteCount: completedWord.token.unicodeScalars.count,
            replacement: correction.replacement,
            boundary: completedWord.boundary,
            boundaryKeyCode: boundaryKeyCode
        ) else {
            return .notHandled
        }

        let sourceSelectionSucceeded = inputSourceSelector.select(correction.target)
        counter.incrementCorrectionCount()
        undoController.register(.init(
            original: correction.original,
            corrected: correction.replacement,
            boundary: completedWord.boundary,
            boundaryKeyCode: boundaryKeyCode,
            context: context,
            priorInputLanguage: priorInputLanguage,
            createdAt: clock.now
        ))
        return sourceSelectionSucceeded
            ? .handled
            : .handledWithInputSourceSelectionFailure(
                expectedLanguage: correction.target
            )
    }

    public func handleImmediateUndo(context: FocusContext) -> CorrectionHandlingResult {
        guard let record = undoController.eligibleRecord(context: context, now: clock.now) else {
            return .notHandled
        }

        undoController.invalidate()
        guard textReplacer.replacePreviousText(
            deleteCount: record.corrected.count + record.boundary.count,
            replacement: record.original,
            boundary: record.boundary,
            boundaryKeyCode: record.boundaryKeyCode
        ) else {
            return .notHandled
        }

        return inputSourceSelector.select(record.priorInputLanguage)
            ? .handled
            : .handledWithInputSourceSelectionFailure(
                expectedLanguage: record.priorInputLanguage
            )
    }

    public func noteOrdinaryInput() {
        undoController.invalidate()
    }
}
