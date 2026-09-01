public struct PhysicalLayoutEvidence: Equatable, Sendable {
    public let recoveredShift: Bool
    public let hasAlphabeticKey: Bool

    public init(recoveredShift: Bool) {
        self.init(recoveredShift: recoveredShift, hasAlphabeticKey: true)
    }

    public init(recoveredShift: Bool, hasAlphabeticKey: Bool) {
        self.recoveredShift = recoveredShift
        self.hasAlphabeticKey = hasAlphabeticKey
    }
}

public struct LayoutConversion: Equatable, Sendable {
    public let original: String
    public let candidate: String
    public let source: Language
    public let target: Language
    public let physicalEvidence: PhysicalLayoutEvidence?

    public init(
        original: String,
        candidate: String,
        source: Language,
        target: Language,
        physicalEvidence: PhysicalLayoutEvidence? = nil
    ) {
        self.original = original
        self.candidate = candidate
        self.source = source
        self.target = target
        self.physicalEvidence = physicalEvidence
    }

    public var hasAuthoritativePhysicalEvidence: Bool {
        guard let physicalEvidence,
              physicalEvidence.hasAlphabeticKey else { return false }
        if physicalEvidence.recoveredShift { return true }

        // A complete physical trace resolves the otherwise ambiguous Hebrew
        // final-letter forms for the only standalone English letter words.
        return target == .english
            && candidate.count == 1
            && (candidate.lowercased() == "a" || candidate.lowercased() == "i")
    }
}

public struct KeyboardLayoutMap: Sendable {
    public init() {}

    public static let englishToHebrew: [Character: Character] = [
        "q": "/", "w": "׳", "e": "ק", "r": "ר", "t": "א",
        "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "[": "]", "]": "[",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע",
        "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף", "'": ",",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ",
        "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": "."
    ]

    public static let hebrewLetters = Set("אבגדהוזחטיךכלםמןנסעףפץצקרשת")

    // Apple Hebrew emits these distinct strings for the shifted A, U, C/K,
    // and D letter keys. Most other shifted letter keys emit no text at all.
    private static let shiftedHebrewOutputs = Set(["שׁ", "וֹ", "לֹ", "„"])
    private static let unambiguousShiftedHebrewToEnglish: [Character: Character] = [
        Character("שׁ"): "A",
        Character("וֹ"): "U",
        Character("„"): "D",
    ]

    // Virtual key codes are physical positions and therefore remain stable
    // while the active input source changes between ABC/U.S. and Hebrew.
    private static let englishLetterByKeyCode: [Int: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g",
        4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s",
        17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
    private static let englishWordJoinerByKeyCode: [
        Int: (hebrewText: String, candidate: Character)
    ] = [
        39: (",", "'"),
    ]

    private static let hebrewToEnglish: [Character: Character] = {
        var inverse: [Character: Character] = [:]
        for (english, hebrew) in englishToHebrew {
            precondition(inverse[hebrew] == nil, "Keyboard layout values must be unique")
            inverse[hebrew] = english
        }
        inverse["'"] = "w"
        return inverse
    }()

    public static func isAlphabeticKeyCode(_ keyCode: Int) -> Bool {
        englishLetterByKeyCode[keyCode] != nil
    }

    public func convert(
        _ token: String,
        sourceHint: Language? = nil,
        keyStrokes: [ObservedKeyStroke] = []
    ) -> LayoutConversion? {
        guard !token.isEmpty || !keyStrokes.isEmpty else { return nil }

        var source: Language?
        for character in token {
            let characterLanguage: Language?
            if Self.isEnglishLetter(character) {
                characterLanguage = .english
            } else if Self.hebrewLetters.contains(character)
                        || Self.shiftedHebrewOutputs.contains(String(character)) {
                characterLanguage = .hebrew
            } else {
                characterLanguage = nil
            }

            guard let characterLanguage else { continue }
            guard source == nil || source == characterLanguage else { return nil }
            source = characterLanguage
        }

        if let sourceHint, let source, sourceHint != source { return nil }
        guard let source = source ?? sourceHint else { return nil }
        let target: Language = source == .english ? .hebrew : .english

        if let physicalConversion = Self.translatedPhysicalCandidate(
            for: token,
            source: source,
            keyStrokes: keyStrokes
        ) {
            return LayoutConversion(
                original: token,
                candidate: physicalConversion.candidate,
                source: source,
                target: target,
                physicalEvidence: .init(
                    recoveredShift: physicalConversion.recoveredShift,
                    hasAlphabeticKey: keyStrokes.contains {
                        Self.isAlphabeticKeyCode($0.keyCode)
                    }
                )
            )
        }

        if source == .hebrew,
           let physicalConversion = Self.physicalEnglishCandidate(
               for: token,
               keyStrokes: keyStrokes
           ) {
            return LayoutConversion(
                original: token,
                candidate: physicalConversion.candidate,
                source: source,
                target: target,
                physicalEvidence: .init(
                    recoveredShift: physicalConversion.recoveredShift,
                    hasAlphabeticKey: keyStrokes.contains {
                        Self.isAlphabeticKeyCode($0.keyCode)
                    }
                )
            )
        }

        let lookup = source == .english ? Self.englishToHebrew : Self.hebrewToEnglish
        var candidate = String()
        candidate.reserveCapacity(token.count)

        for character in token {
            let key = source == .english ? Self.lowercaseASCII(character) : character
            let converted = source == .hebrew
                ? Self.unambiguousShiftedHebrewToEnglish[key] ?? lookup[key]
                : lookup[key]
            guard let converted else { return nil }
            candidate.append(converted)
        }

        return LayoutConversion(original: token, candidate: candidate, source: source, target: target)
    }

    private static func translatedPhysicalCandidate(
        for token: String,
        source: Language,
        keyStrokes: [ObservedKeyStroke]
    ) -> (candidate: String, recoveredShift: Bool)? {
        guard !keyStrokes.isEmpty,
              keyStrokes.map(\.text).joined() == token,
              keyStrokes.allSatisfy({ $0.targetText != nil }) else {
            return nil
        }

        let candidate = keyStrokes.compactMap(\.targetText).joined()
        guard !candidate.isEmpty else { return nil }
        let recoveredShift = source == .hebrew && keyStrokes.contains { keyStroke in
            guard keyStroke.modifiers.contains(.shift)
                    || keyStroke.modifiers.contains(.capsLock),
                  let targetText = keyStroke.targetText else {
                return false
            }
            return targetText.contains(where: isUppercaseEnglishLetter)
        }
        return (candidate, recoveredShift)
    }

    private static func physicalEnglishCandidate(
        for token: String,
        keyStrokes: [ObservedKeyStroke]
    ) -> (candidate: String, recoveredShift: Bool)? {
        guard !keyStrokes.isEmpty,
              keyStrokes.map(\.text).joined() == token else {
            return nil
        }

        var candidate = String()
        var recoveredShift = false
        candidate.reserveCapacity(keyStrokes.count)
        for keyStroke in keyStrokes {
            if let joiner = englishWordJoinerByKeyCode[keyStroke.keyCode],
               joiner.hebrewText == keyStroke.text {
                candidate.append(joiner.candidate)
                continue
            }

            guard let lowercase = englishLetterByKeyCode[keyStroke.keyCode] else {
                return nil
            }
            let wasShifted = keyStroke.text.isEmpty
                || shiftedHebrewOutputs.contains(keyStroke.text)
            recoveredShift = recoveredShift || wasShifted
            candidate.append(wasShifted ? uppercaseASCII(lowercase) : lowercase)
        }
        return (candidate, recoveredShift)
    }

    private static func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isUppercaseEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value)
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

    private static func uppercaseASCII(_ character: Character) -> Character {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return character
        }
        guard scalar.value >= 97 && scalar.value <= 122,
              let uppercase = UnicodeScalar(scalar.value - 32) else {
            return character
        }
        return Character(String(uppercase))
    }
}
