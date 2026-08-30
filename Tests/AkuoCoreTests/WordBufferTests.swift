import XCTest
@testable import AkuoCore

final class WordBufferTests: XCTestCase {
    func testBoundaryCompletesOnlyCurrentWord() {
        var buffer = WordBuffer()
        XCTAssertEqual(buffer.consume(.text("a")), .accumulating)
        XCTAssertEqual(buffer.consume(.text("k")), .accumulating)
        XCTAssertEqual(buffer.consume(.text("u")), .accumulating)
        XCTAssertEqual(buffer.consume(.text("o")), .accumulating)
        XCTAssertEqual(buffer.consume(.boundary(" ")), .completed(.init(token: "akuo", boundary: " ")))
        XCTAssertEqual(buffer.currentToken, "")
    }

    func testDeleteRemovesOneGrapheme() {
        var buffer = WordBuffer()
        for character in "שלום" { _ = buffer.consume(.text(String(character))) }
        XCTAssertEqual(buffer.consume(.deleteBackward), .accumulating)
        XCTAssertEqual(buffer.currentToken, "שלו")
    }

    func testDeleteDiscardsSilentAndCompositeShiftedKeyTraces() {
        let cases: [([ObservedKeyStroke], String)] = [
            ([
                .init(text: "", keyCode: 4),
                .init(text: "ק", keyCode: 14),
                .init(text: "ך", keyCode: 37),
            ], "ק"),
            ([
                .init(text: "לֹ", keyCode: 8),
                .init(text: "ם", keyCode: 31),
            ], "לֹ"),
        ]

        for (keyStrokes, remainingToken) in cases {
            var buffer = WordBuffer()
            for keyStroke in keyStrokes {
                _ = buffer.consume(.observedKeyStroke(keyStroke))
            }

            XCTAssertEqual(buffer.consume(.deleteBackward), .accumulating)
            XCTAssertEqual(
                buffer.consume(.boundary(" ")),
                .completed(.init(
                    token: remainingToken,
                    boundary: " ",
                    keyStrokes: []
                ))
            )
        }
    }

    func testBoundaryWithEmptyBufferPassesThrough() {
        var buffer = WordBuffer()
        XCTAssertEqual(buffer.consume(.boundary(" ")), .passThrough)
    }

    func testShortcutNavigationAndResetClearState() {
        for clearingInput in [BufferedInput.shortcut, .navigation, .reset] {
            var buffer = WordBuffer()
            _ = buffer.consume(.text("a"))
            XCTAssertEqual(buffer.consume(clearingInput), .reset)
            XCTAssertEqual(buffer.currentToken, "")
        }
    }

    func testReturnAndPunctuationAreBoundaries() {
        for boundary in ["\n", ".", ",", "!", "?", ":", ";"] {
            var buffer = WordBuffer()
            _ = buffer.consume(.text("a"))
            XCTAssertEqual(buffer.consume(.boundary(boundary)),
                           .completed(.init(token: "a", boundary: boundary)))
        }
    }
}
