import CoreGraphics
import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

@MainActor
final class LiveUndoIntegrationTests: XCTestCase {
    private let nativeEvent = CGEvent(
        keyboardEventSource: nil,
        virtualKey: 0,
        keyDown: true
    )!

    func testAkuoSourceChangeNotificationPreservesImmediateUndo() {
        let suiteName = "LiveUndoIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.isEnabled = true
        let backend = LiveUndoInputSourceBackend()
        let inputSources = InputSourceController(backend: backend)
        let replacer = LiveUndoTextReplacer()
        let scorer = WordScorer(recognizer: LiveUndoRecognizer())
        let coordinator = CorrectionCoordinator(
            policy: CorrectionPolicy(
                layoutMap: KeyboardLayoutMap(),
                originalScorer: scorer,
                candidateScorer: scorer,
                excluder: TokenExcluder()
            ),
            textReplacer: replacer,
            inputSourceSelector: inputSources,
            counter: preferences,
            clock: LiveUndoClock(),
            undoController: UndoController()
        )
        let decoder = LiveUndoEventDecoder()
        let focus = LiveUndoFocusProvider()
        let monitor = KeyboardEventMonitor(
            decoder: decoder,
            coordinator: coordinator,
            permission: LiveUndoPermission(),
            secureInput: LiveUndoSecureInput(),
            focusContextProvider: focus,
            inputSources: inputSources,
            tapManager: LiveUndoTapManager(),
            isAkuoEnabled: { true }
        )
        let lifecycle = SystemRuntimeLifecycleObserver()
        let model = AppModel(
            preferences: preferences,
            permission: LiveUndoPermission(),
            secureInput: LiveUndoSecureInput(),
            inputSources: inputSources,
            monitor: monitor,
            launchAtLoginController: LiveUndoLaunchAtLogin(),
            lifecycleObserver: lifecycle
        )
        defer { lifecycle.stop() }

        for character in "akuo" {
            decoder.event = .text(String(character), marker: 0)
            XCTAssertTrue(monitor.process(nativeEvent) === nativeEvent)
        }
        decoder.event = .text(" ", keyCode: 49, marker: 0)
        XCTAssertNil(monitor.process(nativeEvent))
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
        ])
        XCTAssertEqual(backend.selectedIdentifiers, ["com.apple.keylayout.Hebrew"])

        lifecycle.handleInputSourceChangeNotification()
        XCTAssertEqual(model.currentLanguage, .hebrew)

        decoder.event = .commandZ(marker: 0)
        XCTAssertNil(monitor.process(nativeEvent))
        XCTAssertEqual(replacer.calls, [
            .init(deleteCount: 4, replacement: "שלום", boundary: " "),
            .init(deleteCount: 5, replacement: "akuo", boundary: " "),
        ])
        XCTAssertEqual(backend.selectedIdentifiers, [
            "com.apple.keylayout.Hebrew",
            "com.apple.keylayout.ABC",
        ])
        XCTAssertEqual(inputSources.currentLanguage, .english)
    }
}

private struct LiveUndoReplacement: Equatable {
    let deleteCount: Int
    let replacement: String
    let boundary: String
}

private final class LiveUndoTextReplacer: TextReplacing {
    private(set) var calls: [LiveUndoReplacement] = []

    func replacePreviousText(
        deleteCount: Int,
        replacement: String,
        boundary: String,
        boundaryKeyCode: Int
    ) -> Bool {
        calls.append(.init(
            deleteCount: deleteCount,
            replacement: replacement,
            boundary: boundary
        ))
        return true
    }
}

private struct LiveUndoRecognizer: WordRecognizing {
    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        let isRecognized = switch language {
        case .english:
            word.lowercased() == "hello"
        case .hebrew:
            word == "שלום"
        }
        return isRecognized ? .recognized : .unknown
    }
}

private struct LiveUndoClock: RuntimeClock {
    let now = Date(timeIntervalSinceReferenceDate: 100)
}

private final class LiveUndoInputSourceBackend: InputSourceBackend {
    let sources: [InputSourceDescriptor] = [
        .init(identifier: "com.apple.keylayout.ABC"),
        .init(identifier: "com.apple.keylayout.Hebrew"),
    ]
    private(set) var currentIdentifier: String? = "com.apple.keylayout.ABC"
    private(set) var selectedIdentifiers: [String] = []

    func select(identifier: String) -> Bool {
        selectedIdentifiers.append(identifier)
        currentIdentifier = identifier
        return true
    }
}

private final class LiveUndoEventDecoder: NativeEventDecoding {
    var event: DecodedKeyboardEvent = .unhandled(marker: 0)

    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent {
        self.event
    }
}

private struct LiveUndoFocusProvider: FocusContextProviding {
    func current() -> FocusContext? {
        .init(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )
    }
}

private struct LiveUndoPermission: AccessibilityPermissionChecking {
    let isGranted = true

    func request() {}
}

private struct LiveUndoSecureInput: SecureInputChecking {
    let isSecureInputEnabled = false
}

private final class LiveUndoTapManager: NativeEventTapManaging {
    private(set) var isInstalled = false

    func install(
        userInfo: UnsafeMutableRawPointer,
        callback: CGEventTapCallBack
    ) -> Bool {
        isInstalled = true
        return true
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        isInstalled && enabled
    }

    func remove() {
        isInstalled = false
    }
}

private final class LiveUndoLaunchAtLogin: LaunchAtLoginControlling {
    let status: LaunchAtLoginStatus = .disabled

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        status
    }
}
