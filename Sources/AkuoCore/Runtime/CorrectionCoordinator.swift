import Foundation

public final class CorrectionCoordinator {
    private static let forcedCorrectionEligibilityInterval: TimeInterval = 5

    private struct PendingForcedCorrection {
        let completedWord: CompletedWord
        let boundaryKeyCode: Int
        let correction: Correction
        let context: FocusContext
        let priorInputLanguage: Language
        let createdAt: Date
    }

    private let policy: CorrectionPolicy
    private let textReplacer: any TextReplacing
    private let inputSourceSelector: any InputSourceSelecting
    private let counter: any CorrectionCounting
    private let clock: any RuntimeClock
    private let undoController: any UndoRecording
    private var pendingForcedCorrection: PendingForcedCorrection?

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
        priorInputLanguage: Language,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult {
        pendingForcedCorrection = nil
        undoController.invalidate()
        guard context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput else {
            return .notHandled
        }
        guard let boundaryKeyCode else { return .notHandled }
        let decision = policy.decision(
            for: completedWord.token,
            sourceHint: priorInputLanguage,
            keyStrokes: completedWord.keyStrokes
        )
        guard case let .correct(correction) = decision else {
            if case let .correct(forcedCorrection) = policy.forcedDecision(
                for: completedWord.token,
                sourceHint: priorInputLanguage,
                keyStrokes: completedWord.keyStrokes
            ) {
                guard isContextStillEligible() else { return .notHandled }
                pendingForcedCorrection = .init(
                    completedWord: completedWord,
                    boundaryKeyCode: boundaryKeyCode,
                    correction: forcedCorrection,
                    context: context,
                    priorInputLanguage: priorInputLanguage,
                    createdAt: clock.now
                )
            }
            return .notHandled
        }
        guard isContextStillEligible() else {
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

    public func handleImmediateUndo(
        context: FocusContext,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult {
        pendingForcedCorrection = nil
        guard let record = undoController.eligibleRecord(context: context, now: clock.now) else {
            return .notHandled
        }

        guard isContextStillEligible() else {
            undoController.invalidate()
            return .notHandled
        }
        undoController.invalidate()
        guard textReplacer.replacePreviousText(
            deleteCount: record.corrected.unicodeScalars.count
                + record.boundary.unicodeScalars.count,
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

    public func handleForcedCorrection(
        _ unfinishedWord: CompletedWord? = nil,
        context: FocusContext,
        priorInputLanguage: Language? = nil,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult {
        if let unfinishedWord {
            pendingForcedCorrection = nil
            undoController.invalidate()
            guard let priorInputLanguage,
                  context.elementIdentifier != nil,
                  !context.isSecureField,
                  context.isEditableTextInput,
                  case let .correct(correction) = policy.forcedDecision(
                      for: unfinishedWord.token,
                      sourceHint: priorInputLanguage,
                      keyStrokes: unfinishedWord.keyStrokes
                  ),
                  isContextStillEligible() else {
                return .notHandled
            }
            return applyForcedCorrection(
                unfinishedWord,
                boundaryKeyCode: nil,
                correction: correction,
                context: context,
                priorInputLanguage: priorInputLanguage
            )
        }

        if let toggleResult = handleForcedToggle(
            context: context,
            currentInputLanguage: priorInputLanguage,
            isContextStillEligible: isContextStillEligible
        ) {
            return toggleResult
        }

        guard let pendingForcedCorrection else { return .notHandled }
        self.pendingForcedCorrection = nil
        undoController.invalidate()
        let elapsed = clock.now.timeIntervalSince(pendingForcedCorrection.createdAt)
        guard pendingForcedCorrection.context == context,
              elapsed >= 0,
              elapsed <= Self.forcedCorrectionEligibilityInterval,
              isContextStillEligible() else {
            return .notHandled
        }

        return applyForcedCorrection(
            pendingForcedCorrection.completedWord,
            boundaryKeyCode: pendingForcedCorrection.boundaryKeyCode,
            correction: pendingForcedCorrection.correction,
            context: context,
            priorInputLanguage: pendingForcedCorrection.priorInputLanguage
        )
    }

    private func handleForcedToggle(
        context: FocusContext,
        currentInputLanguage: Language?,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult? {
        guard let record = undoController.eligibleRecord(
            context: context,
            now: clock.now
        ) else {
            return nil
        }

        pendingForcedCorrection = nil
        guard let currentInputLanguage,
              isContextStillEligible() else {
            undoController.invalidate()
            return .notHandled
        }
        undoController.invalidate()
        guard textReplacer.replacePreviousText(
            deleteCount: record.corrected.unicodeScalars.count
                + record.boundary.unicodeScalars.count,
            replacement: record.original,
            boundary: record.boundary,
            boundaryKeyCode: record.boundaryKeyCode
        ) else {
            return .notHandled
        }

        let sourceSelectionSucceeded = inputSourceSelector.select(
            record.priorInputLanguage
        )
        undoController.register(.init(
            original: record.corrected,
            corrected: record.original,
            boundary: record.boundary,
            boundaryKeyCode: record.boundaryKeyCode,
            context: context,
            priorInputLanguage: currentInputLanguage,
            createdAt: clock.now
        ))
        return sourceSelectionSucceeded
            ? .handled
            : .handledWithInputSourceSelectionFailure(
                expectedLanguage: record.priorInputLanguage
            )
    }

    private func applyForcedCorrection(
        _ completedWord: CompletedWord,
        boundaryKeyCode: Int?,
        correction: Correction,
        context: FocusContext,
        priorInputLanguage: Language
    ) -> CorrectionHandlingResult {
        guard textReplacer.replacePreviousText(
            deleteCount: completedWord.token.unicodeScalars.count
                + completedWord.boundary.unicodeScalars.count,
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

    public func noteOrdinaryInput() {
        pendingForcedCorrection = nil
        undoController.invalidate()
    }
}
