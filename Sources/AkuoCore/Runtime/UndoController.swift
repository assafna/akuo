import Foundation

public struct UndoRecord: Equatable, Sendable {
    public let original: String
    public let corrected: String
    public let boundary: String
    public let boundaryKeyCode: Int
    public let context: FocusContext
    public let priorInputLanguage: Language
    public let createdAt: Date

    public init(
        original: String,
        corrected: String,
        boundary: String,
        boundaryKeyCode: Int,
        context: FocusContext,
        priorInputLanguage: Language,
        createdAt: Date
    ) {
        self.original = original
        self.corrected = corrected
        self.boundary = boundary
        self.boundaryKeyCode = boundaryKeyCode
        self.context = context
        self.priorInputLanguage = priorInputLanguage
        self.createdAt = createdAt
    }
}

public protocol UndoRecording {
    func register(_ record: UndoRecord)
    func eligibleRecord(context: FocusContext, now: Date) -> UndoRecord?
    func invalidate()
}

public final class UndoController: UndoRecording {
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
        guard now.timeIntervalSince(record.createdAt) <= 5 else {
            invalidate()
            return nil
        }
        return record
    }

    public func invalidate() {
        record = nil
    }
}
