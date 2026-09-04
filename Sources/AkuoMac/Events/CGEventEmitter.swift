import CoreGraphics
import AkuoCore

protocol NativeEventPosting: AnyObject {
    func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool) -> CGEvent?
    func makeUnicodeEvent(_ text: String, keyDown: Bool) -> CGEvent?
    func makeBoundaryEvent(_ boundary: String, keyCode: CGKeyCode) -> CGEvent?
    func mark(_ event: CGEvent, with marker: Int64)
    func post(_ event: CGEvent)
}

private final class SystemNativeEventPoster: NativeEventPosting {
    func makeKeyEvent(keyCode: CGKeyCode, keyDown: Bool) -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
    }

    func makeUnicodeEvent(_ text: String, keyDown: Bool) -> CGEvent? {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: keyDown
        ) else {
            return nil
        }
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }

    func makeBoundaryEvent(_ boundary: String, keyCode: CGKeyCode) -> CGEvent? {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
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
        event.post(tap: .cghidEventTap)
    }
}

public final class CGEventEmitter: TextReplacing {
    private let posting: any NativeEventPosting

    public convenience init() {
        self.init(posting: SystemNativeEventPoster())
    }

    init(posting: any NativeEventPosting) {
        self.posting = posting
    }

    public func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: CorrectionBoundary?
    ) -> Bool {
        guard deleteCount >= 0 else {
            return false
        }
        let nativeBoundaryKeyCode: CGKeyCode?
        if let boundary {
            guard let keyCode = CGKeyCode(exactly: boundary.keyCode) else {
                return false
            }
            nativeBoundaryKeyCode = keyCode
        } else {
            nativeBoundaryKeyCode = nil
        }

        var events: [CGEvent] = []
        events.reserveCapacity((deleteCount * 2) + 2 + (boundary == nil ? 0 : 1))

        for _ in 0..<deleteCount {
            guard let keyDown = prepareKeyEvent(keyDown: true),
                  let keyUp = prepareKeyEvent(keyDown: false) else {
                return false
            }
            events.append(keyDown)
            events.append(keyUp)
        }

        guard let unicodeDown = prepareUnicodeEvent(replacement, keyDown: true),
              let unicodeUp = prepareUnicodeEvent(replacement, keyDown: false) else {
            return false
        }
        events.append(unicodeDown)
        events.append(unicodeUp)
        if let boundary, let nativeBoundaryKeyCode {
            guard let boundaryEvent = prepare(posting.makeBoundaryEvent(
                      boundary.text,
                      keyCode: nativeBoundaryKeyCode
                  )) else {
                return false
            }
            events.append(boundaryEvent)
        }

        for event in events {
            posting.post(event)
        }
        return true
    }

    private func prepareKeyEvent(keyDown: Bool) -> CGEvent? {
        prepare(posting.makeKeyEvent(keyCode: 51, keyDown: keyDown))
    }

    private func prepareUnicodeEvent(_ text: String, keyDown: Bool) -> CGEvent? {
        prepare(posting.makeUnicodeEvent(text, keyDown: keyDown))
    }

    private func prepare(_ event: CGEvent?) -> CGEvent? {
        guard let event else { return nil }
        event.flags = []
        posting.mark(event, with: KeyboardEventMonitor.syntheticMarker)
        return event
    }
}
