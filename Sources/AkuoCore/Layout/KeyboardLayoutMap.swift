public struct LayoutConversion: Equatable, Sendable {
    public let original: String
    public let candidate: String
    public let source: Language
    public let target: Language

    public init(original: String, candidate: String, source: Language, target: Language) {
        self.original = original
        self.candidate = candidate
        self.source = source
        self.target = target
    }
}

public struct KeyboardLayoutMap: Sendable {
    public init() {}

    public static let englishToHebrew: [Character: Character] = [
        "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א",
        "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "[": "]", "]": "[",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע",
        "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף", "'": ",",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ",
        "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": "."
    ]

    public static let hebrewLetters = Set("אבגדהוזחטיךכלםמןנסעףפץצקרשת")

    private static let hebrewToEnglish: [Character: Character] = {
        var inverse: [Character: Character] = [:]
        for (english, hebrew) in englishToHebrew {
            precondition(inverse[hebrew] == nil, "Keyboard layout values must be unique")
            inverse[hebrew] = english
        }
        return inverse
    }()

    public func convert(_ token: String) -> LayoutConversion? {
        guard !token.isEmpty else { return nil }

        var source: Language?
        for character in token {
            let characterLanguage: Language?
            if Self.isEnglishLetter(character) {
                characterLanguage = .english
            } else if Self.hebrewLetters.contains(character) {
                characterLanguage = .hebrew
            } else {
                characterLanguage = nil
            }

            guard let characterLanguage else { continue }
            guard source == nil || source == characterLanguage else { return nil }
            source = characterLanguage
        }

        guard let source else { return nil }
        let target: Language = source == .english ? .hebrew : .english
        let lookup = source == .english ? Self.englishToHebrew : Self.hebrewToEnglish
        var candidate = String()
        candidate.reserveCapacity(token.count)

        for character in token {
            let key = source == .english ? Self.lowercaseASCII(character) : character
            guard let converted = lookup[key] else { return nil }
            candidate.append(converted)
        }

        return LayoutConversion(original: token, candidate: candidate, source: source, target: target)
    }

    private static func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func lowercaseASCII(_ character: Character) -> Character {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return character
        }
        guard scalar.value >= 65 && scalar.value <= 90,
              let lowercase = UnicodeScalar(scalar.value + 32) else {
            return character
        }
        return Character(String(lowercase))
    }
}
