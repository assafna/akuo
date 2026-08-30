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

    func testLocalFallbackCannotAuthorizeCandidateOutsideSeedLexicon() {
        let seed = SeedLexicon()
        let originalRecognizer = CompositeWordRecognizer(
            primary: seed,
            fallback: StubRecognizer(english: ["zzzz"], hebrew: [])
        )
        let policy = CorrectionPolicy(
            layoutMap: KeyboardLayoutMap(),
            originalScorer: WordScorer(recognizer: originalRecognizer),
            candidateScorer: WordScorer(recognizer: seed),
            excluder: TokenExcluder()
        )

        XCTAssertEqual(policy.decision(for: "זזזז"), .keep(.candidateUnknown))
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

        XCTAssertTrue(lexicon.recognizes("HELLO", as: .english))
        XCTAssertTrue(lexicon.recognizes("quick", as: .english))
        XCTAssertTrue(lexicon.recognizes("שלום", as: .hebrew))
    }

    func testScoresScriptAndRecognitionWithFixedWeights() {
        let scorer = WordScorer(recognizer: StubRecognizer(english: ["hello"], hebrew: []))

        XCTAssertEqual(
            scorer.evidence(for: "HELLO", language: .english),
            .init(language: .english, scriptMatches: true, recognized: true, score: 100)
        )
        XCTAssertEqual(
            scorer.evidence(for: "unknown", language: .english),
            .init(language: .english, scriptMatches: true, recognized: false, score: 20)
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

    func recognizes(_ word: String, as language: Language) -> Bool {
        switch language {
        case .english:
            english.contains(word.lowercased())
        case .hebrew:
            hebrew.contains(word)
        }
    }
}
