import AppKit
import ApplicationServices
import AkuoCore

private enum AccessibilityCallbackBudget {
    private static let key = "Akuo.accessibilityCallbackDeadline"
    static func begin(now: TimeInterval) -> () -> Void {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        guard previous == nil else { return {} }
        dictionary[key] = now + 0.100
        return { dictionary[key] = previous }
    }
    static func remaining(now: TimeInterval) -> Float? {
        guard let deadline = Thread.current.threadDictionary[key] as? TimeInterval else { return nil }
        return Float(deadline - now)
    }
}

protocol FrontmostProcessProviding {
    var processIdentifier: Int32? { get }
}

private struct WorkspaceFrontmostProcessProvider: FrontmostProcessProviding {
    var processIdentifier: Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

enum AccessibilityOptionalString: Equatable {
    case value(String)
    case absent
    case unknown

    var value: String? {
        guard case let .value(value) = self else {
            return nil
        }
        return value
    }

    var isKnown: Bool {
        self != .unknown
    }
}

enum AccessibilityOptionalBoolean: Equatable {
    case value(Bool)
    case absent
    case unknown

    var permitsInteraction: Bool {
        switch self {
        case .value(true), .absent:
            true
        case .value(false), .unknown:
            false
        }
    }
}

enum AccessibilityAttributeDecoder {
    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func boolean(from value: CFTypeRef?) -> Bool? {
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    static func string(from value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    static func range(from value: CFTypeRef?) -> NSRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0,
              range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    static func optionalString(
        result: AXError,
        value: CFTypeRef?
    ) -> AccessibilityOptionalString {
        switch result {
        case .success:
            guard let value = string(from: value), value != kAXUnknownSubrole else {
                return .unknown
            }
            return .value(value)
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .unknown
        }
    }

    static func optionalBoolean(
        result: AXError,
        value: CFTypeRef?
    ) -> AccessibilityOptionalBoolean {
        switch result {
        case .success:
            guard let value = boolean(from: value) else {
                return .unknown
            }
            return .value(value)
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .unknown
        }
    }
}

enum AccessibilityTextMatcher {
    static func precedingRange(
        selectedRange: NSRange,
        expectedText: String
    ) -> NSRange? {
        precedingRange(
            selectedRange: selectedRange,
            utf16Length: (expectedText as NSString).length
        )
    }

    static func precedingRange(
        selectedRange: NSRange,
        utf16Length: Int
    ) -> NSRange? {
        guard utf16Length > 0,
              selectedRange.location != NSNotFound,
              selectedRange.length == 0 else {
            return nil
        }

        guard selectedRange.location >= utf16Length else {
            return nil
        }
        return NSRange(
            location: selectedRange.location - utf16Length,
            length: utf16Length
        )
    }
}

struct AccessibilityFocusElement: Equatable {
    let identifier: String
    let role: String?
    let subrole: AccessibilityOptionalString
    let isEnabled: AccessibilityOptionalBoolean
    let isValueSettable: Bool?
}

enum AccessibilityFocusSnapshot: Equatable {
    case focused(AccessibilityFocusElement)
    case stablyAbsent
    case unavailable
}

protocol AccessibilityFocusProviding {
    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement?
    func focusSnapshot(for processIdentifier: Int32) -> AccessibilityFocusSnapshot
    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> Bool
    func textImmediatelyBeforeCaret(
        utf16Length: Int,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> String?
}

extension AccessibilityFocusProviding {
    func focusSnapshot(for processIdentifier: Int32) -> AccessibilityFocusSnapshot {
        guard let element = focusedElement(for: processIdentifier) else {
            return .stablyAbsent
        }
        return .focused(element)
    }
    func textImmediatelyBeforeCaret(
        utf16Length: Int,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> String? {
        nil
    }
}

struct AccessibilityAttributeRead {
    let result: AXError
    let value: CFTypeRef?
}

private struct AccessibilitySettableValue {
    let value: Bool?
}

protocol AccessibilityAttributeReading {
    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead
    func parameterizedAttribute(
        _ attribute: String,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead
    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool?
}

private struct SystemAccessibilityAttributeReader: AccessibilityAttributeReading {
    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return .init(result: result, value: value)
    }

    func parameterizedAttribute(
        _ attribute: String,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        )
        return .init(result: result, value: value)
    }

    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool? {
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &isSettable
        ) == .success else {
            return nil
        }
        return isSettable.boolValue
    }
}

private final class AccessibilityFocusIdentityTracker {
    private var element: AXUIElement?
    private var identifier: String?

    func identifier(for focusedElement: AXUIElement) -> String {
        if let element, let identifier, CFEqual(element, focusedElement) {
            return identifier
        }

        let identifier = UUID().uuidString
        element = focusedElement
        self.identifier = identifier
        return identifier
    }
}

final class SystemAccessibilityFocusProvider: AccessibilityFocusProviding {
    private static let messagingTimeout: Float = 0.005
    private let reader: any AccessibilityAttributeReading
    private let configureMessagingTimeout: (AXUIElement, Float) -> AXError
    private let now: () -> TimeInterval
    private let identityTracker = AccessibilityFocusIdentityTracker()

    init(
        reader: any AccessibilityAttributeReading = SystemAccessibilityAttributeReader(),
        configureMessagingTimeout: @escaping (AXUIElement, Float) -> AXError = AXUIElementSetMessagingTimeout,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.reader = reader
        self.configureMessagingTimeout = configureMessagingTimeout
        self.now = now
    }

    func beginCallbackBudget() -> () -> Void { AccessibilityCallbackBudget.begin(now: now()) }

    func hasCallbackBudgetRemaining() -> Bool {
        guard let remaining = AccessibilityCallbackBudget.remaining(now: now()) else {
            return false
        }
        return remaining > 0
    }

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        guard case let .focused(element) = focusSnapshot(for: processIdentifier) else {
            return nil
        }
        return element
    }

    func focusSnapshot(for processIdentifier: Int32) -> AccessibilityFocusSnapshot {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let initialFocus = attribute(
            kAXFocusedUIElementAttribute,
            of: application
        ) else {
            return .unavailable
        }
        if initialFocus.result == .noValue, initialFocus.value == nil {
            guard let finalFocus = attribute(
                kAXFocusedUIElementAttribute,
                of: application
            ) else {
                return .unavailable
            }
            return finalFocus.result == .noValue && finalFocus.value == nil
                ? .stablyAbsent
                : .unavailable
        }
        guard initialFocus.result == .success,
              let element = AccessibilityAttributeDecoder.element(from: initialFocus.value) else {
            return .unavailable
        }

        guard let role = attribute(kAXRoleAttribute, of: element),
              let subrole = attribute(kAXSubroleAttribute, of: element),
              let isEnabled = attribute(kAXEnabledAttribute, of: element),
              let settable = isAttributeSettable(kAXValueAttribute, of: element),
              let finalFocus = attribute(
                  kAXFocusedUIElementAttribute,
                  of: application
              ) else {
            return .unavailable
        }

        guard finalFocus.result == .success,
              let confirmedElement = AccessibilityAttributeDecoder.element(from: finalFocus.value),
              CFEqual(element, confirmedElement) else {
            return .unavailable
        }

        return .focused(AccessibilityFocusElement(
            identifier: identityTracker.identifier(for: element),
            role: role.result == .success
                ? AccessibilityAttributeDecoder.string(from: role.value)
                : nil,
            subrole: AccessibilityAttributeDecoder.optionalString(
                result: subrole.result,
                value: subrole.value
            ),
            isEnabled: AccessibilityAttributeDecoder.optionalBoolean(
                result: isEnabled.result,
                value: isEnabled.value
            ),
            isValueSettable: settable.value
        ))
    }

    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> Bool {
        guard !expectedText.isEmpty else { return false }
        return readTextImmediatelyBeforeCaret(
            utf16Length: (expectedText as NSString).length,
            processIdentifier: processIdentifier,
            elementIdentifier: elementIdentifier,
            requiresDocumentStart: false
        ) == expectedText
    }

    func textImmediatelyBeforeCaret(
        utf16Length: Int,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> String? {
        readTextImmediatelyBeforeCaret(
            utf16Length: utf16Length,
            processIdentifier: processIdentifier,
            elementIdentifier: elementIdentifier,
            requiresDocumentStart: true
        )
    }

    private func readTextImmediatelyBeforeCaret(
        utf16Length: Int,
        processIdentifier: Int32,
        elementIdentifier: String,
        requiresDocumentStart: Bool
    ) -> String? {
        guard utf16Length > 0 else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let initialFocus = attribute(
            kAXFocusedUIElementAttribute,
            of: application
        ) else { return nil }
        guard initialFocus.result == .success,
              let element = AccessibilityAttributeDecoder.element(from: initialFocus.value),
              identityTracker.identifier(for: element) == elementIdentifier else {
            return nil
        }

        guard let selectedRange = attribute(kAXSelectedTextRangeAttribute, of: element) else {
            return nil
        }
        guard selectedRange.result == .success,
              let caretRange = AccessibilityAttributeDecoder.range(
                  from: selectedRange.value
              ),
              let precedingRange = AccessibilityTextMatcher.precedingRange(
                  selectedRange: caretRange,
                  utf16Length: utf16Length
              ),
              !requiresDocumentStart || precedingRange.location == 0 else {
            return nil
        }
        var requestedRange = CFRange(
            location: precedingRange.location,
            length: precedingRange.length
        )
        guard let requestedRangeValue = AXValueCreate(.cfRange, &requestedRange) else {
            return nil
        }
        guard let previousText = parameterizedAttribute(
            kAXStringForRangeParameterizedAttribute,
            parameter: requestedRangeValue,
            of: element
        ), let finalSelectedRange = attribute(
            kAXSelectedTextRangeAttribute,
            of: element
        ), let finalFocus = attribute(
            kAXFocusedUIElementAttribute,
            of: application
        ) else {
            return nil
        }
        guard previousText.result == .success,
              let text = AccessibilityAttributeDecoder.string(from: previousText.value),
              (text as NSString).length == utf16Length,
              finalSelectedRange.result == .success,
              AccessibilityAttributeDecoder.range(from: finalSelectedRange.value)
                  == caretRange,
              finalFocus.result == .success,
              let confirmedElement = AccessibilityAttributeDecoder.element(from: finalFocus.value),
              CFEqual(element, confirmedElement) else {
            return nil
        }

        return text
    }

    private func attribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead? {
        request(on: element) { reader.attribute(attribute, of: element) }
    }

    private func parameterizedAttribute(
        _ attribute: String,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead? {
        request(on: element) {
            reader.parameterizedAttribute(attribute, parameter: parameter, of: element)
        }
    }

    private func isAttributeSettable(
        _ attribute: String,
        of element: AXUIElement
    ) -> AccessibilitySettableValue? {
        request(on: element) {
            AccessibilitySettableValue(
                value: reader.isAttributeSettable(attribute, of: element)
            )
        }
    }

    private func request<T>(
        on element: AXUIElement,
        operation: () -> T
    ) -> T? {
        guard prepare(element) else { return nil }
        let result = operation()
        guard isWithinCallbackBudget else { return nil }
        return result
    }

    private var isWithinCallbackBudget: Bool {
        guard let remaining = AccessibilityCallbackBudget.remaining(now: now()) else {
            return true
        }
        return remaining > 0
    }

    private func prepare(_ element: AXUIElement) -> Bool {
        let timeout: Float
        if let remaining = AccessibilityCallbackBudget.remaining(now: now()) {
            guard remaining > 0 else { return false }
            timeout = min(Self.messagingTimeout, remaining)
        } else {
            timeout = Self.messagingTimeout
        }
        return configureMessagingTimeout(element, timeout) == .success
    }
}

public struct FocusContextProvider {
    // Four ahead processes cover the observed panel-plus-overlay topology.
    // One callback-wide 100 ms deadline covers every resolver, recovery, and
    // validation read. Each AX IPC is reconfigured to min(5 ms, remaining),
    // and evidence is rejected after the request if that one in-flight request
    // crosses the deadline.
    private static let maximumAheadProcessIdentifiers = 4
    private static let secureTextField = "AXSecureTextField"
    // Akuo supports only standard editable text roles that are
    // consistently exposed by the supported macOS 13+ application contexts.
    private static let editableTextRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
    ]

    private let frontmostProcessProvider: any FrontmostProcessProviding
    private let accessibilityProvider: any AccessibilityFocusProviding
    private let windowProcessOrderingProvider: any WindowProcessOrderingProviding

    public init() {
        frontmostProcessProvider = WorkspaceFrontmostProcessProvider()
        accessibilityProvider = SystemAccessibilityFocusProvider()
        windowProcessOrderingProvider = SystemWindowProcessOrderingProvider()
    }

    func beginAccessibilityCallbackBudget() -> () -> Void {
        guard let provider = accessibilityProvider as? SystemAccessibilityFocusProvider else { return {} }
        return provider.beginCallbackBudget()
    }

    func hasAccessibilityCallbackBudgetRemaining() -> Bool {
        guard let provider = accessibilityProvider as? SystemAccessibilityFocusProvider else {
            return false
        }
        return provider.hasCallbackBudgetRemaining()
    }

    init(
        frontmostProcessProvider: some FrontmostProcessProviding,
        accessibilityProvider: some AccessibilityFocusProviding
    ) {
        self.frontmostProcessProvider = frontmostProcessProvider
        self.accessibilityProvider = accessibilityProvider
        windowProcessOrderingProvider = SystemWindowProcessOrderingProvider()
    }

    init(
        frontmostProcessProvider: some FrontmostProcessProviding,
        accessibilityProvider: some AccessibilityFocusProviding,
        windowProcessOrderingProvider: some WindowProcessOrderingProviding
    ) {
        self.frontmostProcessProvider = frontmostProcessProvider
        self.accessibilityProvider = accessibilityProvider
        self.windowProcessOrderingProvider = windowProcessOrderingProvider
    }

    public func current() -> FocusContext? {
        guard let processIdentifier = frontmostProcessProvider.processIdentifier else {
            return nil
        }
        let context = current(processIdentifier: processIdentifier)
        guard frontmostProcessProvider.processIdentifier == processIdentifier else {
            return nil
        }
        return context
    }

    public func current(processIdentifier: Int32) -> FocusContext? {
        guard case let .focused(element) = accessibilityProvider.focusSnapshot(
            for: processIdentifier
        ) else {
            return FocusContext(
                processIdentifier: processIdentifier,
                elementIdentifier: nil,
                isSecureField: false,
                isEditableTextInput: false
            )
        }

        return context(processIdentifier: processIdentifier, element: element)
    }

    private func context(
        processIdentifier: Int32,
        element: AccessibilityFocusElement
    ) -> FocusContext {
        let isSecureField = element.role == Self.secureTextField
            || element.subrole.value == Self.secureTextField
        return FocusContext(
            processIdentifier: processIdentifier,
            elementIdentifier: element.identifier,
            isSecureField: isSecureField,
            isEditableTextInput: !isSecureField
                && element.role.map(Self.editableTextRoles.contains) == true
                && element.subrole.isKnown
                && element.isEnabled.permitsInteraction
                && element.isValueSettable == true
        )
    }

    public func currentInteractionContext() -> FocusContext? {
        guard let processIdentifier = frontmostProcessProvider.processIdentifier else {
            return nil
        }
        let context = currentInteractionContext(
            activationOwnerProcessIdentifier: processIdentifier
        )
        guard frontmostProcessProvider.processIdentifier == processIdentifier else {
            return nil
        }
        return context
    }

    public func currentInteractionContext(
        activationOwnerProcessIdentifier: Int32
    ) -> FocusContext? {
        guard let processIdentifiers = windowProcessOrderingProvider.processIdentifiersInFront(
            of: activationOwnerProcessIdentifier
        ), Set(processIdentifiers).count == processIdentifiers.count,
           processIdentifiers.count <= Self.maximumAheadProcessIdentifiers else {
            return nil
        }

        var interactionContext: FocusContext?
        for processIdentifier in processIdentifiers {
            switch accessibilityProvider.focusSnapshot(for: processIdentifier) {
            case .stablyAbsent:
                continue
            case .unavailable:
                return nil
            case let .focused(element):
                let context = context(processIdentifier: processIdentifier, element: element)
                guard interactionContext == nil else {
                    return nil
                }
                interactionContext = context
            }
        }

        return interactionContext ?? current(processIdentifier: activationOwnerProcessIdentifier)
    }

    public func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        context: FocusContext
    ) -> Bool {
        guard context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput,
              let elementIdentifier = context.elementIdentifier,
              accessibilityProvider.hasExactTextImmediatelyBeforeCaret(
                  expectedText,
                  processIdentifier: context.processIdentifier,
                  elementIdentifier: elementIdentifier
              ) else {
            return false
        }
        return true
    }

    func textImmediatelyBeforeCaret(
        utf16Length: Int,
        context: FocusContext
    ) -> String? {
        guard utf16Length > 0,
              context.elementIdentifier != nil,
              !context.isSecureField,
              context.isEditableTextInput,
              let elementIdentifier = context.elementIdentifier,
              let text = accessibilityProvider.textImmediatelyBeforeCaret(
                  utf16Length: utf16Length,
                  processIdentifier: context.processIdentifier,
                  elementIdentifier: elementIdentifier
              ),
              (text as NSString).length == utf16Length else {
            return nil
        }
        return text
    }
}

extension FocusContextProvider: PreviousTextValidating {}
