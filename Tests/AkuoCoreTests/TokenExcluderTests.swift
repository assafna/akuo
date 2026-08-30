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
            XCTAssertTrue(excluder.shouldExclude(token), "Expected \(token) to be excluded")
        }
    }

    func testExcludesUnknownSingleLetters() {
        XCTAssertTrue(excluder.shouldExclude("x"))
        XCTAssertTrue(excluder.shouldExclude("ת"))
    }

    func testExcludesSourceCodeCasingAndMappedPunctuationShapes() {
        for token in ["aKuo", "Akuo", "URLSession", "akuo.", "akuo[", "akuo]", "akuo,", "akuo;"] {
            XCTAssertTrue(excluder.shouldExclude(token), "Expected \(token) to be excluded")
        }
    }

    func testRejectsApostropheWithoutHebrewDirection() {
        XCTAssertTrue(excluder.shouldExclude("'abc"))
        XCTAssertTrue(excluder.shouldExclude("akuo'"))
    }

    func testAllowsLeadingLayoutPunctuationOnlyForHebrewTokenThatConvertsToEnglish() {
        XCTAssertFalse(excluder.shouldExclude("/וןבל"))
        XCTAssertFalse(excluder.shouldExclude("'וןבל"))
    }
}
