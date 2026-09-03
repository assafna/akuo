import Foundation
import XCTest
@testable import AkuoCore

final class UndoControllerTests: XCTestCase {
    private let createdAt = Date(timeIntervalSinceReferenceDate: 100)
    private let context = FocusContext(
        processIdentifier: 42,
        elementIdentifier: "field",
        isSecureField: false,
        isEditableTextInput: true
    )

    func testReturnsRecordAtFiveSecondEligibilityLimit() {
        let controller = UndoController()
        let record = makeRecord()
        controller.register(record)

        XCTAssertEqual(controller.eligibleRecord(context: context, now: createdAt.addingTimeInterval(5)), record)
    }

    func testRejectsAndInvalidatesRecordWhenElapsedIsNegative() {
        let controller = UndoController()
        controller.register(makeRecord())

        XCTAssertNil(controller.eligibleRecord(
            context: context,
            now: createdAt.addingTimeInterval(-0.001)
        ))
        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testRejectsRecordAfterFiveSecondEligibilityLimit() {
        let controller = UndoController()
        controller.register(makeRecord())

        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt.addingTimeInterval(5.001)))
    }

    func testRejectsRecordFromAnotherProcess() {
        let controller = UndoController()
        controller.register(makeRecord())

        XCTAssertNil(controller.eligibleRecord(
            context: .init(
                processIdentifier: 43,
                elementIdentifier: "field",
                isSecureField: false,
                isEditableTextInput: true
            ),
            now: createdAt
        ))
    }

    func testContextChangeInvalidatesRecordBeforeFocusReturns() {
        let controller = UndoController()
        controller.register(makeRecord())

        XCTAssertNil(controller.eligibleRecord(
            context: .init(
                processIdentifier: 43,
                elementIdentifier: "field",
                isSecureField: false,
                isEditableTextInput: true
            ),
            now: createdAt
        ))
        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testRejectsRecordWhenFocusedElementChanges() {
        let controller = UndoController()
        controller.register(makeRecord())

        XCTAssertNil(controller.eligibleRecord(
            context: .init(
                processIdentifier: 42,
                elementIdentifier: "other-field",
                isSecureField: false,
                isEditableTextInput: true
            ),
            now: createdAt
        ))
    }

    func testRejectsAndInvalidatesRecordForIneligibleControl() {
        let controller = UndoController()
        let ineligibleContext = FocusContext(
            processIdentifier: 42,
            elementIdentifier: "outline",
            isSecureField: false,
            isEditableTextInput: false
        )
        controller.register(UndoRecord(
            original: "akuo",
            corrected: "שלום",
            boundary: " ",
            boundaryKeyCode: 49,
            context: ineligibleContext,
            priorInputLanguage: .english,
            createdAt: createdAt
        ))

        XCTAssertNil(controller.eligibleRecord(context: ineligibleContext, now: createdAt))
        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testRejectsAndInvalidatesRecordForMissingElementIdentifier() {
        let controller = UndoController()
        let uncertainContext = FocusContext(
            processIdentifier: 42,
            elementIdentifier: nil,
            isSecureField: false
        )
        controller.register(UndoRecord(
            original: "akuo",
            corrected: "שלום",
            boundary: " ",
            boundaryKeyCode: 49,
            context: uncertainContext,
            priorInputLanguage: .english,
            createdAt: createdAt
        ))

        XCTAssertNil(controller.eligibleRecord(context: uncertainContext, now: createdAt))
        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testRejectsAndInvalidatesRecordForSecureContext() {
        let controller = UndoController()
        let secureContext = FocusContext(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: true
        )
        controller.register(UndoRecord(
            original: "akuo",
            corrected: "שלום",
            boundary: " ",
            boundaryKeyCode: 49,
            context: secureContext,
            priorInputLanguage: .english,
            createdAt: createdAt
        ))

        XCTAssertNil(controller.eligibleRecord(context: secureContext, now: createdAt))
        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testOrdinaryInputInvalidatesRecord() {
        let controller = UndoController()
        controller.register(makeRecord())
        controller.invalidate()

        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    func testSecondCorrectionReplacesPriorRecord() {
        let controller = UndoController()
        controller.register(makeRecord(original: "akuo", corrected: "שלום"))
        let second = makeRecord(original: "ikll", corrected: "hello")
        controller.register(second)

        XCTAssertEqual(controller.eligibleRecord(context: context, now: createdAt), second)
    }

    func testFocusResetInvalidatesRecord() {
        let controller = UndoController()
        controller.register(makeRecord())
        controller.invalidate()

        XCTAssertNil(controller.eligibleRecord(context: context, now: createdAt))
    }

    private func makeRecord(
        original: String = "akuo",
        corrected: String = "שלום"
    ) -> UndoRecord {
        UndoRecord(
            original: original,
            corrected: corrected,
            boundary: " ",
            boundaryKeyCode: 49,
            context: context,
            priorInputLanguage: .english,
            createdAt: createdAt
        )
    }
}
