import AppKit
import AkuoCore

struct SpellingCheckResult: Equatable {
    let misspelledRange: NSRange
    let wordCount: Int
}

protocol SpellCheckerBackend {
    var availableLanguages: Set<String> { get }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult
}

private struct AppKitSpellCheckerBackend: SpellCheckerBackend {
    var availableLanguages: Set<String> {
        Set(NSSpellChecker.shared.availableLanguages)
    }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult {
        var wordCount = 0
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        return .init(misspelledRange: range, wordCount: wordCount)
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

        guard backend.availableLanguages.contains(languageCode) else {
            return .unavailable
        }

        let result = backend.checkSpelling(in: word, language: languageCode)
        guard result.wordCount >= 0 else { return .unavailable }
        return result.misspelledRange.location == NSNotFound
            ? .recognized
            : .unknown
    }
}
