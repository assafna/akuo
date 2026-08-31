enum OrthographicWordShape {
    private static let englishJoiners = Set<Character>(["'", "’"])

    static func isEnglishWord(_ candidate: String) -> Bool {
        var requiresLetter = true

        for character in candidate {
            if isEnglishLetter(character) {
                requiresLetter = false
            } else if englishJoiners.contains(character), !requiresLetter {
                requiresLetter = true
            } else {
                return false
            }
        }

        return !requiresLetter
    }

    static func isJoinedEnglishWord(_ candidate: String) -> Bool {
        isEnglishWord(candidate)
            && candidate.contains(where: englishJoiners.contains)
    }

    private static func isEnglishLetter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }
}
