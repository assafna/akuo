import XCTest
@testable import AkuoCore

final class TokenExcluderTests: XCTestCase {
    private let excluder = TokenExcluder()

    func testExcludesNonWordTokenShapes() {
        for token in [
            "https://akuo.app",
            "me@example.com",
            "/tmp/file",
            "file_name",
            "abc123",
            "⌘z",
            "abcשלום",
        ] {
            XCTAssertTrue(shouldExclude(token), "Expected \(token) to be excluded")
        }
    }

    func testExcludesUnknownSingleLetters() {
        XCTAssertTrue(shouldExclude("x"))
        XCTAssertTrue(shouldExclude("ת"))
    }

    func testExcludesSourceCodeCasingAndUnsupportedPunctuationShapes() {
        for token in ["aKuo", "Akuo", "URLSession", "akuo[", "akuo]", "akuo'"] {
            XCTAssertTrue(shouldExclude(token), "Expected \(token) to be excluded")
        }
    }

    func testAllowsPunctuationKeysWhoseWholeConversionIsTargetLetters() {
        for token in ["gcrh,", "tr.", "gu;"] {
            XCTAssertFalse(shouldExclude(token), "Expected \(token) to reach recognition")
        }
    }

    func testExcludesPunctuationDominatedLayoutLetterShape() {
        XCTAssertTrue(shouldExclude(",,,a"))
    }

    func testRejectsApostropheWithoutHebrewDirection() {
        XCTAssertTrue(shouldExclude("'abc"))
        XCTAssertTrue(shouldExclude("akuo'"))
    }

    func testAllowsLeadingLayoutPunctuationOnlyForHebrewTokenThatConvertsToEnglish() {
        XCTAssertFalse(shouldExclude("/וןבל"))
        XCTAssertFalse(shouldExclude("'וןבל"))
        XCTAssertFalse(shouldExclude("׳וןבל"))
    }

    func testAllowsInternalEnglishApostropheCandidateFromHebrewLayout() {
        XCTAssertFalse(shouldExclude("גםמ,א"))
        XCTAssertFalse(shouldExclude("'ק,רק"))
    }

    func testAllowsCurlyInternalEnglishApostropheCandidate() {
        XCTAssertFalse(excluder.shouldExclude(
            "גםמ,א",
            conversion: .init(
                original: "גםמ,א",
                candidate: "don’t",
                source: .hebrew,
                target: .english
            )
        ))
    }

    func testShiftedJoinedWordRequiresCompletePhysicalTrace() {
        let token = "„םמ,א"
        let conversion = KeyboardLayoutMap().convert(
            token,
            sourceHint: .hebrew
        )

        XCTAssertEqual(conversion?.candidate, "Don't")
        XCTAssertNil(conversion?.physicalEvidence)
        XCTAssertTrue(excluder.shouldExclude(token, conversion: conversion))
    }

    func testExcludesMalformedEnglishApostropheCandidates() {
        for token in [",יקךךם", "יקךךם,", "כםם,,נשר", "יק׳ךם"] {
            XCTAssertTrue(shouldExclude(token), "Expected \(token) to be excluded")
        }
    }

    private func shouldExclude(_ token: String) -> Bool {
        excluder.shouldExclude(
            token,
            conversion: KeyboardLayoutMap().convert(token)
        )
    }
}
