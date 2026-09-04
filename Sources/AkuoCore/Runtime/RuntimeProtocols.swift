import Foundation

public struct FocusContext: Equatable, Sendable {
    public let processIdentifier: Int32
    public let elementIdentifier: String?
    public let isSecureField: Bool
    public let isEditableTextInput: Bool

    public init(
        processIdentifier: Int32,
        elementIdentifier: String?,
        isSecureField: Bool,
        isEditableTextInput: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.elementIdentifier = elementIdentifier
        self.isSecureField = isSecureField
        self.isEditableTextInput = isEditableTextInput
    }
}

public enum CorrectionHandlingResult: Equatable, Sendable {
    case notHandled
    case handled
    case handledWithInputSourceSelectionFailure(expectedLanguage: Language)
}

public protocol TextReplacing {
    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: CorrectionBoundary?
    ) -> Bool
}

public protocol PreviousTextValidating {
    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        context: FocusContext
    ) -> Bool
}

public struct RejectingPreviousTextValidator: PreviousTextValidating {
    public init() {}

    public func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        context: FocusContext
    ) -> Bool {
        false
    }
}

public protocol InputSourceSelecting {
    @discardableResult func select(_ language: Language) -> Bool
    @discardableResult func selectExact(identifier: String) -> Bool
}

public extension InputSourceSelecting {
    @discardableResult
    func selectExact(identifier: String) -> Bool { false }
}

public protocol CorrectionCounting {
    func incrementCorrectionCount()
}

public protocol RuntimeClock {
    var now: Date { get }
}
