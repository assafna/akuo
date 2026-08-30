public struct SeedLexicon: WordRecognizing, Sendable {
    private static let english: Set<String> = [
        "a", "and", "are", "be", "for", "from", "go", "good", "hello",
        "how", "i", "in", "is", "it", "me", "my", "no", "of", "on",
        "please", "quick", "thanks", "that", "the", "this", "to", "we", "what",
        "with", "yes", "you",
    ]

    private static let hebrew: Set<String> = [
        "אני", "את", "אתה", "אתם", "בבקשה", "גם", "הוא", "היא", "היה",
        "היי", "הכל", "זה", "טוב", "כן", "לא", "לי", "מה", "מי", "עם",
        "על", "פה", "של", "שלום", "תודה", "יש", "אנחנו", "עולם",
    ]

    public init() {}

    public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let isRecognized = switch language {
        case .english:
            Self.english.contains(word.lowercased())
        case .hebrew:
            Self.hebrew.contains(word)
        }
        return isRecognized ? .recognized : .unknown
    }
}
