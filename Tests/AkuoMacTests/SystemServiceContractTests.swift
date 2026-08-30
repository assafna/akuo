import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

final class SystemServiceContractTests: XCTestCase {
    func testSpellCheckerUsesEnglishLocale() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(recognized: [("hello", "en_US")])
        )

        XCTAssertEqual(checker.recognitionStatus(for: "hello", as: .english), .recognized)
        XCTAssertEqual(checker.recognitionStatus(for: "hello", as: .hebrew), .unknown)
    }

    func testSpellCheckerUsesHebrewLocale() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(recognized: [("שלום", "he_IL")])
        )

        XCTAssertEqual(checker.recognitionStatus(for: "שלום", as: .hebrew), .recognized)
        XCTAssertEqual(checker.recognitionStatus(for: "שלום", as: .english), .unknown)
    }

    func testSpellCheckerAlwaysRejectsEmptyWords() {
        let checker = SystemSpellChecker(
            backend: LocaleSpellCheckerBackend(
                availableLanguages: [],
                recognized: [("", "en_US"), ("", "he_IL")]
            )
        )

        XCTAssertEqual(checker.recognitionStatus(for: "", as: .english), .unknown)
        XCTAssertEqual(checker.recognitionStatus(for: "", as: .hebrew), .unknown)
    }

    func testSpellCheckerReportsUnavailableWhenRequestedLanguageIsMissing() {
        let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
            availableLanguages: ["en_US"],
            recognized: []
        ))

        XCTAssertEqual(
            checker.recognitionStatus(for: "שלום", as: .hebrew),
            .unavailable
        )
    }

    func testSpellCheckerReportsUnavailableWhenBackendCheckFails() {
        let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
            availableLanguages: ["en_US", "he_IL"],
            recognized: [],
            failed: ["he_IL:שלום"]
        ))

        XCTAssertEqual(
            checker.recognitionStatus(for: "שלום", as: .hebrew),
            .unavailable
        )
    }

    func testSpellCheckerReportsUnknownForCompletedMisspelling() {
        let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
            availableLanguages: ["en_US", "he_IL"],
            recognized: []
        ))

        XCTAssertEqual(
            checker.recognitionStatus(for: "notaword", as: .english),
            .unknown
        )
    }

    func testSpellCheckerAcceptsAdvertisedBaseLanguagesForLocaleChecks() {
        let checker = SystemSpellChecker(backend: LocaleSpellCheckerBackend(
            availableLanguages: ["en", "he"],
            recognized: [("hello", "en_US"), ("שלום", "he_IL")]
        ))

        XCTAssertEqual(
            checker.recognitionStatus(for: "hello", as: .english),
            .recognized
        )
        XCTAssertEqual(
            checker.recognitionStatus(for: "שלום", as: .hebrew),
            .recognized
        )
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

        XCTAssertEqual(
            recognizer.recognitionStatus(for: "HELLO", as: .english),
            .recognized
        )
        XCTAssertEqual(
            recognizer.recognitionStatus(for: "שלום", as: .hebrew),
            .recognized
        )
        XCTAssertEqual(
            recognizer.recognitionStatus(for: "unknown", as: .english),
            .unknown
        )

        let unavailable = StatusRecognizer(statuses: ["english:hello": .unavailable])
        let acceptingFallback = StatusRecognizer(statuses: ["english:hello": .recognized])
        let composite = CompositeWordRecognizer(primary: unavailable, fallback: acceptingFallback)

        XCTAssertEqual(
            composite.recognitionStatus(for: "HELLO", as: .english),
            .unavailable
        )
    }
}

private struct LocaleSpellCheckerBackend: SpellCheckerBackend {
    let availableLanguages: Set<String>
    let recognized: Set<String>
    let failed: Set<String>

    init(
        availableLanguages: Set<String> = ["en_US", "he_IL"],
        recognized: [(String, String)],
        failed: Set<String> = []
    ) {
        self.availableLanguages = availableLanguages
        self.recognized = Set(recognized.map { "\($0.1):\($0.0)" })
        self.failed = failed
    }

    func checkSpelling(in word: String, language: String) -> SpellingCheckResult {
        let key = "\(language):\(word)"
        if failed.contains(key) {
            return .init(
                misspelledRange: NSRange(location: NSNotFound, length: 0),
                wordCount: -1
            )
        }
        let range = recognized.contains(key)
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (word as NSString).length)
        return .init(misspelledRange: range, wordCount: 1)
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

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        recognized.contains("\(language.rawValue):\(word)") ? .recognized : .unknown
    }
}

private struct StatusRecognizer: WordRecognizing {
    let statuses: [String: RecognitionStatus]

    func recognitionStatus(for word: String, as language: Language) -> RecognitionStatus {
        statuses["\(language.rawValue):\(word)"] ?? .unknown
    }
}
