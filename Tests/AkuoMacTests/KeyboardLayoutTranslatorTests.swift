import Carbon
import XCTest
import AkuoCore
@testable import AkuoMac

final class KeyboardLayoutTranslatorTests: XCTestCase {
    private let abcIdentifier = "com.apple.keylayout.ABC"
    private let hebrewIdentifier = "com.apple.keylayout.Hebrew"

    func testInstalledAppleLayoutsTranslateLettersAndShiftedPunctuation() throws {
        try XCTSkipUnless(
            requiredEnabledLayoutsAreAvailable(),
            "Requires enabled ABC and Hebrew input sources in the current macOS session."
        )
        let translator = AppleKeyboardLayoutTextTranslator()

        XCTAssertEqual(
            translator.characters(
                keyCode: 13,
                modifiers: [],
                inputSourceIdentifier: hebrewIdentifier
            ),
            "׳"
        )
        XCTAssertEqual(
            translator.characters(
                keyCode: 13,
                modifiers: [],
                inputSourceIdentifier: abcIdentifier
            ),
            "w"
        )
        for (keyCode, expected) in [(18, "!"), (44, "?")] {
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: hebrewIdentifier
                ),
                expected
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: abcIdentifier
                ),
                expected
            )
        }
    }

    func testInstalledABCLayoutTranslatesShiftAndCapsLockLettersAsUppercase() throws {
        try XCTSkipUnless(
            requiredEnabledLayoutsAreAvailable(),
            "Requires enabled ABC and Hebrew input sources in the current macOS session."
        )
        let translator = AppleKeyboardLayoutTextTranslator()

        for (keyCode, expected) in [(4, "H"), (8, "C")] {
            XCTAssertEqual(
                translator.characters(
                    keyCode: keyCode,
                    modifiers: [.shift, .capsLock],
                    inputSourceIdentifier: abcIdentifier
                ),
                expected,
                "ABC key code \(keyCode)"
            )
        }
    }

    func testInstalledAppleLayoutsTranslateEveryPrintablePunctuationKey() throws {
        try XCTSkipUnless(
            requiredEnabledLayoutsAreAvailable(),
            "Requires enabled ABC and Hebrew input sources in the current macOS session."
        )
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
                    inputSourceIdentifier: abcIdentifier
                ),
                row.english,
                "ABC key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: abcIdentifier
                ),
                row.shiftedEnglish,
                "Shift+ABC key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [],
                    inputSourceIdentifier: hebrewIdentifier
                ),
                row.hebrew,
                "Hebrew key code \(row.keyCode)"
            )
            XCTAssertEqual(
                translator.characters(
                    keyCode: row.keyCode,
                    modifiers: [.shift],
                    inputSourceIdentifier: hebrewIdentifier
                ),
                row.shiftedHebrew,
                "Shift+Hebrew key code \(row.keyCode)"
            )
        }
    }

    private func requiredEnabledLayoutsAreAvailable() -> Bool {
        let abcIsAvailable = enabledInputSourceExists(identifier: abcIdentifier)
        let hebrewIsAvailable = enabledInputSourceExists(identifier: hebrewIdentifier)

        return abcIsAvailable && hebrewIsAvailable
    }

    private func enabledInputSourceExists(identifier: String) -> Bool {
        let condition = [
            kTISPropertyInputSourceID as String: identifier,
        ] as CFDictionary
        guard let inputSources = TISCreateInputSourceList(
            condition,
            false
        )?.takeRetainedValue() else { return false }

        return CFArrayGetCount(inputSources) > 0
    }
}
