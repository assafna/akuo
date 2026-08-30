public struct TokenExcluder: Sendable {
    private static let excludedPunctuation = Set<Character>("/\\@_.,;[]':")

    public init() {}

    public func shouldExclude(_ token: String) -> Bool {
        guard !token.isEmpty else { return true }
        guard !isPermittedLeadingLayoutPunctuation(token) else { return false }

        if token.contains(where: Self.excludedPunctuation.contains) {
            return true
        }

        if token.contains(where: { $0.isNumber }) || token.contains("⌘") {
            return true
        }

        if hasSourceCodeCasing(token) {
            return true
        }

        let hasEnglish = token.contains(where: isEnglishLetter)
        let hasHebrew = token.contains(where: KeyboardLayoutMap.hebrewLetters.contains)
        if hasEnglish && hasHebrew {
            return true
        }

        return token.count == 1 && (hasEnglish || hasHebrew)
    }

    private func isPermittedLeadingLayoutPunctuation(_ token: String) -> Bool {
        guard let first = token.first, first == "/" || first == "'" else { return false }

        let remainder = token.dropFirst()
        guard !remainder.isEmpty,
              remainder.allSatisfy(KeyboardLayoutMap.hebrewLetters.contains) else {
            return false
        }

        return KeyboardLayoutMap().convert(token)?.target == .english
    }

    private func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private func hasSourceCodeCasing(_ token: String) -> Bool {
        let characters = Array(token)

        if let first = characters.first,
           characters.count > 1,
           isUppercaseEnglish(first),
           characters.dropFirst().allSatisfy(isLowercaseEnglish) {
            return true
        }

        for (previous, current) in zip(characters, characters.dropFirst())
            where isLowercaseEnglish(previous) && isUppercaseEnglish(current) {
            return true
        }

        for (current, next) in zip(characters.dropFirst(), characters.dropFirst(2))
            where isUppercaseEnglish(current) && isLowercaseEnglish(next) {
            return true
        }

        return false
    }

    private func isLowercaseEnglish(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (97...122).contains(scalar.value)
    }

    private func isUppercaseEnglish(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value)
    }
}
