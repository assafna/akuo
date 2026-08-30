public enum RecognitionStatus: Equatable, Sendable {
    case recognized
    case unknown
    case unavailable
}

public protocol WordRecognizing {
    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus
}

public struct CompositeWordRecognizer: WordRecognizing {
    private let primary: any WordRecognizing
    private let fallback: any WordRecognizing

    public init(
        primary: some WordRecognizing,
        fallback: some WordRecognizing
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let normalizedWord = language == .english ? word.lowercased() : word

        switch primary.recognitionStatus(for: normalizedWord, as: language) {
        case .recognized:
            return .recognized
        case .unknown:
            return fallback.recognitionStatus(for: normalizedWord, as: language)
        case .unavailable:
            return .unavailable
        }
    }
}
