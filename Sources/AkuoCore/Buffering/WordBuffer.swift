public enum BufferedInput: Equatable, Sendable {
    case text(String)
    case observedKeyStroke(ObservedKeyStroke)
    case deleteBackward
    case boundary(String)
    case navigation
    case shortcut
    case reset
}

public struct ObservedKeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let capsLock = Self(rawValue: 1 << 1)
}

public struct ObservedKeyStroke: Equatable, Sendable {
    public let text: String
    public let keyCode: Int
    public let modifiers: ObservedKeyModifiers
    public let targetText: String?

    public init(
        text: String,
        keyCode: Int,
        modifiers: ObservedKeyModifiers = [],
        targetText: String? = nil
    ) {
        self.text = text
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.targetText = targetText
    }
}

public struct CompletedWord: Equatable, Sendable {
    public let token: String
    public let boundary: String
    public let keyStrokes: [ObservedKeyStroke]

    public init(
        token: String,
        boundary: String,
        keyStrokes: [ObservedKeyStroke] = []
    ) {
        self.token = token
        self.boundary = boundary
        self.keyStrokes = keyStrokes
    }
}

public enum BufferResult: Equatable, Sendable {
    case accumulating
    case completed(CompletedWord)
    case passThrough
    case reset
}

public struct WordBuffer: Sendable {
    public private(set) var currentToken = ""
    private var currentKeyStrokes: [ObservedKeyStroke] = []

    public var unfinishedWord: CompletedWord? {
        guard !currentToken.isEmpty || !currentKeyStrokes.isEmpty else {
            return nil
        }
        return CompletedWord(
            token: currentToken,
            boundary: "",
            keyStrokes: currentKeyStrokes
        )
    }

    public init() {}

    public mutating func consume(_ input: BufferedInput) -> BufferResult {
        switch input {
        case let .text(text):
            currentToken.append(contentsOf: text)
            return .accumulating

        case let .observedKeyStroke(keyStroke):
            currentToken.append(contentsOf: keyStroke.text)
            currentKeyStrokes.append(keyStroke)
            return .accumulating

        case .deleteBackward:
            if !currentToken.isEmpty {
                currentToken.removeLast()
            }
            // A deletion can merge or split Unicode grapheme clusters, so the
            // physical trace is no longer guaranteed to align with the visible
            // token. Fail closed for capitalization recovery after editing.
            currentKeyStrokes.removeAll(keepingCapacity: true)
            return .accumulating

        case let .boundary(boundary):
            guard !currentToken.isEmpty || !currentKeyStrokes.isEmpty else {
                currentKeyStrokes.removeAll(keepingCapacity: true)
                return .passThrough
            }
            let completed = CompletedWord(
                token: currentToken,
                boundary: boundary,
                keyStrokes: currentKeyStrokes
            )
            currentToken.removeAll(keepingCapacity: true)
            currentKeyStrokes.removeAll(keepingCapacity: true)
            return .completed(completed)

        case .navigation, .shortcut, .reset:
            reset()
            return .reset
        }
    }

    public mutating func reset() {
        currentToken.removeAll(keepingCapacity: true)
        currentKeyStrokes.removeAll(keepingCapacity: true)
    }
}
