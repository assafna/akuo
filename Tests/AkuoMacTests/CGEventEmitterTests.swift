import CoreGraphics
import XCTest
@testable import AkuoMac

final class CGEventEmitterTests: XCTestCase {
    func testReplacementPostsCompleteTaggedBatchInOrder() {
        let posting = FakeNativeEventPosting()
        let emitter = CGEventEmitter(posting: posting)

        XCTAssertTrue(emitter.replacePreviousText(
            deleteCount: 2,
            replacement: "שלום",
            boundary: " ",
            boundaryKeyCode: 49
        ))

        XCTAssertEqual(posting.requests, [
            .key(keyCode: 51, keyDown: true),
            .key(keyCode: 51, keyDown: false),
            .key(keyCode: 51, keyDown: true),
            .key(keyCode: 51, keyDown: false),
            .unicode(text: "שלום", keyDown: true),
            .unicode(text: "שלום", keyDown: false),
            .boundary(text: " ", keyCode: 49),
        ])
        XCTAssertEqual(posting.posted.count, 7)
        XCTAssertTrue(posting.posted.allSatisfy {
            $0.getIntegerValueField(.eventSourceUserData) == KeyboardEventMonitor.syntheticMarker
        })
    }

    func testConstructionFailurePostsNothing() {
        for failingRequestIndex in 0..<7 {
            let posting = FakeNativeEventPosting(
                failingRequestIndex: failingRequestIndex
            )
            let emitter = CGEventEmitter(posting: posting)

            XCTAssertFalse(emitter.replacePreviousText(
                deleteCount: 2,
                replacement: "שלום",
                boundary: " ",
                boundaryKeyCode: 49
            ))
            XCTAssertTrue(
                posting.posted.isEmpty,
                "Posted a partial batch when request \(failingRequestIndex) failed"
            )
        }
    }

    func testReplacementClearsUnsafeLiveModifiersFromEveryPostedEvent() {
        let unsafeLiveModifiers: CGEventFlags = [
            .maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn,
        ]
        let posting = FakeNativeEventPosting(initialFlags: unsafeLiveModifiers)
        let emitter = CGEventEmitter(posting: posting)

        XCTAssertTrue(emitter.replacePreviousText(
            deleteCount: 1,
            replacement: "akuo",
            boundary: " ",
            boundaryKeyCode: 49
        ))

        XCTAssertEqual(posting.postedFlags.count, 5)
        XCTAssertTrue(posting.postedFlags.allSatisfy(\.isEmpty))
        XCTAssertEqual(posting.postedFlags.last, [], "Boundary retained live modifiers")
    }

    func testNegativeDeleteCountFailsBeforeConstructingOrPosting() {
        let posting = FakeNativeEventPosting()
        let emitter = CGEventEmitter(posting: posting)

        XCTAssertFalse(emitter.replacePreviousText(
            deleteCount: -1,
            replacement: "שלום",
            boundary: " ",
            boundaryKeyCode: 49
        ))

        XCTAssertTrue(posting.requests.isEmpty)
        XCTAssertTrue(posting.posted.isEmpty)
    }

    func testInvalidBoundaryKeyCodeFailsBeforeConstructingOrPosting() {
        for keyCode in [-1, Int(UInt16.max) + 1] {
            let posting = FakeNativeEventPosting()
            let emitter = CGEventEmitter(posting: posting)

            XCTAssertFalse(emitter.replacePreviousText(
                deleteCount: 1,
                replacement: "שלום",
                boundary: "\r",
                boundaryKeyCode: keyCode
            ))
            XCTAssertTrue(posting.requests.isEmpty)
            XCTAssertTrue(posting.posted.isEmpty)
        }
    }

    func testReturnBoundaryPreservesPhysicalIdentityAndUnicodeWithoutSyntheticKeyUp() {
        let posting = FakeNativeEventPosting()
        let emitter = CGEventEmitter(posting: posting)

        XCTAssertTrue(emitter.replacePreviousText(
            deleteCount: 1,
            replacement: "שלום",
            boundary: "\r",
            boundaryKeyCode: 36
        ))

        XCTAssertEqual(posting.requests.last, .boundary(text: "\r", keyCode: 36))
        XCTAssertEqual(posting.requests.filter {
            if case .boundary = $0 { return true }
            return false
        }.count, 1)
        let boundary = try! XCTUnwrap(posting.posted.last)
        XCTAssertEqual(boundary.getIntegerValueField(.keyboardEventKeycode), 36)
        XCTAssertEqual(unicodeText(of: boundary), "\r")
        XCTAssertEqual(boundary.flags, [])
        XCTAssertEqual(
            boundary.getIntegerValueField(.eventSourceUserData),
            KeyboardEventMonitor.syntheticMarker
        )
    }

    private func unicodeText(of event: CGEvent) -> String {
        var count = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &count,
            unicodeString: nil
        )
        var characters = [UniChar](repeating: 0, count: count)
        characters.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &count,
                unicodeString: buffer.baseAddress
            )
        }
        return String(utf16CodeUnits: characters, count: count)
    }
}

private enum PostingRequest: Equatable {
    case key(keyCode: CGKeyCode, keyDown: Bool)
    case unicode(text: String, keyDown: Bool)
    case boundary(text: String, keyCode: CGKeyCode)
}

private final class FakeNativeEventPosting: NativeEventPosting {
    private let failingRequestIndex: Int?
    private let initialFlags: CGEventFlags
    private(set) var requests: [PostingRequest] = []
    private(set) var posted: [CGEvent] = []
    private(set) var postedFlags: [CGEventFlags] = []

    init(
        failingRequestIndex: Int? = nil,
        initialFlags: CGEventFlags = []
    ) {
        self.failingRequestIndex = failingRequestIndex
        self.initialFlags = initialFlags
    }

    func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        make(.key(keyCode: keyCode, keyDown: keyDown), keyCode: keyCode, keyDown: keyDown)
    }

    func makeUnicodeEvent(_ text: String, keyDown: Bool) -> CGEvent? {
        make(.unicode(text: text, keyDown: keyDown), keyCode: 0, keyDown: keyDown)
    }

    func makeBoundaryEvent(_ boundary: String, keyCode: CGKeyCode) -> CGEvent? {
        guard let event = make(
            .boundary(text: boundary, keyCode: keyCode),
            keyCode: keyCode,
            keyDown: true
        ) else {
            return nil
        }
        let characters = Array(boundary.utf16)
        characters.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }

    func mark(_ event: CGEvent, with marker: Int64) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    func post(_ event: CGEvent) {
        postedFlags.append(event.flags)
        posted.append(event)
    }

    private func make(
        _ request: PostingRequest,
        keyCode: CGKeyCode,
        keyDown: Bool
    ) -> CGEvent? {
        let requestIndex = requests.count
        requests.append(request)
        guard requestIndex != failingRequestIndex else { return nil }
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            return nil
        }
        event.flags = initialFlags
        return event
    }
}
