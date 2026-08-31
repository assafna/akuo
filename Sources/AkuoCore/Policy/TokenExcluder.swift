public struct TokenExcluder: Sendable {
    private static let excludedPunctuation = Set<Character>("/\\@_.,;[]':")
    private static let hebrewFinalLetters = Set<Character>("ךםןףץ")

    public init() {}

    public func shouldExclude(
        _ token: String,
        conversion: LayoutConversion?
    ) -> Bool {
        let hasAuthoritativePhysicalEvidence =
            conversion?.hasAuthoritativePhysicalEvidence == true
        guard !token.isEmpty else {
            return !hasAuthoritativePhysicalEvidence
        }

        if token.contains(where: { $0.isNumber }) || token.contains("⌘") {
            return true
        }

        if hasSourceCodeCasing(token) { return true }

        let hasEnglish = token.contains(where: isEnglishLetter)
        let hasHebrew = token.contains(where: KeyboardLayoutMap.hebrewLetters.contains)
        if hasEnglish && hasHebrew { return true }

        if hasDomainLikeShape(token) { return true }

        if token.contains(where: Self.excludedPunctuation.contains),
           !isPermittedLayoutLetterPunctuation(token, conversion: conversion) {
            return true
        }

        return token.count == 1
            && (hasEnglish || hasHebrew)
            && !hasAuthoritativePhysicalEvidence
    }

    private func isPermittedLayoutLetterPunctuation(
        _ token: String,
        conversion: LayoutConversion?
    ) -> Bool {
        guard let conversion,
              conversion.original == token,
              hasTargetWordShape(conversion),
              hasSupportedPunctuationPlacement(token, source: conversion.source),
              !isPunctuationDominated(token) else {
            return false
        }
        return true
    }

    private func hasSupportedPunctuationPlacement(
        _ token: String,
        source: Language
    ) -> Bool {
        guard source == .hebrew else { return true }
        guard let first = token.first,
              first == "/" || first == "'" else {
            return false
        }

        let remainder = token.dropFirst()
        return !remainder.isEmpty
            && remainder.allSatisfy(KeyboardLayoutMap.hebrewLetters.contains)
    }

    private func hasTargetWordShape(_ conversion: LayoutConversion) -> Bool {
        switch conversion.target {
        case .english:
            return !conversion.candidate.isEmpty
                && conversion.candidate.allSatisfy(isEnglishLetter)
        case .hebrew:
            return hasHebrewWordShape(conversion.candidate)
        }
    }

    private func hasHebrewWordShape(_ candidate: String) -> Bool {
        let characters = Array(candidate)
        guard !characters.isEmpty,
              characters.allSatisfy(KeyboardLayoutMap.hebrewLetters.contains) else {
            return false
        }

        return characters.dropLast().allSatisfy {
            !Self.hebrewFinalLetters.contains($0)
        }
    }

    private func hasDomainLikeShape(_ token: String) -> Bool {
        let labels = token.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1 else { return false }

        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { character in
                isEnglishLetter(character)
                    || KeyboardLayoutMap.hebrewLetters.contains(character)
                    || character.isNumber
                    || character == "-"
            }
        }
    }

    private func isPunctuationDominated(_ token: String) -> Bool {
        let letterCount = token.count { character in
            isEnglishLetter(character)
                || KeyboardLayoutMap.hebrewLetters.contains(character)
        }
        return token.count - letterCount > letterCount
    }

    private func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private func hasSourceCodeCasing(_ token: String) -> Bool {
        let characters = token.filter(isEnglishLetter)

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
