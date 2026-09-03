import XCTest
@testable import AkuoMac

final class ShiftGestureRecognizerTests: XCTestCase {
    func testDoubleShiftTriggersAfterTwoCompleteSameSideTaps() {
        var recognizer = ShiftGestureRecognizer(activationInterval: 0.4)

        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 1.00,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .up,
            timestamp: 1.05,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 1.20,
            gesture: .doubleShift
        ))
        XCTAssertTrue(recognizer.consume(
            side: .left,
            phase: .up,
            timestamp: 1.25,
            gesture: .doubleShift
        ))
    }

    func testDoubleShiftRejectsOppositeSidesSlowTapsAndInterruptedSequences() {
        var recognizer = ShiftGestureRecognizer(activationInterval: 0.4)

        tap(.left, from: 1.00, using: &recognizer, gesture: .doubleShift)
        XCTAssertFalse(tap(.right, from: 1.20, using: &recognizer, gesture: .doubleShift))

        tap(.left, from: 2.00, using: &recognizer, gesture: .doubleShift)
        XCTAssertFalse(tap(.left, from: 2.60, using: &recognizer, gesture: .doubleShift))

        tap(.left, from: 3.00, using: &recognizer, gesture: .doubleShift)
        recognizer.reset()
        XCTAssertFalse(tap(.left, from: 3.20, using: &recognizer, gesture: .doubleShift))
    }

    func testBothShiftsTriggersOnlyForOverlappingOppositeKeysWithinInterval() {
        var recognizer = ShiftGestureRecognizer(activationInterval: 0.4)

        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 1.00,
            gesture: .bothShifts
        ))
        XCTAssertTrue(recognizer.consume(
            side: .right,
            phase: .down,
            timestamp: 1.20,
            gesture: .bothShifts
        ))
        XCTAssertFalse(recognizer.consume(
            side: .right,
            phase: .up,
            timestamp: 1.25,
            gesture: .bothShifts
        ))
        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .up,
            timestamp: 1.30,
            gesture: .bothShifts
        ))

        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 2.00,
            gesture: .bothShifts
        ))
        XCTAssertFalse(recognizer.consume(
            side: .right,
            phase: .down,
            timestamp: 2.50,
            gesture: .bothShifts
        ))
    }

    func testConfiguredGestureDoesNotCrossActivate() {
        var recognizer = ShiftGestureRecognizer(activationInterval: 0.4)

        tap(.left, from: 1.00, using: &recognizer, gesture: .bothShifts)
        XCTAssertFalse(tap(.left, from: 1.20, using: &recognizer, gesture: .bothShifts))

        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 2.00,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .right,
            phase: .down,
            timestamp: 2.10,
            gesture: .doubleShift
        ))
    }

    func testOverlappingOppositeKeysDoNotSeedADoubleShiftSequence() {
        var recognizer = ShiftGestureRecognizer(activationInterval: 0.4)

        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .down,
            timestamp: 1,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .right,
            phase: .down,
            timestamp: 1.1,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .left,
            phase: .up,
            timestamp: 1.15,
            gesture: .doubleShift
        ))
        XCTAssertFalse(recognizer.consume(
            side: .right,
            phase: .up,
            timestamp: 1.2,
            gesture: .doubleShift
        ))

        XCTAssertFalse(tap(
            .right,
            from: 1.3,
            using: &recognizer,
            gesture: .doubleShift
        ))
    }

    @discardableResult
    private func tap(
        _ side: ShiftKeySide,
        from timestamp: TimeInterval,
        using recognizer: inout ShiftGestureRecognizer,
        gesture: ForceConversionGesture
    ) -> Bool {
        XCTAssertFalse(recognizer.consume(
            side: side,
            phase: .down,
            timestamp: timestamp,
            gesture: gesture
        ))
        return recognizer.consume(
            side: side,
            phase: .up,
            timestamp: timestamp + 0.05,
            gesture: gesture
        )
    }
}
