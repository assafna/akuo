import XCTest
import AkuoCore

final class CorrectionBoundaryTests: XCTestCase {
    func testAcceptsOnlySupportedMatchingBoundaryPairs() throws {
        let cases = [
            (text: " ", keyCode: 49),
            (text: "\r", keyCode: 36),
            (text: "\n", keyCode: 36),
            (text: "\u{3}", keyCode: 76),
        ]

        for expected in cases {
            let boundary = try XCTUnwrap(CorrectionBoundary(
                text: expected.text,
                keyCode: expected.keyCode
            ))

            XCTAssertEqual(boundary.text, expected.text)
            XCTAssertEqual(boundary.keyCode, expected.keyCode)
        }
    }

    func testRejectsEmptyTabPunctuationAndMismatchedPairs() {
        let cases = [
            (text: "", keyCode: 49),
            (text: "\t", keyCode: 48),
            (text: ".", keyCode: 47),
            (text: " ", keyCode: 36),
            (text: "\r", keyCode: 49),
            (text: "\n", keyCode: 76),
            (text: "\u{3}", keyCode: 36),
        ]

        for invalid in cases {
            XCTAssertNil(CorrectionBoundary(
                text: invalid.text,
                keyCode: invalid.keyCode
            ))
        }
    }
}
