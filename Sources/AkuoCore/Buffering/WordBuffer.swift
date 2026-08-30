public enum BufferedInput: Equatable, Sendable {
    case text(String)
    case deleteBackward
    case boundary(String)
    case navigation
    case shortcut
    case reset
}

public struct CompletedWord: Equatable, Sendable {
    public let token: String
    public let boundary: String

    public init(token: String, boundary: String) {
        self.token = token
        self.boundary = boundary
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

    public init() {}

    public mutating func consume(_ input: BufferedInput) -> BufferResult {
        switch input {
        case let .text(text):
            currentToken.append(contentsOf: text)
            return .accumulating

        case .deleteBackward:
            if !currentToken.isEmpty {
                currentToken.removeLast()
            }
            return .accumulating

        case let .boundary(boundary):
            guard !currentToken.isEmpty else { return .passThrough }
            let completed = CompletedWord(token: currentToken, boundary: boundary)
            currentToken.removeAll(keepingCapacity: true)
            return .completed(completed)

        case .navigation, .shortcut, .reset:
            reset()
            return .reset
        }
    }

    public mutating func reset() {
        currentToken.removeAll(keepingCapacity: true)
    }
}
