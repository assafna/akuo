import AppKit
import CoreFoundation
import CoreGraphics
import Foundation
import AkuoCore

enum DecodedKeyboardEvent: Equatable {
    case text(String, keyCode: CGKeyCode? = nil, marker: Int64)
    case shiftChanged(
        side: ShiftKeySide,
        phase: ShiftKeyPhase,
        timestamp: TimeInterval,
        marker: Int64
    )
    case deleteBackward(marker: Int64)
    case navigation(marker: Int64)
    case commandZ(marker: Int64)
    case unsupportedModifiers(marker: Int64)
    case unhandled(marker: Int64)
    case tapDisabledByTimeout
    case tapDisabledByUserInput

    var marker: Int64? {
        switch self {
        case let .text(_, _, marker),
             let .shiftChanged(_, _, _, marker),
             let .deleteBackward(marker),
             let .navigation(marker),
             let .commandZ(marker),
             let .unsupportedModifiers(marker),
             let .unhandled(marker):
            marker
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            nil
        }
    }
}

protocol NativeEventDecoding {
    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent
}

protocol CurrentKeyboardTextRetranslating {
    func characters(for event: CGEvent) -> String?
}

private struct AppKitCurrentKeyboardTextRetranslator: CurrentKeyboardTextRetranslating {
    func characters(for event: CGEvent) -> String? {
        guard let nativeEvent = NSEvent(cgEvent: event) else { return nil }
        let modifiers = nativeEvent.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        return nativeEvent.characters(byApplyingModifiers: modifiers)
    }
}

final class SystemNativeEventDecoder: NativeEventDecoding {
    private static let deleteKey: CGKeyCode = 51
    private static let leftShiftKey: CGKeyCode = 56
    private static let rightShiftKey: CGKeyCode = 60
    private static let zKey: CGKeyCode = 6
    private static let navigationKeys: Set<CGKeyCode> = [
        48, 115, 116, 117, 119, 121, 123, 124, 125, 126,
    ]
    private let retranslator: any CurrentKeyboardTextRetranslating
    private var pressedShiftKeys: Set<ShiftKeySide> = []

    init(
        retranslator: any CurrentKeyboardTextRetranslating = AppKitCurrentKeyboardTextRetranslator()
    ) {
        self.retranslator = retranslator
    }

    static func decodeEmptyUnicodeKey(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        marker: Int64
    ) -> DecodedKeyboardEvent {
        if flags.contains(.maskShift),
           KeyboardLayoutMap.isAlphabeticKeyCode(Int(keyCode)) {
            return .text("", keyCode: keyCode, marker: marker)
        }
        return .unhandled(marker: marker)
    }

    func decode(_ event: CGEvent, type: CGEventType) -> DecodedKeyboardEvent {
        if type == .tapDisabledByTimeout {
            return .tapDisabledByTimeout
        }
        if type == .tapDisabledByUserInput {
            return .tapDisabledByUserInput
        }

        let marker = event.getIntegerValueField(.eventSourceUserData)
        if type == .flagsChanged {
            return decodeShiftChange(event, marker: marker)
        }
        guard type == .keyDown else { return .unhandled(marker: marker) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let commandZDisallowedModifiers: CGEventFlags = [
            .maskShift, .maskControl, .maskAlternate,
        ]
        if keyCode == Self.zKey,
           flags.contains(.maskCommand),
           flags.intersection(commandZDisallowedModifiers).isEmpty {
            return .commandZ(marker: marker)
        }

        let unsupportedModifiers: CGEventFlags = [
            .maskCommand, .maskControl, .maskAlternate,
        ]
        if !flags.intersection(unsupportedModifiers).isEmpty {
            return .unsupportedModifiers(marker: marker)
        }
        if keyCode == Self.deleteKey {
            return .deleteBackward(marker: marker)
        }
        if Self.navigationKeys.contains(keyCode) {
            return .navigation(marker: marker)
        }

        guard let characters = retranslator.characters(for: event) else {
            return .unhandled(marker: marker)
        }
        guard !characters.isEmpty else {
            // On Apple's standard Hebrew layout, Shift plus most letter keys
            // emits no Unicode text. Preserve those physical keydowns so Akuo
            // can recover the intended English capital at the word boundary.
            return Self.decodeEmptyUnicodeKey(
                keyCode: keyCode,
                flags: flags,
                marker: marker
            )
        }
        return .text(
            characters,
            keyCode: keyCode,
            marker: marker
        )
    }

    private func decodeShiftChange(
        _ event: CGEvent,
        marker: Int64
    ) -> DecodedKeyboardEvent {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let side: ShiftKeySide
        switch keyCode {
        case Self.leftShiftKey:
            side = .left
        case Self.rightShiftKey:
            side = .right
        default:
            return .unhandled(marker: marker)
        }

        let phase: ShiftKeyPhase
        if pressedShiftKeys.remove(side) != nil {
            phase = .up
        } else if event.flags.contains(.maskShift) {
            pressedShiftKeys.insert(side)
            phase = .down
        } else {
            pressedShiftKeys.removeAll(keepingCapacity: true)
            phase = .up
        }

        return .shiftChanged(
            side: side,
            phase: phase,
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000,
            marker: marker
        )
    }
}

protocol CorrectionCoordinating: AnyObject {
    func handleBoundary(
        _ completedWord: CompletedWord,
        boundaryKeyCode: Int?,
        context: FocusContext,
        priorInputLanguage: Language,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult
    func handleImmediateUndo(
        context: FocusContext,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult
    func handleForcedCorrection(
        _ unfinishedWord: CompletedWord?,
        context: FocusContext,
        priorInputLanguage: Language?,
        isContextStillEligible: () -> Bool
    ) -> CorrectionHandlingResult
    func noteOrdinaryInput()
}

extension CorrectionCoordinator: CorrectionCoordinating {}

protocol FocusContextProviding {
    func current() -> FocusContext?
}

extension FocusContextProvider: FocusContextProviding {}

protocol InputSourceStateProviding {
    var readiness: InputSourceReadiness { get }
    var currentLanguage: Language? { get }
    var currentSource: InputSourceSnapshot? { get }
    func preferredSource(for language: Language) -> InputSourceSnapshot?
}

extension InputSourceController: InputSourceStateProviding {}

extension InputSourceStateProviding {
    func preferredSource(for language: Language) -> InputSourceSnapshot? { nil }
}

protocol NativeEventTapManaging: AnyObject {
    var isInstalled: Bool { get }
    func install(
        userInfo: UnsafeMutableRawPointer,
        callback: CGEventTapCallBack
    ) -> Bool
    func setEnabled(_ enabled: Bool) -> Bool
    func remove()
}

private final class SystemNativeEventTapManager: NativeEventTapManaging {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isInstalled: Bool {
        eventTap != nil
    }

    func install(
        userInfo: UnsafeMutableRawPointer,
        callback: CGEventTapCallBack
    ) -> Bool {
        guard eventTap == nil else { return true }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: KeyboardEventMonitor.productionEventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard let eventTap else { return false }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
        return CGEvent.tapIsEnabled(tap: eventTap) == enabled
    }

    func remove() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }
}

public protocol KeyboardEventMonitorDelegate: AnyObject {
    func didChangeMonitorState(_ state: KeyboardEventMonitor.State)
    func didFailInputSourceSelection(_ failure: InputSourceSelectionFailure)
}

public extension KeyboardEventMonitorDelegate {
    func didFailInputSourceSelection(_ failure: InputSourceSelectionFailure) {}
}

public enum InputSourceSelectionOperation: Equatable, Sendable {
    case correction
    case forcedCorrection
    case immediateUndo
}

public struct InputSourceSelectionFailure: Equatable, Sendable {
    public let operation: InputSourceSelectionOperation
    public let expectedLanguage: Language

    public init(
        operation: InputSourceSelectionOperation,
        expectedLanguage: Language
    ) {
        self.operation = operation
        self.expectedLanguage = expectedLanguage
    }
}

public final class KeyboardEventMonitor {
    public enum State: Equatable, Sendable {
        case stopped
        case active
        case degraded
    }

    public static let syntheticMarker: Int64 = 0x414B554F
    static let productionEventMask = [
        CGEventType.keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
    ].reduce(CGEventMask(0)) { mask, eventType in
        mask | (CGEventMask(1) << eventType.rawValue)
    }

    public weak var delegate: (any KeyboardEventMonitorDelegate)?
    public private(set) var state: State = .stopped

    private let decoder: any NativeEventDecoding
    private let coordinator: any CorrectionCoordinating
    private let permission: any AccessibilityPermissionChecking
    private let secureInput: any SecureInputChecking
    private let focusContextProvider: any FocusContextProviding
    private let inputSources: any InputSourceStateProviding
    private let tapManager: any NativeEventTapManaging
    private let layoutTranslator: (any KeyboardLayoutTextTranslating)?
    private let forceConversionGesture: () -> ForceConversionGesture
    private let isAkuoEnabled: () -> Bool

    private var wordBuffer = WordBuffer()
    private var lastFocusContext: FocusContext?
    private var lastInputSourceIdentifier: String?
    private var suppressCorrectionUntilBoundary = false
    private var shiftGestureRecognizer = ShiftGestureRecognizer(activationInterval: 0.4)

    public convenience init(
        coordinator: CorrectionCoordinator,
        permission: any AccessibilityPermissionChecking,
        secureInput: any SecureInputChecking,
        focusContextProvider: FocusContextProvider,
        inputSources: InputSourceController,
        forceConversionGesture: @escaping () -> ForceConversionGesture = { .doubleShift },
        isAkuoEnabled: @escaping () -> Bool
    ) {
        self.init(
            decoder: SystemNativeEventDecoder(),
            coordinator: coordinator,
            permission: permission,
            secureInput: secureInput,
            focusContextProvider: focusContextProvider,
            inputSources: inputSources,
            tapManager: SystemNativeEventTapManager(),
            layoutTranslator: AppleKeyboardLayoutTextTranslator(),
            forceConversionGesture: forceConversionGesture,
            isAkuoEnabled: isAkuoEnabled
        )
    }

    init(
        decoder: any NativeEventDecoding,
        coordinator: any CorrectionCoordinating,
        permission: any AccessibilityPermissionChecking,
        secureInput: any SecureInputChecking,
        focusContextProvider: any FocusContextProviding,
        inputSources: any InputSourceStateProviding,
        tapManager: any NativeEventTapManaging,
        layoutTranslator: (any KeyboardLayoutTextTranslating)? = nil,
        forceConversionGesture: @escaping () -> ForceConversionGesture = { .doubleShift },
        isAkuoEnabled: @escaping () -> Bool
    ) {
        self.decoder = decoder
        self.coordinator = coordinator
        self.permission = permission
        self.secureInput = secureInput
        self.focusContextProvider = focusContextProvider
        self.inputSources = inputSources
        self.tapManager = tapManager
        self.layoutTranslator = layoutTranslator
        self.forceConversionGesture = forceConversionGesture
        self.isAkuoEnabled = isAkuoEnabled
    }

    deinit {
        tapManager.remove()
    }

    @discardableResult
    public func start() -> Bool {
        guard prerequisitesAreMet else {
            stop()
            return false
        }

        if !tapManager.isInstalled {
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            guard tapManager.install(userInfo: userInfo, callback: akuoEventTapCallback) else {
                setState(.degraded)
                return false
            }
        }

        guard tapManager.setEnabled(true) else {
            setState(.degraded)
            return false
        }
        setState(.active)
        return true
    }

    public func stop() {
        clearTransientState()
        tapManager.remove()
        setState(.stopped)
    }

    public func refreshState() {
        clearTransientState()
        restartAfterStateRefresh()
    }

    func refreshAfterAkuoInputSourceChange() {
        resetInputContext(invalidateImmediateUndo: false)
        restartAfterStateRefresh()
    }

    private func restartAfterStateRefresh() {
        if prerequisitesAreMet {
            _ = start()
        } else {
            tapManager.remove()
            setState(.stopped)
        }
    }

    @discardableResult
    func process(_ event: CGEvent, type: CGEventType? = nil) -> CGEvent? {
        let eventType = type ?? event.type
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return recoverDisabledTap(for: event)
        default:
            break
        }

        guard !secureInput.isSecureInputEnabled else {
            stop()
            return event
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return event
        }

        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            clearTransientState()
            return event
        default:
            break
        }

        guard let context = focusContextProvider.current(),
              context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput else {
            clearTransientState()
            return event
        }

        if let lastFocusContext, lastFocusContext != context {
            clearTransientState()
        }
        lastFocusContext = context

        let sourceBeforeDecoding = inputSources.currentSource
        let decoded = decoder.decode(event, type: eventType)

        switch decoded {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return recoverDisabledTap(for: event)
        default:
            break
        }

        if decoded.marker == Self.syntheticMarker {
            return event
        }

        if case .shiftChanged = decoded {
            // Keep a modifier-only sequence alive until it completes.
        } else {
            shiftGestureRecognizer.reset()
        }

        switch decoded {
        case let .shiftChanged(side, phase, timestamp, _):
            guard shiftGestureRecognizer.consume(
                side: side,
                phase: phase,
                timestamp: timestamp,
                gesture: forceConversionGesture()
            ) else {
                return event
            }
            let unfinishedWord = wordBuffer.unfinishedWord
            let sourceAtGesture = inputSources.currentSource
            if unfinishedWord != nil,
               lastInputSourceIdentifier != sourceAtGesture?.identifier {
                clearTransientState()
                return event
            }
            let result = coordinator.handleForcedCorrection(
                unfinishedWord,
                context: context,
                priorInputLanguage: sourceAtGesture?.language,
                isContextStillEligible: {
                    self.isContextStillEligible(context)
                        && self.inputSources.currentSource == sourceAtGesture
                }
            )
            if case let .handledWithInputSourceSelectionFailure(expectedLanguage) = result {
                delegate?.didFailInputSourceSelection(.init(
                    operation: .forcedCorrection,
                    expectedLanguage: expectedLanguage
                ))
            }
            if result != .notHandled, unfinishedWord != nil {
                resetInputContext(invalidateImmediateUndo: false)
            }
            return event

        case let .text(text, keyCode, _):
            guard let sourceBeforeDecoding,
                  let sourceAfterDecoding = inputSources.currentSource,
                  sourceAfterDecoding == sourceBeforeDecoding else {
                clearTransientState()
                return event
            }
            if let lastInputSourceIdentifier,
               lastInputSourceIdentifier != sourceAfterDecoding.identifier {
                resetInputContext(invalidateImmediateUndo: true)
                lastFocusContext = context
            }
            lastInputSourceIdentifier = sourceAfterDecoding.identifier
            let language = sourceAfterDecoding.language
            coordinator.noteOrdinaryInput()
            let isSilentShiftedHebrewLetter = language == .hebrew
                && text.isEmpty
                && keyCode.map { KeyboardLayoutMap.isAlphabeticKeyCode(Int($0)) } == true
            let isBufferedTokenText = isTokenText(
                text,
                keyCode: keyCode,
                language: language
            ) || isSilentShiftedHebrewLetter
            if suppressCorrectionUntilBoundary {
                if !isBufferedTokenText {
                    suppressCorrectionUntilBoundary = false
                }
                return event
            }
            if isBufferedTokenText {
                if let keyCode {
                    var modifiers = ObservedKeyModifiers()
                    if event.flags.contains(.maskShift) {
                        modifiers.insert(.shift)
                    }
                    if event.flags.contains(.maskAlphaShift) {
                        modifiers.insert(.capsLock)
                    }
                    let targetLanguage: Language = language == .english
                        ? .hebrew
                        : .english
                    let targetText = inputSources.preferredSource(for: targetLanguage)
                        .flatMap { targetSource in
                            layoutTranslator?.characters(
                                keyCode: Int(keyCode),
                                modifiers: modifiers,
                                inputSourceIdentifier: targetSource.identifier
                            )
                    }
                    if layoutTranslator != nil, targetText == nil {
                        clearTransientState()
                        suppressCorrectionUntilBoundary = true
                        return event
                    }
                    _ = wordBuffer.consume(.observedKeyStroke(.init(
                        text: text,
                        keyCode: Int(keyCode),
                        modifiers: modifiers,
                        targetText: targetText
                    )))
                } else {
                    _ = wordBuffer.consume(.text(text))
                }
                return event
            }

            guard isCorrectionBoundary(text, keyCode: keyCode) else {
                resetInputContext(invalidateImmediateUndo: false)
                return event
            }

            switch wordBuffer.consume(.boundary(text)) {
            case let .completed(completedWord):
                let result = coordinator.handleBoundary(
                    completedWord,
                    boundaryKeyCode: keyCode.map(Int.init),
                    context: context,
                    priorInputLanguage: language,
                    isContextStillEligible: {
                        self.isContextStillEligible(context)
                    }
                )
                if case let .handledWithInputSourceSelectionFailure(expectedLanguage) = result {
                    delegate?.didFailInputSourceSelection(.init(
                        operation: .correction,
                        expectedLanguage: expectedLanguage
                    ))
                }
                return result == .notHandled ? event : nil
            case .accumulating, .passThrough, .reset:
                return event
            }

        case .deleteBackward:
            coordinator.noteOrdinaryInput()
            _ = wordBuffer.consume(.deleteBackward)
            return event

        case .navigation, .unsupportedModifiers, .unhandled:
            clearTransientState()
            return event

        case .commandZ:
            wordBuffer.reset()
            let result = coordinator.handleImmediateUndo(
                context: context,
                isContextStillEligible: {
                    self.isContextStillEligible(context)
                }
            )
            if case let .handledWithInputSourceSelectionFailure(expectedLanguage) = result {
                delegate?.didFailInputSourceSelection(.init(
                    operation: .immediateUndo,
                    expectedLanguage: expectedLanguage
                ))
            }
            if result != .notHandled {
                return nil
            }
            coordinator.noteOrdinaryInput()
            return event

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return event
        }
    }

    var currentTokenForTesting: String {
        wordBuffer.currentToken
    }

    private func isContextStillEligible(_ expected: FocusContext) -> Bool {
        guard !secureInput.isSecureInputEnabled,
              let current = focusContextProvider.current() else {
            return false
        }
        return current == expected
            && current.elementIdentifier != nil
            && !current.isSecureField
            && current.isEditableTextInput
    }

    private var prerequisitesAreMet: Bool {
        let readiness = inputSources.readiness
        return isAkuoEnabled()
            && permission.isGranted
            && readiness.englishAvailable
            && readiness.hebrewAvailable
            && !secureInput.isSecureInputEnabled
    }

    private func isTokenText(
        _ text: String,
        keyCode: CGKeyCode?,
        language: Language
    ) -> Bool {
        if language == .hebrew,
           (keyCode == 12 && text == "/") || (keyCode == 13 && text == "'") {
            return true
        }
        guard !text.isEmpty else { return false }
        // Keep printable punctuation with the unfinished token so structured
        // shapes reach the exclusion policy intact at Space or Return/Enter.
        return text.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.controlCharacters.contains($0)
        }
    }

    private func isCorrectionBoundary(_ text: String, keyCode: CGKeyCode?) -> Bool {
        guard let keyCode else { return false }
        switch (keyCode, text) {
        case (49, " "), (36, "\r"), (36, "\n"), (76, "\u{3}"):
            return true
        default:
            return false
        }
    }

    private func clearTransientState() {
        resetInputContext(invalidateImmediateUndo: true)
    }

    private func resetInputContext(invalidateImmediateUndo: Bool) {
        wordBuffer.reset()
        lastFocusContext = nil
        lastInputSourceIdentifier = nil
        suppressCorrectionUntilBoundary = false
        shiftGestureRecognizer.reset()
        if invalidateImmediateUndo {
            coordinator.noteOrdinaryInput()
        }
    }

    private func recoverDisabledTap(for event: CGEvent) -> CGEvent {
        clearTransientState()
        guard prerequisitesAreMet, tapManager.isInstalled else {
            setState(.stopped)
            return event
        }
        setState(tapManager.setEnabled(true) ? .active : .degraded)
        return event
    }

    private func setState(_ state: State) {
        guard self.state != state else { return }
        self.state = state
        delegate?.didChangeMonitorState(state)
    }
}

private func akuoEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<KeyboardEventMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    guard let returnedEvent = monitor.process(event, type: type) else {
        return nil
    }
    return Unmanaged.passUnretained(returnedEvent)
}
