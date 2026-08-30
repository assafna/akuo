import XCTest
@testable import AkuoCore

final class CorrectionPolicyTests: XCTestCase {
    func testCorrectsAkuoToShalom() {
        let policy = makePolicy(recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום", "עולם"]))

        XCTAssertEqual(
            policy.decision(for: "akuo"),
            .correct(.init(original: "akuo", replacement: "שלום", target: .hebrew))
        )
    }

    func testCorrectsRecognizedHebrewCandidatesUsingPunctuationLayoutKeys() {
        let cases = [("gcrh,", "עברית"), ("tr.", "ארץ"), ("gu;", "עוף")]
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: ["עברית", "ארץ", "עוף"]
        ))

        for (source, replacement) in cases {
            XCTAssertEqual(
                policy.decision(for: source),
                .correct(.init(original: source, replacement: replacement, target: .hebrew)),
                source
            )
        }
    }

    func testCorrectsHebrewLayoutHello() {
        let policy = makePolicy(recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום", "עולם"]))

        XCTAssertEqual(
            policy.decision(for: "יקךךם"),
            .correct(.init(original: "יקךךם", replacement: "hello", target: .english))
        )
    }

    func testKeepsKnownOriginal() {
        let policy = makePolicy(recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום", "עולם"]))

        XCTAssertEqual(policy.decision(for: "hello"), .keep(.originalRecognized))
    }

    func testKeepsRecognizedPunctuatedOriginalWithTargetWordShape() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: ["the,"],
            hebrew: ["איקת"]
        ))

        XCTAssertEqual(policy.decision(for: "the,"), .keep(.originalRecognized))
    }

    func testKeepsLayoutPunctuationWhenConvertedCandidateIsUnknown() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: []))

        XCTAssertEqual(policy.decision(for: "gcrh,"), .keep(.candidateUnknown))
    }

    func testKeepsDomainExcludedEvenWhenMappedCandidateIsRecognized() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: ["שלוםץשפפ"]
        ))

        XCTAssertEqual(policy.decision(for: "akuo.app"), .keep(.excluded))
    }

    func testKeepsInteriorHebrewSlashExcludedEvenWhenMappedCandidateIsRecognized() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: ["heqlo"],
            hebrew: []
        ))

        XCTAssertEqual(policy.decision(for: "יק/ךם"), .keep(.excluded))
    }

    func testKeepsPascalCaseWithLayoutPunctuationExcluded() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: ["שלוםת"]
        ))

        XCTAssertEqual(policy.decision(for: "Akuo,"), .keep(.excluded))
    }

    func testKeepsLeadingDotPathExcludedEvenWhenMappedCandidateIsRecognized() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: ["ץנשדירב"]
        ))

        XCTAssertEqual(policy.decision(for: ".bashrc"), .keep(.excluded))
    }

    func testKeepsWhenBothFormsAreKnown() {
        let recognizer = StubRecognizer(english: ["go"], hebrew: ["עם"])
        let policy = makePolicy(recognizer: recognizer)

        XCTAssertEqual(policy.decision(for: "go"), .keep(.originalRecognized))
        XCTAssertEqual(policy.decision(for: "עם"), .keep(.originalRecognized))
    }

    func testKeepsWhenNeitherFormIsKnown() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: []))

        XCTAssertEqual(policy.decision(for: "akuo"), .keep(.candidateUnknown))
    }

    func testKeepsWhenOriginalRecognitionIsUnavailable() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: ["שלום"],
            unavailableEnglish: ["akuo"]
        ))

        XCTAssertEqual(policy.decision(for: "akuo"), .keep(.recognitionUnavailable))
    }

    func testKeepsWhenCandidateRecognitionIsUnavailable() {
        let policy = makePolicy(recognizer: StubRecognizer(
            english: [],
            hebrew: [],
            unavailableHebrew: ["שלום"]
        ))

        XCTAssertEqual(policy.decision(for: "akuo"), .keep(.recognitionUnavailable))
    }

    func testKeepsMixedSentenceTokensIndependently() {
        let policy = makePolicy(recognizer: StubRecognizer(english: ["hello"], hebrew: ["שלום", "עולם"]))

        XCTAssertEqual(policy.decision(for: "hello"), .keep(.originalRecognized))
        XCTAssertEqual(
            policy.decision(for: "akuo"),
            .correct(.init(original: "akuo", replacement: "שלום", target: .hebrew))
        )
        XCTAssertEqual(policy.decision(for: "עולם"), .keep(.originalRecognized))
    }

    func testKeepsUnknownSingleLetter() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: []))

        XCTAssertEqual(policy.decision(for: "x"), .keep(.excluded))
    }

    func testKeepsExcludedCamelCaseTokenWhenCandidateIsKnown() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: ["שלום"]))

        XCTAssertEqual(policy.decision(for: "aKuo"), .keep(.excluded))
    }

    func testKeepsExcludedPascalCaseTokenWhenCandidateIsKnown() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: ["שלום"]))

        XCTAssertEqual(policy.decision(for: "Akuo"), .keep(.excluded))
    }

    func testKeepsPunctuationOnlyCodePunctuationExcluded() {
        let policy = makePolicy(recognizer: StubRecognizer(english: [], hebrew: []))

        XCTAssertEqual(policy.decision(for: ";"), .keep(.excluded))
    }

    func testSeedLexiconNormalizesEnglishButNotHebrew() {
        let lexicon = SeedLexicon()

        XCTAssertEqual(lexicon.recognitionStatus(for: "HELLO", as: .english), .recognized)
        XCTAssertEqual(lexicon.recognitionStatus(for: "quick", as: .english), .recognized)
        XCTAssertEqual(lexicon.recognitionStatus(for: "שלום", as: .hebrew), .recognized)
    }

    func testScoresScriptAndRecognitionWithFixedWeights() {
        let scorer = WordScorer(recognizer: StubRecognizer(english: ["hello"], hebrew: []))

        XCTAssertEqual(
            scorer.evidence(for: "HELLO", language: .english),
            .init(language: .english, scriptMatches: true, status: .recognized, score: 100)
        )
        XCTAssertEqual(
            scorer.evidence(for: "unknown", language: .english),
            .init(language: .english, scriptMatches: true, status: .unknown, score: 20)
        )
    }

    func testUnavailableRecognitionCarriesNoRecognitionWeight() {
        let scorer = WordScorer(recognizer: StubRecognizer(
            english: [],
            hebrew: [],
            unavailableEnglish: ["unknown"]
        ))

        XCTAssertEqual(
            scorer.evidence(for: "unknown", language: .english),
            .init(
                language: .english,
                scriptMatches: true,
                status: .unavailable,
                score: 20
            )
        )
    }

    private func makePolicy(recognizer: some WordRecognizing) -> CorrectionPolicy {
        let scorer = WordScorer(recognizer: recognizer)
        return CorrectionPolicy(
            layoutMap: KeyboardLayoutMap(),
            originalScorer: scorer,
            candidateScorer: scorer,
            excluder: TokenExcluder()
        )
    }
}

private struct StubRecognizer: WordRecognizing {
    let english: Set<String>
    let hebrew: Set<String>
    let unavailableEnglish: Set<String>
    let unavailableHebrew: Set<String>

    init(
        english: Set<String>,
        hebrew: Set<String>,
        unavailableEnglish: Set<String> = [],
        unavailableHebrew: Set<String> = []
    ) {
        self.english = english
        self.hebrew = hebrew
        self.unavailableEnglish = unavailableEnglish
        self.unavailableHebrew = unavailableHebrew
    }

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        switch language {
        case .english:
            if unavailableEnglish.contains(word.lowercased()) { return .unavailable }
            return english.contains(word.lowercased()) ? .recognized : .unknown
        case .hebrew:
            if unavailableHebrew.contains(word) { return .unavailable }
            return hebrew.contains(word) ? .recognized : .unknown
        }
    }
}
