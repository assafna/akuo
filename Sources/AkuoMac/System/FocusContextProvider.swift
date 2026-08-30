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

struct AccessibilityFocusElement: Equatable {
    let identifier: String
    let role: String?
    let subrole: String?
}

protocol AccessibilityFocusProviding {
    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement?
}

private struct SystemAccessibilityFocusProvider: AccessibilityFocusProviding {
    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
            let value
        else {
            return nil
        }

        let element = value as! AXUIElement
        return AccessibilityFocusElement(
            identifier: String(CFHash(element)),
            role: stringAttribute(kAXRoleAttribute, of: element),
            subrole: stringAttribute(kAXSubroleAttribute, of: element)
        )
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
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
            return FocusContext(
                processIdentifier: processIdentifier,
                elementIdentifier: nil,
                isSecureField: false,
                isEditableTextInput: false
            )
        }

        let isSecureField = element.role == Self.secureTextField
            || element.subrole == Self.secureTextField
        return FocusContext(
            processIdentifier: processIdentifier,
            elementIdentifier: element.identifier,
            isSecureField: isSecureField,
            isEditableTextInput: !isSecureField
                && element.role.map(Self.editableTextRoles.contains) == true
        )
    }
}
