import AppKit
import AkuoCore

protocol SpellCheckerBackend {
    func misspelledRange(in word: String, language: String) -> NSRange
}

private struct AppKitSpellCheckerBackend: SpellCheckerBackend {
    func misspelledRange(in word: String, language: String) -> NSRange {
        var wordCount = 0
        return NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
    }
}

public struct SystemSpellChecker: WordRecognizing {
    private let backend: any SpellCheckerBackend

    public init() {
        backend = AppKitSpellCheckerBackend()
    }

    init(backend: some SpellCheckerBackend) {
        self.backend = backend
    }

    public func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        guard !word.isEmpty else { return .unknown }

        let languageCode: String
        switch language {
        case .english:
            languageCode = "en_US"
        case .hebrew:
            languageCode = "he_IL"
        }

        return backend.misspelledRange(in: word, language: languageCode).location == NSNotFound
            ? .recognized
            : .unknown
    }
}
