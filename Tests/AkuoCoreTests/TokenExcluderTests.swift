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
    }

    private func shouldExclude(_ token: String) -> Bool {
        excluder.shouldExclude(
            token,
            conversion: KeyboardLayoutMap().convert(token)
        )
    }
}
