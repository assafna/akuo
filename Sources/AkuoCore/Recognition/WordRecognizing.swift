public protocol WordRecognizing {
    func recognizes(_ word: String, as language: Language) -> Bool
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

    public func recognizes(_ word: String, as language: Language) -> Bool {
        let normalizedWord: String
        switch language {
        case .english:
            normalizedWord = word.lowercased()
        case .hebrew:
            normalizedWord = word
        }

        return primary.recognizes(normalizedWord, as: language)
            || fallback.recognizes(normalizedWord, as: language)
    }
}
