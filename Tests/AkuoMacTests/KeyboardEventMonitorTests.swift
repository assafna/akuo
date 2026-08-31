import CoreGraphics
import XCTest
import AkuoCore
@testable import AkuoMac

final class KeyboardEventMonitorTests: XCTestCase {
    private let fakeNativeEvent = CGEvent(
        keyboardEventSource: nil,
        virtualKey: 0,
        keyDown: true
    )!

    func testSyntheticEventNeverEntersWordBuffer() {
        let fixture = makeFixture()
        fixture.decoder.event = .text("a", marker: KeyboardEventMonitor.syntheticMarker)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertEqual(fixture.coordinator.noteOrdinaryInputCalls, 0)
    }

    func testTaggedNativeReplacementSkipsPayloadDecoder() {
        let fixture = makeFixture()
        let event = nativeUnicodeEvent("שלום")
        event.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardEventMonitor.syntheticMarker
        )
        fixture.decoder.event = .text("must-not-decode", marker: 0)

        XCTAssertNotNil(fixture.monitor.process(event))

        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
    }

    func testProductionDecoderDynamicallyReadsMoreThanThirtyTwoUTF16Units() {
        let text = String(repeating: "a", count: 40)
        let event = nativeUnicodeEvent(text)

        XCTAssertEqual(
            SystemNativeEventDecoder().decode(event, type: .keyDown),
            .text(text, keyCode: 0, marker: 0)
        )
    }

    func testProductionDecoderReadsMarkerFromTaggedReplacementEvent() {
        let event = nativeUnicodeEvent("שלום")
        event.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardEventMonitor.syntheticMarker
        )

        XCTAssertEqual(
            SystemNativeEventDecoder().decode(event, type: .keyDown),
            .text(
                "שלום",
                keyCode: 0,
                marker: KeyboardEventMonitor.syntheticMarker
            )
        )
    }

    func testProductionDecoderClassifiesEverySilentShiftedAlphabeticKey() {
        let alphabeticKeyCodes: [CGKeyCode] = [
            0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
            45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
        ]

        for keyCode in alphabeticKeyCodes {
            XCTAssertEqual(
                SystemNativeEventDecoder.decodeEmptyUnicodeKey(
                    keyCode: keyCode,
                    flags: [.maskShift],
                    marker: 0
                ),
                .text("", keyCode: keyCode, marker: 0),
                "keyCode \(keyCode)"
            )
        }
    }

    func testProductionDecoderRejectsOtherEmptyUnicodeKeys() {
        for (keyCode, flags) in [
            (CGKeyCode(4), CGEventFlags()),
            (CGKeyCode(122), CGEventFlags.maskShift),
        ] {
            XCTAssertEqual(
                SystemNativeEventDecoder.decodeEmptyUnicodeKey(
                    keyCode: keyCode,
                    flags: flags,
                    marker: 0
                ),
                .unhandled(marker: 0)
            )
        }
    }

    func testProductionEventTapMaskIncludesKeyboardAndEveryMouseDown() {
        for eventType in [
            CGEventType.keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ] {
            let bit = CGEventMask(1) << eventType.rawValue
            XCTAssertNotEqual(
                KeyboardEventMonitor.productionEventMask & bit,
                0,
                "Missing event type \(eventType.rawValue)"
            )
        }
    }

    func testSecureInputClearsTransientStateAndPassesThrough() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.decoder.event = .text("b", marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertEqual(fixture.coordinator.noteOrdinaryInputCalls, 2)
    }

    func testSecureFocusedFieldClearsTransientStateAndPassesThrough() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.focus.context = .init(
            processIdentifier: 42,
            elementIdentifier: "password",
            isSecureField: true,
            isEditableTextInput: false
        )
        fixture.decoder.event = .text("b", marker: 0)
        fixture.decoder.resetDecodeCalls()

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertEqual(fixture.coordinator.noteOrdinaryInputCalls, 2)
        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
    }

    func testUnknownFocusClearsTransientStateAndFailsOpen() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.focus.context = nil
        fixture.decoder.event = .text("b", marker: 0)
        fixture.decoder.resetDecodeCalls()

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertTrue(fixture.coordinator.boundaryCalls.isEmpty)
        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
    }

    func testMissingFocusedElementIdentityClearsTransientStateAndFailsOpen() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.focus.context = .init(
            processIdentifier: 42,
            elementIdentifier: nil,
            isSecureField: false,
            isEditableTextInput: false
        )
        fixture.decoder.event = .text("b", marker: 0)
        fixture.decoder.resetDecodeCalls()

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertTrue(fixture.coordinator.boundaryCalls.isEmpty)
        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
    }

    func testIneligibleFocusedControlClearsTransientStateWithoutDecoding() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.focus.context = .init(
            processIdentifier: 42,
            elementIdentifier: "outline",
            isSecureField: false,
            isEditableTextInput: false
        )
        fixture.decoder.event = .text("private", marker: 0)
        fixture.decoder.resetDecodeCalls()

        XCTAssertTrue(fixture.monitor.process(fakeNativeEvent) === fakeNativeEvent)

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertTrue(fixture.coordinator.boundaryCalls.isEmpty)
        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
    }

    func testSecureInputStopsActiveTapBeforePayloadDecodingUntilExplicitRefresh() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.monitor.start())
        fixture.secureInput.isSecureInputEnabled = true
        fixture.decoder.event = .text("private", marker: 0)
        let enableCallsBeforeSecureEvent = fixture.tapManager.enableCalls

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.decoder.decodeCalls, 0)
        XCTAssertEqual(fixture.tapManager.removeCalls, 1)
        XCTAssertEqual(fixture.tapManager.enableCalls, enableCallsBeforeSecureEvent)
        XCTAssertEqual(fixture.monitor.state, .stopped)

        fixture.secureInput.isSecureInputEnabled = false
        XCTAssertEqual(fixture.tapManager.installCalls, 1)
        XCTAssertEqual(fixture.tapManager.enableCalls, enableCallsBeforeSecureEvent)

        fixture.monitor.refreshState()

        XCTAssertEqual(fixture.tapManager.installCalls, 2)
        XCTAssertEqual(fixture.tapManager.enableCalls, enableCallsBeforeSecureEvent + [true])
        XCTAssertEqual(fixture.monitor.state, .active)
    }

    func testOrdinaryCharactersFillBufferAndDeleteEditsToken() {
        let fixture = makeFixture()

        type("a", in: fixture)
        type("b", in: fixture)
        fixture.decoder.event = .deleteBackward(marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "a")
    }

    func testNavigationClearsToken() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.decoder.event = .navigation(marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
    }

    func testEveryMouseDownTypeInvalidatesWithoutFocusOrPayloadInspection() {
        for eventType in [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ] {
            let fixture = makeFixture()
            type("a", in: fixture)
            fixture.decoder.event = .text("private", marker: 0)
            fixture.decoder.resetDecodeCalls()
            fixture.focus.resetCurrentCalls()

            XCTAssertTrue(
                fixture.monitor.process(fakeNativeEvent, type: eventType) === fakeNativeEvent,
                "Failed for event type \(eventType.rawValue)"
            )

            XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
            XCTAssertEqual(fixture.decoder.decodeCalls, 0)
            XCTAssertEqual(fixture.focus.currentCalls, 0)
        }
    }

    func testMouseDownPreventsPartialTokenCorrectionInSameEditor() {
        let fixture = makeFixture()
        type("a", in: fixture)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent, type: .leftMouseDown))

        fixture.decoder.event = .text(" ", marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertTrue(fixture.coordinator.boundaryCalls.isEmpty)
    }

    func testMouseDownDisarmsImmediateUndoInSameEditor() {
        let fixture = makeFixture()
        fixture.coordinator.armUndoOnHandledBoundary = true
        fixture.coordinator.boundaryResult = .handled
        type("a", in: fixture)
        fixture.decoder.event = .text(" ", keyCode: 49, marker: 0)
        XCTAssertNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent, type: .leftMouseDown))

        fixture.decoder.event = .commandZ(marker: 0)
        XCTAssertTrue(fixture.monitor.process(fakeNativeEvent) === fakeNativeEvent)
    }

    func testFrontmostApplicationChangeStartsFreshToken() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.focus.context = .init(
            processIdentifier: 99,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )

        type("b", in: fixture)

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "b")
    }

    func testUnsupportedModifiersClearTokenAndPassThrough() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.decoder.event = .unsupportedModifiers(marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
    }

    func testHebrewQKeyPunctuationRemainsInCompletedToken() {
        let fixture = makeFixture(language: .hebrew)
        fixture.decoder.event = .text("/", keyCode: 12, marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        for character in "וןבל" {
            type(String(character), in: fixture)
        }
        fixture.decoder.event = .text(" ", marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.coordinator.boundaryCalls, [
            .init(
                completedWord: .init(
                    token: "/וןבל",
                    boundary: " ",
                    keyStrokes: [.init(text: "/", keyCode: 12)]
                ),
                boundaryKeyCode: nil,
                context: fixture.focus.context!,
                priorInputLanguage: .hebrew
            )
        ])
    }

    func testHebrewWKeyApostropheRemainsInCompletedToken() {
        let fixture = makeFixture(language: .hebrew)
        fixture.decoder.event = .text("'", keyCode: 13, marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        type("ן", in: fixture)
        fixture.decoder.event = .text(" ", marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(
            fixture.coordinator.boundaryCalls.first?.completedWord,
            .init(
                token: "'ן",
                boundary: " ",
                keyStrokes: [.init(text: "'", keyCode: 13)]
            )
        )
    }

    func testPrintablePunctuationRemainsInTokenUntilWhitespace() {
        let fixture = makeFixture()
        for character in "https://akuo.app" {
            type(String(character), in: fixture)
        }
        fixture.decoder.event = .text(" ", marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.coordinator.boundaryCalls.first?.completedWord, .init(
            token: "https://akuo.app",
            boundary: " "
        ))
    }

    func testReturnBoundaryKeyCodeReachesCoordinator() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.decoder.event = .text("\r", keyCode: 36, marker: 0)

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.coordinator.boundaryCalls.first?.boundaryKeyCode, 36)
        XCTAssertEqual(fixture.coordinator.boundaryCalls.first?.completedWord.boundary, "\r")
    }

    func testKeepBoundaryReturnsOriginalEvent() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.coordinator.boundaryResult = .notHandled
        fixture.decoder.event = .text(" ", marker: 0)

        let returned = fixture.monitor.process(fakeNativeEvent)

        XCTAssertTrue(returned === fakeNativeEvent)
        XCTAssertEqual(fixture.coordinator.boundaryCalls.first?.priorInputLanguage, .english)
    }

    func testSuccessfulCorrectionSuppressesOnlyOriginalBoundary() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.coordinator.boundaryResult = .handled
        fixture.decoder.event = .text(" ", keyCode: 49, marker: 0)

        XCTAssertNil(fixture.monitor.process(fakeNativeEvent))

        fixture.decoder.event = .text("b", marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "b")
        XCTAssertTrue(fixture.delegate.selectionFailures.isEmpty)
    }

    func testCorrectionSelectionFailureIsSignaledAfterSuppressingBoundary() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.coordinator.boundaryResult = .handledWithInputSourceSelectionFailure(
            expectedLanguage: .hebrew
        )
        fixture.decoder.event = .text(" ", keyCode: 49, marker: 0)

        XCTAssertNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.delegate.selectionFailures, [
            .init(operation: .correction, expectedLanguage: .hebrew),
        ])
    }

    func testReplacementFailureReturnsOriginalBoundary() {
        let fixture = makeFixture()
        type("a", in: fixture)
        fixture.coordinator.boundaryResult = .notHandled
        fixture.decoder.event = .text(" ", keyCode: 49, marker: 0)

        XCTAssertTrue(fixture.monitor.process(fakeNativeEvent) === fakeNativeEvent)
        XCTAssertEqual(fixture.coordinator.boundaryCalls.count, 1)
    }

    func testImmediateCommandZIsSuppressedOnlyWhenUndoSucceeds() {
        let fixture = makeFixture()
        fixture.decoder.event = .commandZ(marker: 0)
        fixture.coordinator.undoResult = .handled

        XCTAssertNil(fixture.monitor.process(fakeNativeEvent))

        fixture.coordinator.undoResult = .notHandled
        XCTAssertTrue(fixture.monitor.process(fakeNativeEvent) === fakeNativeEvent)
        XCTAssertEqual(fixture.coordinator.undoContexts, [fixture.focus.context!, fixture.focus.context!])
        XCTAssertTrue(fixture.delegate.selectionFailures.isEmpty)
    }

    func testUndoSelectionFailureIsSignaledAfterSuppressingCommandZ() {
        let fixture = makeFixture()
        fixture.decoder.event = .commandZ(marker: 0)
        fixture.coordinator.undoResult = .handledWithInputSourceSelectionFailure(
            expectedLanguage: .english
        )

        XCTAssertNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.delegate.selectionFailures, [
            .init(operation: .immediateUndo, expectedLanguage: .english),
        ])
    }

    func testTapTimeoutClearsStateAndReenablesExistingTapOnce() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.monitor.start())
        fixture.tapManager.enableCalls.removeAll()
        type("a", in: fixture)
        fixture.decoder.event = .tapDisabledByTimeout

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertEqual(fixture.tapManager.installCalls, 1)
        XCTAssertEqual(fixture.tapManager.enableCalls, [true])
        XCTAssertEqual(fixture.delegate.states.last, .active)
    }

    func testUserDisableReportsDegradedWhenSingleReenableFails() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.monitor.start())
        fixture.tapManager.enableCalls.removeAll()
        fixture.tapManager.enableResults = [false]
        type("a", in: fixture)
        fixture.decoder.event = .tapDisabledByUserInput

        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))

        XCTAssertEqual(fixture.monitor.currentTokenForTesting, "")
        XCTAssertEqual(fixture.tapManager.enableCalls, [true])
        XCTAssertEqual(fixture.delegate.states.last, .degraded)
    }

    func testStartRequiresEnablementPermissionSourcesAndNonSecureInput() {
        let disabled = makeFixture(isAkuoEnabled: false)
        XCTAssertFalse(disabled.monitor.start())
        XCTAssertEqual(disabled.tapManager.installCalls, 0)

        let denied = makeFixture(permissionGranted: false)
        XCTAssertFalse(denied.monitor.start())
        XCTAssertEqual(denied.tapManager.installCalls, 0)

        let missingSource = makeFixture(readiness: .init(
            englishAvailable: true,
            hebrewAvailable: false
        ))
        XCTAssertFalse(missingSource.monitor.start())
        XCTAssertEqual(missingSource.tapManager.installCalls, 0)

        let secure = makeFixture(secureInputEnabled: true)
        XCTAssertFalse(secure.monitor.start())
        XCTAssertEqual(secure.tapManager.installCalls, 0)
    }

    private func makeFixture(
        language: Language = .english,
        isAkuoEnabled: Bool = true,
        permissionGranted: Bool = true,
        secureInputEnabled: Bool = false,
        readiness: InputSourceReadiness = .init(
            englishAvailable: true,
            hebrewAvailable: true
        )
    ) -> MonitorFixture {
        let decoder = FakeNativeEventDecoder()
        let coordinator = FakeCorrectionCoordinator()
        let permission = FakePermissionChecker(isGranted: permissionGranted)
        let secureInput = FakeSecureInputChecker(isSecureInputEnabled: secureInputEnabled)
        let focus = FakeFocusContextProvider(context: .init(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        ))
        let inputSources = FakeInputSourceState(readiness: readiness, currentLanguage: language)
        let tapManager = FakeNativeEventTapManager()
        let delegate = FakeMonitorDelegate()
        let monitor = KeyboardEventMonitor(
            decoder: decoder,
            coordinator: coordinator,
            permission: permission,
            secureInput: secureInput,
            focusContextProvider: focus,
            inputSources: inputSources,
            tapManager: tapManager,
            isAkuoEnabled: { isAkuoEnabled }
        )
        monitor.delegate = delegate
        return MonitorFixture(
            monitor: monitor,
            decoder: decoder,
            coordinator: coordinator,
            secureInput: secureInput,
            focus: focus,
            tapManager: tapManager,
            delegate: delegate
        )
    }

    private func type(_ text: String, in fixture: MonitorFixture) {
        fixture.decoder.event = .text(text, marker: 0)
        XCTAssertNotNil(fixture.monitor.process(fakeNativeEvent))
    }

    private func nativeUnicodeEvent(_ text: String) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }
}

private struct MonitorFixture {
    let monitor: KeyboardEventMonitor
    let decoder: FakeNativeEventDecoder
    let coordinator: FakeCorrectionCoordinator
    let secureInput: FakeSecureInputChecker
    let focus: FakeFocusContextProvider
    let tapManager: FakeNativeEventTapManager
    let delegate: FakeMonitorDelegate
}

private final class FakeNativeEventDecoder: NativeEventDecoding {
    var event: DecodedKeyboardEvent = .unhandled(marker: 0)
    private(set) var decodeCalls = 0

    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent {
        decodeCalls += 1
        return self.event
    }

    func resetDecodeCalls() {
        decodeCalls = 0
    }
}

private struct BoundaryCall: Equatable {
    let completedWord: CompletedWord
    let boundaryKeyCode: Int?
    let context: FocusContext
    let priorInputLanguage: Language
}

private final class FakeCorrectionCoordinator: CorrectionCoordinating {
    var boundaryResult: CorrectionHandlingResult = .notHandled
    var undoResult: CorrectionHandlingResult = .notHandled
    var armUndoOnHandledBoundary = false
    private(set) var boundaryCalls: [BoundaryCall] = []
    private(set) var undoContexts: [FocusContext] = []
    private(set) var noteOrdinaryInputCalls = 0
    private var isUndoArmed = false

    func handleBoundary(
        _ completedWord: CompletedWord,
        boundaryKeyCode: Int?,
        context: FocusContext,
        priorInputLanguage: Language
    ) -> CorrectionHandlingResult {
        boundaryCalls.append(.init(
            completedWord: completedWord,
            boundaryKeyCode: boundaryKeyCode,
            context: context,
            priorInputLanguage: priorInputLanguage
        ))
        if boundaryResult != .notHandled, armUndoOnHandledBoundary {
            isUndoArmed = true
        }
        return boundaryResult
    }

    func handleImmediateUndo(context: FocusContext) -> CorrectionHandlingResult {
        undoContexts.append(context)
        let result = undoResult != .notHandled
            ? undoResult
            : (isUndoArmed ? .handled : .notHandled)
        isUndoArmed = false
        return result
    }

    func noteOrdinaryInput() {
        noteOrdinaryInputCalls += 1
        isUndoArmed = false
    }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    func request() {}
}

private final class FakeSecureInputChecker: SecureInputChecking {
    var isSecureInputEnabled: Bool

    init(isSecureInputEnabled: Bool) {
        self.isSecureInputEnabled = isSecureInputEnabled
    }
}

private final class FakeFocusContextProvider: FocusContextProviding {
    var context: FocusContext?
    private(set) var currentCalls = 0

    init(context: FocusContext?) {
        self.context = context
    }

    func current() -> FocusContext? {
        currentCalls += 1
        return context
    }

    func resetCurrentCalls() {
        currentCalls = 0
    }
}

private final class FakeInputSourceState: InputSourceStateProviding {
    var readiness: InputSourceReadiness
    var currentLanguage: Language?

    init(readiness: InputSourceReadiness, currentLanguage: Language?) {
        self.readiness = readiness
        self.currentLanguage = currentLanguage
    }
}

private final class FakeNativeEventTapManager: NativeEventTapManaging {
    var installResult = true
    var enableResults: [Bool] = []
    private(set) var isInstalled = false
    private(set) var installCalls = 0
    var enableCalls: [Bool] = []
    private(set) var removeCalls = 0

    func install(
        userInfo: UnsafeMutableRawPointer,
        callback: CGEventTapCallBack
    ) -> Bool {
        installCalls += 1
        isInstalled = installResult
        return installResult
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        enableCalls.append(enabled)
        return enableResults.isEmpty ? true : enableResults.removeFirst()
    }

    func remove() {
        removeCalls += 1
        isInstalled = false
    }
}

private final class FakeMonitorDelegate: KeyboardEventMonitorDelegate {
    private(set) var states: [KeyboardEventMonitor.State] = []
    private(set) var selectionFailures: [InputSourceSelectionFailure] = []

    func didChangeMonitorState(_ state: KeyboardEventMonitor.State) {
        states.append(state)
    }

    func didFailInputSourceSelection(_ failure: InputSourceSelectionFailure) {
        selectionFailures.append(failure)
    }
}
