import XCTest
@testable import AkuoCore

final class KeyboardLayoutMapTests: XCTestCase {
    private let map = KeyboardLayoutMap()

    func testEnglishLayoutMistakeConvertsToHebrew() {
        XCTAssertEqual(map.convert("akuo"), .init(
            original: "akuo", candidate: "שלום",
            source: .english, target: .hebrew
        ))
    }

    func testHebrewLayoutMistakeConvertsToEnglish() {
        XCTAssertEqual(map.convert("יקךךם")?.candidate, "hello")
    }

    func testUppercaseEnglishIsNormalizedForLookup() {
        XCTAssertEqual(map.convert("AKUO")?.candidate, "שלום")
    }

    func testEveryLetterEntryRoundTrips() {
        for (english, hebrew) in KeyboardLayoutMap.englishToHebrew
            where KeyboardLayoutMap.hebrewLetters.contains(hebrew) &&
                  Set("abcdefghijklmnopqrstuvwxyz").contains(english) {
            XCTAssertEqual(map.convert(String(english))?.candidate, String(hebrew))
            XCTAssertEqual(map.convert(String(hebrew))?.candidate, String(english))
        }
    }

    func testHebrewOutputWithLeadingQKeyPunctuationConvertsToEnglish() {
        XCTAssertEqual(map.convert("/וןבל")?.candidate, "quick")
    }

    func testMixedScriptHasNoConversion() {
        XCTAssertNil(map.convert("abcשלום"))
    }

    func testEmptyTokenHasNoConversion() {
        XCTAssertNil(map.convert(""))
    }

    func testPunctuationOnlyTokenHasNoConversion() {
        XCTAssertNil(map.convert("/[];,'"))
    }

    func testUnsupportedCharacterHasNoConversion() {
        XCTAssertNil(map.convert("hello🙂"))
    }
}
