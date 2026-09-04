import Foundation

public final class CorrectionCoordinator {
    private static let forcedCorrectionEligibilityInterval: TimeInterval = 5

    private struct PendingForcedCorrection {
        let completedWord: CompletedWord
        let correction: Correction
        let context: FocusContext
        let priorInputLanguage: Language
        let priorInputSourceIdentifier: String
        let createdAt: Date
    }

    private let policy: CorrectionPolicy
    private let textReplacer: any TextReplacing
    private let inputSourceSelector: any InputSourceSelecting
    private let counter: any CorrectionCounting
    private let clock: any RuntimeClock
    private let undoController: any UndoRecording
    private let previousTextValidator: any PreviousTextValidating
    private var pendingForcedCorrection: PendingForcedCorrection?

    public init(
        policy: CorrectionPolicy,
        textReplacer: any TextReplacing,
        inputSourceSelector: any InputSourceSelecting,
        counter: any CorrectionCounting,
        clock: any RuntimeClock,
        undoController: any UndoRecording,
        previousTextValidator: any PreviousTextValidating = RejectingPreviousTextValidator()
    ) {
        self.policy = policy
        self.textReplacer = textReplacer
        self.inputSourceSelector = inputSourceSelector
        self.counter = counter
        self.clock = clock
        self.undoController = undoController
        self.previousTextValidator = previousTextValidator
    }

    public func handleBoundary(
        _ completedWord: CompletedWord,
        context: FocusContext,
        priorInputLanguage: Language,
        priorInputSourceIdentifier: String? = nil,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult {
        pendingForcedCorrection = nil
        undoController.invalidate()
        guard context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput else {
            return .notHandled
        }
        guard let boundary = completedWord.boundary else { return .notHandled }
        let decision = policy.decision(
            for: completedWord.token,
            sourceHint: priorInputLanguage,
            keyStrokes: completedWord.keyStrokes
        )
        guard case let .correct(correction) = decision else {
            if completedWord.physicalTraceIntegrity != .invalidated,
               boundary.keyCode == 49,
               boundary.text == " ",
               let priorInputSourceIdentifier,
               case let .correct(forcedCorrection) = policy.forcedDecision(
                for: completedWord.token,
                sourceHint: priorInputLanguage,
                keyStrokes: completedWord.keyStrokes
            ) {
                guard isContextStillEligible() else { return .notHandled }
                pendingForcedCorrection = .init(
                    completedWord: completedWord,
                    correction: forcedCorrection,
                    context: context,
                    priorInputLanguage: priorInputLanguage,
                    priorInputSourceIdentifier: priorInputSourceIdentifier,
                    createdAt: clock.now
                )
            }
            return .notHandled
        }
        guard isContextStillEligible() else {
            return .notHandled
        }
        guard previousTextValidator.hasExactTextImmediatelyBeforeCaret(
            completedWord.token,
            context: context
        ) else {
            return .notHandled
        }
        guard isContextStillEligible() else {
            return .notHandled
        }
        guard textReplacer.replacePreviousText(
            deleteCount: completedWord.token.unicodeScalars.count,
            replacement: correction.replacement,
            boundary: boundary
        ) else {
            return .notHandled
        }

        let sourceSelectionSucceeded = inputSourceSelector.select(correction.target)
        counter.incrementCorrectionCount()
        undoController.register(UndoRecord(
            original: correction.original,
            corrected: correction.replacement,
            boundary: boundary,
            context: context,
            priorInputLanguage: priorInputLanguage,
            compatibilityPriorInputSourceIdentifier: priorInputSourceIdentifier,
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
        guard previousTextValidator.hasExactTextImmediatelyBeforeCaret(
            record.corrected + (record.boundary?.text ?? ""),
            context: context
        ) else {
            undoController.invalidate()
            return .notHandled
        }
        guard isContextStillEligible() else {
            undoController.invalidate()
            return .notHandled
        }
        undoController.invalidate()
        guard restoreInputSource(for: record) else {
            return .handledWithInputSourceSelectionFailure(
                expectedLanguage: record.priorInputLanguage
            )
        }
        guard textReplacer.replacePreviousText(
            deleteCount: record.corrected.unicodeScalars.count
                + (record.boundary?.text.unicodeScalars.count ?? 0),
            replacement: record.original,
            boundary: record.boundary
        ) else {
            return .notHandled
        }

        return .handled
    }

    public func handleForcedCorrection(
        _ unfinishedWord: CompletedWord? = nil,
        context: FocusContext,
        priorInputLanguage: Language? = nil,
        currentInputSourceIdentifier: String? = nil,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult {
        if let unfinishedWord {
            pendingForcedCorrection = nil
            undoController.invalidate()
            guard let priorInputLanguage,
                  context.elementIdentifier != nil,
                  !context.isSecureField,
                  context.isEditableTextInput,
                  unfinishedWord.physicalTraceIntegrity != .invalidated,
                  case let .correct(correction) = policy.forcedDecision(
                      for: unfinishedWord.token,
                      sourceHint: priorInputLanguage,
                      keyStrokes: unfinishedWord.keyStrokes
                  ),
                  isContextStillEligible() else {
                return .notHandled
            }
            guard previousTextValidator.hasExactTextImmediatelyBeforeCaret(
                unfinishedWord.token + (unfinishedWord.boundary?.text ?? ""),
                context: context
            ), isContextStillEligible() else {
                return .notHandled
            }
            return applyForcedCorrection(
                unfinishedWord,
                correction: correction,
                context: context,
                priorInputLanguage: priorInputLanguage,
                priorInputSourceIdentifier: currentInputSourceIdentifier
            )
        }

        if let toggleResult = handleForcedToggle(
            context: context,
            currentInputLanguage: priorInputLanguage,
            currentInputSourceIdentifier: currentInputSourceIdentifier,
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
              pendingForcedCorrection.priorInputSourceIdentifier
                  == currentInputSourceIdentifier,
              priorInputLanguage == pendingForcedCorrection.priorInputLanguage,
              isContextStillEligible() else {
            return .notHandled
        }
        guard previousTextValidator.hasExactTextImmediatelyBeforeCaret(
            pendingForcedCorrection.completedWord.token
                + (pendingForcedCorrection.completedWord.boundary?.text ?? ""),
            context: context
        ), isContextStillEligible() else {
            return .notHandled
        }

        return applyForcedCorrection(
            pendingForcedCorrection.completedWord,
            correction: pendingForcedCorrection.correction,
            context: context,
            priorInputLanguage: pendingForcedCorrection.priorInputLanguage,
            priorInputSourceIdentifier: pendingForcedCorrection.priorInputSourceIdentifier
        )
    }

    private func handleForcedToggle(
        context: FocusContext,
        currentInputLanguage: Language?,
        currentInputSourceIdentifier: String?,
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
        guard previousTextValidator.hasExactTextImmediatelyBeforeCaret(
            record.corrected + (record.boundary?.text ?? ""),
            context: context
        ), isContextStillEligible() else {
            undoController.invalidate()
            return .notHandled
        }
        undoController.invalidate()
        guard restoreInputSource(for: record) else {
            return .handledWithInputSourceSelectionFailure(
                expectedLanguage: record.priorInputLanguage
            )
        }
        guard textReplacer.replacePreviousText(
            deleteCount: record.corrected.unicodeScalars.count
                + (record.boundary?.text.unicodeScalars.count ?? 0),
            replacement: record.original,
            boundary: record.boundary
        ) else {
            return .notHandled
        }

        undoController.register(UndoRecord(
            original: record.corrected,
            corrected: record.original,
            boundary: record.boundary,
            context: context,
            priorInputLanguage: currentInputLanguage,
            compatibilityPriorInputSourceIdentifier: currentInputSourceIdentifier,
            createdAt: clock.now
        ))
        return .handled
    }

    private func applyForcedCorrection(
        _ completedWord: CompletedWord,
        correction: Correction,
        context: FocusContext,
        priorInputLanguage: Language,
        priorInputSourceIdentifier: String?
    ) -> CorrectionHandlingResult {
        guard textReplacer.replacePreviousText(
            deleteCount: completedWord.token.unicodeScalars.count
                + (completedWord.boundary?.text.unicodeScalars.count ?? 0),
            replacement: correction.replacement,
            boundary: completedWord.boundary
        ) else {
            return .notHandled
        }

        let sourceSelectionSucceeded = inputSourceSelector.select(correction.target)
        counter.incrementCorrectionCount()
        undoController.register(UndoRecord(
            original: correction.original,
            corrected: correction.replacement,
            boundary: completedWord.boundary,
            context: context,
            priorInputLanguage: priorInputLanguage,
            compatibilityPriorInputSourceIdentifier: priorInputSourceIdentifier,
            createdAt: clock.now
        ))
        return sourceSelectionSucceeded
            ? .handled
            : .handledWithInputSourceSelectionFailure(
                expectedLanguage: correction.target
            )
    }

    private func restoreInputSource(for record: UndoRecord) -> Bool {
        guard let identifier = record.priorInputSourceIdentifier else {
            return false
        }
        return inputSourceSelector.selectExact(identifier: identifier)
    }

    public func noteOrdinaryInput() {
        pendingForcedCorrection = nil
        undoController.invalidate()
    }
}
