enum OrthographicWordShape {
    private static let englishJoiners = Set<Character>(["'", "’"])
    private static let englishSegmentJoiners = englishJoiners.union(["-"])
    private static let hebrewSegmentJoiners = Set<Character>(["׳", "״", "־", "-"])
    private static let hebrewFinalLetters = Set<Character>("ךםןףץ")
    private static let terminalPunctuation = Set<Character>(".,!?:;…")
    private static let wrapperPairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "<": ">",
        "\"": "\"", "“": "”", "‘": "’", "״": "״",
    ]

    static func isEnglishWord(_ candidate: String) -> Bool {
        recognitionToken(for: candidate, language: .english) != nil
    }

    static func isJoinedEnglishWord(_ candidate: String) -> Bool {
        guard let token = recognitionToken(for: candidate, language: .english) else {
            return false
        }
        return token.contains(where: englishJoiners.contains)
    }

    static func recognitionToken(
        for token: String,
        language: Language
    ) -> String? {
        var characters = Array(token)
        guard !characters.isEmpty else { return nil }

        while characters.last.map(terminalPunctuation.contains) == true {
            characters.removeLast()
        }
        while let first = characters.first,
              let expectedClosing = wrapperPairs[first],
              characters.last == expectedClosing,
              characters.count > 2 {
            characters.removeFirst()
            characters.removeLast()
            while characters.last.map(terminalPunctuation.contains) == true {
                characters.removeLast()
            }
        }
        guard !characters.isEmpty else { return nil }

        let core = String(characters)
        switch language {
        case .english:
            return hasValidSegments(
                characters,
                letters: isEnglishLetter,
                joiners: englishSegmentJoiners,
                segmentIsValid: { _ in true }
            ) ? core : nil
        case .hebrew:
            return hasValidSegments(
                characters,
                letters: KeyboardLayoutMap.hebrewLetters.contains,
                joiners: hebrewSegmentJoiners,
                segmentIsValid: { segment in
                    segment.dropLast().allSatisfy {
                        !hebrewFinalLetters.contains($0)
                    }
                }
            ) ? core : nil
        }
    }

    private static func hasValidSegments(
        _ characters: [Character],
        letters: (Character) -> Bool,
        joiners: Set<Character>,
        segmentIsValid: ([Character]) -> Bool
    ) -> Bool {
        var segment: [Character] = []
        for character in characters {
            if letters(character) {
                segment.append(character)
                continue
            }
            guard joiners.contains(character),
                  !segment.isEmpty,
                  segmentIsValid(segment) else {
                return false
            }
            segment.removeAll(keepingCapacity: true)
        }
        return !segment.isEmpty && segmentIsValid(segment)
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
