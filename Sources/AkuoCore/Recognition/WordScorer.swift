public struct RecognitionEvidence: Equatable, Sendable {
    public let language: Language
    public let scriptMatches: Bool
    public let recognized: Bool
    public let score: Int

    public init(language: Language, scriptMatches: Bool, recognized: Bool, score: Int) {
        self.language = language
        self.scriptMatches = scriptMatches
        self.recognized = recognized
        self.score = score
    }
}

public struct WordScorer {
    private let recognizer: any WordRecognizing

    public init(recognizer: some WordRecognizing) {
        self.recognizer = recognizer
    }

    public func evidence(for word: String, language: Language) -> RecognitionEvidence {
        let scriptMatches = Self.matchesScript(word, language: language)
        let recognized = recognizer.recognizes(word, as: language)
        let score = (scriptMatches ? 20 : 0) + (recognized ? 80 : 0)

        return RecognitionEvidence(
            language: language,
            scriptMatches: scriptMatches,
            recognized: recognized,
            score: score
        )
    }

    private static func matchesScript(_ word: String, language: Language) -> Bool {
        let hasEnglish = word.contains(where: isEnglishLetter)
        let hasHebrew = word.contains(where: KeyboardLayoutMap.hebrewLetters.contains)

        switch language {
        case .english:
            return hasEnglish && !hasHebrew
        case .hebrew:
            return hasHebrew && !hasEnglish
        }
    }

    private static func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}
