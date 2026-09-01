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

    func testAccessibilityBooleanDecoderRequiresAnActualCFBoolean() {
        XCTAssertEqual(
            AccessibilityAttributeDecoder.boolean(from: kCFBooleanTrue),
            true
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.boolean(from: kCFBooleanFalse),
            false
        )
        XCTAssertNil(
            AccessibilityAttributeDecoder.boolean(from: NSNumber(value: 1) as CFTypeRef)
        )
        XCTAssertNil(
            AccessibilityAttributeDecoder.boolean(from: NSNumber(value: 0) as CFTypeRef)
        )
        XCTAssertNil(
            AccessibilityAttributeDecoder.boolean(from: "true" as CFString)
        )
    }

    func testAccessibilityElementDecoderRejectsMalformedFocusedElementValues() {
        let element = AXUIElementCreateApplication(42)

        guard let decoded = AccessibilityAttributeDecoder.element(from: element) else {
            return XCTFail("Expected an AXUIElement value to decode")
        }
        XCTAssertTrue(CFEqual(decoded, element))
        XCTAssertNil(AccessibilityAttributeDecoder.element(from: "AXTextField" as CFString))
        XCTAssertNil(AccessibilityAttributeDecoder.element(from: kCFBooleanTrue))
        XCTAssertNil(AccessibilityAttributeDecoder.element(from: nil))
    }

    func testAccessibilityOptionalBooleanDecoderDistinguishesAbsenceFromUnknown() {
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalBoolean(
                result: .success,
                value: kCFBooleanTrue
            ),
            .value(true)
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalBoolean(
                result: .success,
                value: kCFBooleanFalse
            ),
            .value(false)
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalBoolean(
                result: .attributeUnsupported,
                value: nil
            ),
            .absent
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalBoolean(result: .noValue, value: nil),
            .absent
        )

        for result in [AXError.cannotComplete, .invalidUIElement] {
            XCTAssertEqual(
                AccessibilityAttributeDecoder.optionalBoolean(result: result, value: nil),
                .unknown,
                "result=\(result.rawValue)"
            )
        }
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalBoolean(
                result: .success,
                value: NSNumber(value: 1) as CFTypeRef
            ),
            .unknown
        )
    }

    func testAccessibilityOptionalStringDecoderDistinguishesAbsenceFromUnknown() {
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalString(
                result: .success,
                value: "AXSecureTextField" as CFString
            ),
            .value("AXSecureTextField")
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalString(result: .noValue, value: nil),
            .absent
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalString(
                result: .attributeUnsupported,
                value: nil
            ),
            .absent
        )

        for result in [AXError.cannotComplete, .invalidUIElement] {
            XCTAssertEqual(
                AccessibilityAttributeDecoder.optionalString(result: result, value: nil),
                .unknown,
                "result=\(result.rawValue)"
            )
        }
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalString(
                result: .success,
                value: NSNumber(value: 1) as CFTypeRef
            ),
            .unknown
        )
        XCTAssertEqual(
            AccessibilityAttributeDecoder.optionalString(
                result: .success,
                value: kAXUnknownSubrole as CFString
            ),
            .unknown
        )
    }

    func testSystemFocusProviderRejectsMalformedFocusedElementValue() {
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [
            "AXTextArea" as CFString,
        ])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        XCTAssertNil(provider.focusedElement(for: 42))
    }

    func testSystemFocusProviderRejectsFocusChangeDuringEvidenceCollection() {
        let first = AXUIElementCreateApplication(42)
        let second = AXUIElementCreateApplication(43)
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [first, second])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        XCTAssertNil(provider.focusedElement(for: 42))
    }

    func testSystemFocusProviderRejectsMalformedFinalFocusSnapshot() {
        let element = AXUIElementCreateApplication(42)
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [
            element,
            kCFBooleanTrue,
        ])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        XCTAssertNil(provider.focusedElement(for: 42))
    }

    func testSystemFocusProviderUsesStableOpaqueIdentityForEqualElements() {
        let first = AXUIElementCreateApplication(42)
        let second = AXUIElementCreateApplication(43)
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [
            first, first,
            first, first,
            second, second,
        ])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        let firstSnapshot = provider.focusedElement(for: 42)
        let repeatedSnapshot = provider.focusedElement(for: 42)
        let changedSnapshot = provider.focusedElement(for: 43)

        XCTAssertNotNil(firstSnapshot)
        XCTAssertEqual(firstSnapshot?.identifier, repeatedSnapshot?.identifier)
        XCTAssertNotEqual(firstSnapshot?.identifier, changedSnapshot?.identifier)
    }

    func testTextEditDocumentShapeWithUnsupportedOptionalMetadataIsEditable() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "textedit-editor",
                    role: "AXTextArea",
                    subrole: AccessibilityAttributeDecoder.optionalString(
                        result: .attributeUnsupported,
                        value: nil
                    ),
                    isEnabled: .absent,
                    isValueSettable: true
                )
            )
        )

        XCTAssertEqual(provider.current()?.isEditableTextInput, true)
    }

    func testFocusContextIncludesFrontmostProcessAndFocusedElement() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "element-1",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: true
                )
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

    func testFrontmostProcessChangeDuringInspectionReturnsNoFocusContext() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: ScriptedFrontmostProcessProvider([42, 43]),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "element-1",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: true
                )
            )
        )

        XCTAssertNil(provider.current())
    }

    func testOnlyNarrowTextEntryRoleAllowlistIsEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            let provider = FocusContextProvider(
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
                accessibilityProvider: FakeAccessibilityFocusProvider(
                    element: .init(
                        identifier: role,
                        role: role,
                        subrole: .absent,
                        isEnabled: .value(true),
                        isValueSettable: true
                    )
                )
            )

            XCTAssertEqual(provider.current()?.isEditableTextInput, true, role)
        }
    }

    func testDisabledTextEntryRoleIsIneligible() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "disabled",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(false),
                    isValueSettable: true
                )
            )
        )

        XCTAssertEqual(provider.current()?.isEditableTextInput, false)
    }

    func testReadOnlyTextEntryRoleIsIneligible() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "read-only",
                    role: "AXTextArea",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: false
                )
            )
        )

        XCTAssertEqual(provider.current()?.isEditableTextInput, false)
    }

    func testUnknownEditabilityEvidenceIsIneligible() {
        let evidence: [(isEnabled: AccessibilityOptionalBoolean, isValueSettable: Bool?)] = [
            (.unknown, true),
            (.value(true), nil),
            (.absent, nil),
        ]

        for (isEnabled, isValueSettable) in evidence {
            let provider = FocusContextProvider(
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
                accessibilityProvider: FakeAccessibilityFocusProvider(
                    element: .init(
                        identifier: "unknown",
                        role: "AXComboBox",
                        subrole: .absent,
                        isEnabled: isEnabled,
                        isValueSettable: isValueSettable
                    )
                )
            )

            XCTAssertEqual(
                provider.current()?.isEditableTextInput,
                false,
                "enabled=\(String(describing: isEnabled)), settable=\(String(describing: isValueSettable))"
            )
        }
    }

    func testUnknownSubroleEvidenceIsIneligible() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "unknown-subrole",
                    role: "AXTextField",
                    subrole: .unknown,
                    isEnabled: .value(true),
                    isValueSettable: true
                )
            )
        )

        XCTAssertEqual(provider.current()?.isEditableTextInput, false)
    }

    func testNonTextAndUnknownRolesAreIneligible() {
        for role in ["AXList", "AXOutline", "AXRow", "AXStaticText", nil] {
            let provider = FocusContextProvider(
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
                accessibilityProvider: FakeAccessibilityFocusProvider(
                    element: .init(
                        identifier: "control",
                        role: role,
                        subrole: .absent,
                        isEnabled: .value(true),
                        isValueSettable: true
                    )
                )
            )

            XCTAssertEqual(provider.current()?.isEditableTextInput, false, role ?? "missing role")
        }
    }

    func testSecureTextFieldRoleMarksFocusContextSecure() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "secret",
                    role: "AXSecureTextField",
                    subrole: .unknown,
                    isEnabled: .value(true),
                    isValueSettable: true
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

    func testSecureTextFieldSubroleMarksFocusContextSecure() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "secret",
                    role: "AXTextField",
                    subrole: .value("AXSecureTextField"),
                    isEnabled: .value(true),
                    isValueSettable: true
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
                element: .init(
                    identifier: "ignored",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: true
                )
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

private final class ScriptedFrontmostProcessProvider: FrontmostProcessProviding {
    private var processIdentifiers: [Int32?]

    init(_ processIdentifiers: [Int32?]) {
        self.processIdentifiers = processIdentifiers
    }

    var processIdentifier: Int32? {
        guard processIdentifiers.count > 1 else {
            return processIdentifiers.first ?? nil
        }
        return processIdentifiers.removeFirst()
    }
}

private struct FakeAccessibilityFocusProvider: AccessibilityFocusProviding {
    let element: AccessibilityFocusElement?

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        element
    }
}

private final class ScriptedAccessibilityAttributeReader: AccessibilityAttributeReading {
    private var focusedElementValues: [CFTypeRef?]

    init(focusedElementValues: [CFTypeRef?]) {
        self.focusedElementValues = focusedElementValues
    }

    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead {
        switch attribute {
        case kAXFocusedUIElementAttribute:
            guard !focusedElementValues.isEmpty else {
                return .init(result: .noValue, value: nil)
            }
            return .init(result: .success, value: focusedElementValues.removeFirst())
        case kAXRoleAttribute:
            return .init(result: .success, value: "AXTextArea" as CFString)
        case kAXSubroleAttribute, kAXEnabledAttribute:
            return .init(result: .attributeUnsupported, value: nil)
        default:
            return .init(result: .attributeUnsupported, value: nil)
        }
    }

    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool? {
        attribute == kAXValueAttribute ? true : nil
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
