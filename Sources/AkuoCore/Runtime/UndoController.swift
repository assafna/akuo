import Foundation

public struct UndoRecord: Equatable, Sendable {
    public let original: String
    public let corrected: String
    public let boundary: CorrectionBoundary?
    public let context: FocusContext
    public let priorInputLanguage: Language
    public let priorInputSourceIdentifier: String?
    public let createdAt: Date

    public init(
        original: String,
        corrected: String,
        boundary: CorrectionBoundary?,
        context: FocusContext,
        priorInputLanguage: Language,
        priorInputSourceIdentifier: String,
        createdAt: Date
    ) {
        self.init(
            original: original,
            corrected: corrected,
            boundary: boundary,
            context: context,
            priorInputLanguage: priorInputLanguage,
            compatibilityPriorInputSourceIdentifier: priorInputSourceIdentifier,
            createdAt: createdAt
        )
    }

    @available(*, deprecated, message: "Pass priorInputSourceIdentifier for exact undo restoration.")
    public init(
        original: String,
        corrected: String,
        boundary: CorrectionBoundary?,
        context: FocusContext,
        priorInputLanguage: Language,
        createdAt: Date
    ) {
        self.init(
            original: original,
            corrected: corrected,
            boundary: boundary,
            context: context,
            priorInputLanguage: priorInputLanguage,
            compatibilityPriorInputSourceIdentifier: nil,
            createdAt: createdAt
        )
    }

    init(
        original: String,
        corrected: String,
        boundary: CorrectionBoundary?,
        context: FocusContext,
        priorInputLanguage: Language,
        compatibilityPriorInputSourceIdentifier: String?,
        createdAt: Date
    ) {
        self.original = original
        self.corrected = corrected
        self.boundary = boundary
        self.context = context
        self.priorInputLanguage = priorInputLanguage
        self.priorInputSourceIdentifier = compatibilityPriorInputSourceIdentifier
        self.createdAt = createdAt
    }
}

public protocol UndoRecording {
    func register(_ record: UndoRecord)
    func eligibleRecord(context: FocusContext, now: Date) -> UndoRecord?
    func invalidate()
}

public final class UndoController: UndoRecording {
    private static let eligibilityInterval: TimeInterval = 5

    private var record: UndoRecord?

    public init() {}

    public func register(_ record: UndoRecord) {
        self.record = record
    }

    public func eligibleRecord(context: FocusContext, now: Date) -> UndoRecord? {
        guard let record else { return nil }
        guard record.context == context,
              record.context.elementIdentifier != nil,
              context.elementIdentifier != nil,
              !record.context.isSecureField,
              !context.isSecureField,
              record.context.isEditableTextInput,
              context.isEditableTextInput else {
            invalidate()
            return nil
        }
        let elapsed = now.timeIntervalSince(record.createdAt)
        guard elapsed >= 0, elapsed <= Self.eligibilityInterval else {
            invalidate()
            return nil
        }
        return record
    }

    public func invalidate() {
        record = nil
    }
}
