import XCTest
import AkuoCore
@testable import AkuoMac

final class KeyboardLayoutTranslatorTests: XCTestCase {
    func testInstalledAppleLayoutsTranslateLettersAndShiftedPunctuation() {
        let translator = AppleKeyboardLayoutTextTranslator()

        XCTAssertEqual(
            translator.characters(
                keyCode: 13,
                modifiers: [],
                inputSourceIdentifier: "com.apple.keylayout.Hebrew"
            ),
            "׳"
        )
        XCTAssertEqual(
            translator.characters(
                keyCode: 13,
                modifiers: [],
                inputSourceIdentifier: "com.apple.keylayout.ABC"
            ),
            "w"
        )
        for (keyCode, expected) in [(18, "!"), (44, "?")] {
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: "com.apple.keylayout.Hebrew"
                ),
                expected
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: "com.apple.keylayout.ABC"
                ),
                expected
            )
        }
    }

    func testInstalledABCLayoutTranslatesShiftAndCapsLockLettersAsUppercase() {
        let translator = AppleKeyboardLayoutTextTranslator()

        for (keyCode, expected) in [(4, "H"), (8, "C")] {
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift, .capsLock],
                    inputSourceIdentifier: "com.apple.keylayout.ABC"
                ),
                expected,
                "ABC key code \(keyCode)"
            )
        }
    }

    func testInstalledAppleLayoutsTranslateEveryPrintablePunctuationKey() {
        let translator = AppleKeyboardLayoutTextTranslator()
        let rows: [(
            keyCode: Int,
            english: String,
            shiftedEnglish: String,
            hebrew: String,
            shiftedHebrew: String
        )] = [
            (18, "1", "!", "1", "!"),
            (19, "2", "@", "2", "@"),
            (20, "3", "#", "3", "#"),
            (21, "4", "$", "4", "$"),
            (23, "5", "%", "5", "%"),
            (22, "6", "^", "6", "^"),
            (26, "7", "&", "7", "₪"),
            (28, "8", "*", "8", "*"),
            (25, "9", "(", "9", ")"),
            (29, "0", ")", "0", "("),
            (27, "-", "_", "-", "_"),
            (24, "=", "+", "=", "+"),
            (33, "[", "{", "]", "}"),
            (30, "]", "}", "[", "{"),
            (42, "\\", "|", "ֿ", "|"),
            (41, ";", ":", "ף", ":"),
            (39, "'", "\"", ",", "״"),
            (43, ",", "<", "ת", ">"),
            (47, ".", ">", "ץ", "<"),
            (44, "/", "?", ".", "?"),
            (50, "`", "~", ";", "~"),
        ]

        for row in rows {
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [],
                    inputSourceIdentifier: "com.apple.keylayout.ABC"
                ),
                row.english,
                "ABC key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: "com.apple.keylayout.ABC"
                ),
                row.shiftedEnglish,
                "Shift+ABC key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [],
                    inputSourceIdentifier: "com.apple.keylayout.Hebrew"
                ),
                row.hebrew,
                "Hebrew key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: "com.apple.keylayout.Hebrew"
                ),
                row.shiftedHebrew,
                "Shift+Hebrew key code \(row.keyCode)"
            )
        }
    }
}
