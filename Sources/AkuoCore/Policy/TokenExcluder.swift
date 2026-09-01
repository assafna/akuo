public struct TokenExcluder: Sendable {
    private static let excludedPunctuation = Set<Character>("/\\@_.,;[]':׳")

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

        if let conversion,
           isPunctuationDominated(conversion.candidate) {
            return true
        }

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
              hasTargetWordShape(conversion) else {
            return false
        }
        // A physical conversion exists only when every observed key position
        // aligns with the visible token. That evidence safely covers Apple's
        // silent and composite Hebrew Shift outputs without maintaining a
        // second, incomplete punctuation whitelist here.
        if conversion.physicalEvidence != nil { return true }

        guard hasSupportedPunctuationPlacement(token, conversion: conversion),
              !isPunctuationDominated(token) else {
            return false
        }
        return true
    }

    private func hasSupportedPunctuationPlacement(
        _ token: String,
        conversion: LayoutConversion
    ) -> Bool {
        guard conversion.source == .hebrew else {
            // Without a complete physical trace, retain the legacy English to
            // Hebrew allowance only for punctuation keys that map to letters.
            // Terminal punctuation envelopes require the exact target-layout
            // output recorded by the live event monitor.
            return conversion.candidate.allSatisfy(
                KeyboardLayoutMap.hebrewLetters.contains
            )
        }
        if conversion.target == .english,
           OrthographicWordShape.isJoinedEnglishWord(conversion.candidate) {
            return hasSupportedHebrewSourceForJoinedEnglishWord(token)
        }

        guard let first = token.first,
              first == "/" || first == "'" || first == "׳" else {
            return false
        }

        let remainder = token.dropFirst()
        return !remainder.isEmpty
            && remainder.allSatisfy(KeyboardLayoutMap.hebrewLetters.contains)
    }

    private func hasSupportedHebrewSourceForJoinedEnglishWord(
        _ token: String
    ) -> Bool {
        token.enumerated().allSatisfy { index, character in
            if KeyboardLayoutMap.hebrewLetters.contains(character)
                || character == "," {
                return true
            }
            return index == 0
                && (character == "/" || character == "'" || character == "׳")
        }
    }

    private func hasTargetWordShape(_ conversion: LayoutConversion) -> Bool {
        switch conversion.target {
        case .english:
            return OrthographicWordShape.isEnglishWord(conversion.candidate)
        case .hebrew:
            return OrthographicWordShape.recognitionToken(
                for: conversion.candidate,
                language: .hebrew
            ) != nil
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
