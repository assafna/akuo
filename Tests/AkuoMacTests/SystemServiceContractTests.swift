import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

final class SystemServiceContractTests: XCTestCase {
    func testSpellCheckerUsesEnglishLocale() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(recognized: [("hello", "en_US")])
        )

        XCTAssertTrue(checker.recognizes("hello", as: .english))
        XCTAssertFalse(checker.recognizes("hello", as: .hebrew))
    }

    func testSpellCheckerUsesHebrewLocale() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(recognized: [("שלום", "he_IL")])
        )

        XCTAssertTrue(checker.recognizes("שלום", as: .hebrew))
        XCTAssertFalse(checker.recognizes("שלום", as: .english))
    }

    func testSpellCheckerAlwaysRejectsEmptyWords() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(recognized: [("", "en_US"), ("", "he_IL")])
        )

        XCTAssertFalse(checker.recognizes("", as: .english))
        XCTAssertFalse(checker.recognizes("", as: .hebrew))
    }

    func testPermissionRequestIsExplicitRatherThanInitializationSideEffect() {
        let backend = FakeAccessibilityPermissionBackend(isGranted: false)
        let permission = SystemAccessibilityPermission(backend: backend)

        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertFalse(permission.isGranted)
        XCTAssertEqual(backend.requestCount, 0)

        permission.request()

        XCTAssertEqual(backend.requestCount, 1)
    }

    func testSecureInputCheckerReportsBackendStatus() {
        XCTAssertTrue(
            SystemSecureInputChecker(
                backend: FakeSecureInputBackend(isSecureInputEnabled: true)
            ).isSecureInputEnabled
        )
        XCTAssertFalse(
            SystemSecureInputChecker(
                backend: FakeSecureInputBackend(isSecureInputEnabled: false)
            ).isSecureInputEnabled
        )
    }

    func testFocusContextIncludesFrontmostProcessAndFocusedElement() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(identifier: "element-1", role: "AXTextField", subrole: nil)
            )
        )

        XCTAssertEqual(
            provider.current(),
            .init(
                processIdentifier: 42,
                elementIdentifier: "element-1",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
    }

    func testOnlyNarrowTextEntryRoleAllowlistIsEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            let provider = FocusContextProvider(
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
                accessibilityProvider: FakeAccessibilityFocusProvider(
                    element: .init(identifier: role, role: role, subrole: nil)
                )
            )

            XCTAssertEqual(provider.current()?.isEditableTextInput, true, role)
        }
    }

    func testNonTextAndUnknownRolesAreIneligible() {
        for role in ["AXList", "AXOutline", "AXRow", "AXStaticText", nil] {
            let provider = FocusContextProvider(
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
                accessibilityProvider: FakeAccessibilityFocusProvider(
                    element: .init(identifier: "control", role: role, subrole: nil)
                )
            )

            XCTAssertEqual(provider.current()?.isEditableTextInput, false, role ?? "missing role")
        }
    }

    func testSecureTextFieldRoleMarksFocusContextSecure() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(identifier: "secret", role: "AXSecureTextField", subrole: nil)
            )
        )

        XCTAssertEqual(
            provider.current(),
            .init(
                processIdentifier: 42,
                elementIdentifier: "secret",
                isSecureField: true,
                isEditableTextInput: false
            )
        )
    }

    func testSecureTextFieldSubroleMarksFocusContextSecure() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "secret",
                    role: "AXTextField",
                    subrole: "AXSecureTextField"
                )
            )
        )

        XCTAssertEqual(
            provider.current(),
            .init(
                processIdentifier: 42,
                elementIdentifier: "secret",
                isSecureField: true,
                isEditableTextInput: false
            )
        )
    }

    func testMissingFocusedElementPreservesProcessWithIneligibleIdentity() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(element: nil)
        )

        XCTAssertEqual(
            provider.current(),
            .init(
                processIdentifier: 42,
                elementIdentifier: nil,
                isSecureField: false,
                isEditableTextInput: false
            )
        )
    }

    func testMissingFrontmostApplicationReturnsNoFocusContext() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: nil),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(identifier: "ignored", role: "AXTextField", subrole: nil)
            )
        )

        XCTAssertNil(provider.current())
    }

    func testCompositeRecognizerUsesNormalizedPrimaryThenFallback() {
        let primary = LiteralRecognizer(recognized: ["english:hello"])
        let fallback = LiteralRecognizer(recognized: ["hebrew:שלום"])
        let recognizer = CompositeWordRecognizer(primary: primary, fallback: fallback)

        XCTAssertTrue(recognizer.recognizes("HELLO", as: .english))
        XCTAssertTrue(recognizer.recognizes("שלום", as: .hebrew))
        XCTAssertFalse(recognizer.recognizes("unknown", as: .english))
    }
}

private struct LocaleSpellCheckerBackend: SpellCheckerBackend {
    let recognized: Set<String>

    init(recognized: [(String, String)]) {
        self.recognized = Set(recognized.map { "\($0.1):\($0.0)" })
    }

    func misspelledRange(in word: String, language: String) -> NSRange {
        recognized.contains("\(language):\(word)")
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (word as NSString).length)
    }
}

private final class FakeAccessibilityPermissionBackend: AccessibilityPermissionBackend {
    let isGranted: Bool
    private(set) var requestCount = 0

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    func request() {
        requestCount += 1
    }
}

private struct FakeSecureInputBackend: SecureInputBackend {
    let isSecureInputEnabled: Bool
}

private struct FakeFrontmostProcessProvider: FrontmostProcessProviding {
    let processIdentifier: Int32?
}

private struct FakeAccessibilityFocusProvider: AccessibilityFocusProviding {
    let element: AccessibilityFocusElement?

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        element
    }
}

private struct LiteralRecognizer: WordRecognizing {
    let recognized: Set<String>

    func recognizes(_ word: String, as language: Language) -> Bool {
        recognized.contains("\(language.rawValue):\(word)")
    }
}
