import AppKit
import ApplicationServices
import AkuoCore

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

struct AccessibilityFocusElement: Equatable {
    let identifier: String
    let role: String?
    let subrole: AccessibilityOptionalString
    let isEnabled: AccessibilityOptionalBoolean
    let isValueSettable: Bool?
}

protocol AccessibilityFocusProviding {
    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement?
}

struct AccessibilityAttributeRead {
    let result: AXError
    let value: CFTypeRef?
}

protocol AccessibilityAttributeReading {
    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead
    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool?
}

private struct SystemAccessibilityAttributeReader: AccessibilityAttributeReading {
    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
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
    private let reader: any AccessibilityAttributeReading
    private let identityTracker = AccessibilityFocusIdentityTracker()

    init(reader: any AccessibilityAttributeReading = SystemAccessibilityAttributeReader()) {
        self.reader = reader
    }

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        let initialFocus = reader.attribute(kAXFocusedUIElementAttribute, of: application)
        guard initialFocus.result == .success,
              let element = AccessibilityAttributeDecoder.element(from: initialFocus.value) else {
            return nil
        }

        let role = reader.attribute(kAXRoleAttribute, of: element)
        let subrole = reader.attribute(kAXSubroleAttribute, of: element)
        let isEnabled = reader.attribute(kAXEnabledAttribute, of: element)
        let isValueSettable = reader.isAttributeSettable(kAXValueAttribute, of: element)

        let finalFocus = reader.attribute(kAXFocusedUIElementAttribute, of: application)
        guard finalFocus.result == .success,
              let confirmedElement = AccessibilityAttributeDecoder.element(from: finalFocus.value),
              CFEqual(element, confirmedElement) else {
            return nil
        }

        return AccessibilityFocusElement(
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
            isValueSettable: isValueSettable
        )
    }
}

public struct FocusContextProvider {
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

    public init() {
        frontmostProcessProvider = WorkspaceFrontmostProcessProvider()
        accessibilityProvider = SystemAccessibilityFocusProvider()
    }

    init(
        frontmostProcessProvider: some FrontmostProcessProviding,
        accessibilityProvider: some AccessibilityFocusProviding
    ) {
        self.frontmostProcessProvider = frontmostProcessProvider
        self.accessibilityProvider = accessibilityProvider
    }

    public func current() -> FocusContext? {
        guard let processIdentifier = frontmostProcessProvider.processIdentifier else {
            return nil
        }
        guard let element = accessibilityProvider.focusedElement(for: processIdentifier) else {
            guard frontmostProcessProvider.processIdentifier == processIdentifier else {
                return nil
            }
            return FocusContext(
                processIdentifier: processIdentifier,
                elementIdentifier: nil,
                isSecureField: false,
                isEditableTextInput: false
            )
        }

        guard frontmostProcessProvider.processIdentifier == processIdentifier else {
            return nil
        }

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
}
