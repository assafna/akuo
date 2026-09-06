import Foundation
import CoreGraphics
import XCTest
import AkuoCore
@testable import AkuoMac

final class SystemServiceContractTests: XCTestCase {
    func testWindowOrderingReturnsDistinctProcessesAheadOfActivationOwner() {
        let windows = [
            WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 71, layer: 5, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 42, layer: 0, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 99, layer: 0, alpha: 1),
        ]

        XCTAssertEqual(
            WindowProcessOrdering.processIdentifiersInFront(
                of: 42,
                excluding: 265,
                windows: windows,
                acceptedLevels: 0 ... 8
            ),
            [70, 71]
        )
    }

    func testWindowOrderingSkipsInvalidAlphaLevelsAndAkuoProcess() {
        let windows = [
            WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 0),
            WindowProcessSnapshot(processIdentifier: 71, layer: 8, alpha: .nan),
            WindowProcessSnapshot(processIdentifier: 72, layer: 9, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 265, layer: 8, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 73, layer: 8, alpha: 1),
            WindowProcessSnapshot(processIdentifier: 42, layer: 0, alpha: 1),
        ]

        XCTAssertEqual(
            WindowProcessOrdering.processIdentifiersInFront(
                of: 42,
                excluding: 265,
                windows: windows,
                acceptedLevels: 0 ... 8
            ),
            [73]
        )
    }

    func testWindowOrderingRejectsNonpositiveProcessIdentifiers() {
        XCTAssertEqual(WindowProcessOrdering.processIdentifiersInFront(
            of: 42, excluding: 265,
            windows: [
                .init(processIdentifier: 0, layer: 8, alpha: 1),
                .init(processIdentifier: -1, layer: 8, alpha: 1),
                .init(processIdentifier: 42, layer: 0, alpha: 1),
            ], acceptedLevels: 0 ... 8
        ), [])
    }

    func testWindowOrderingSystemProviderUsesExactAcceptedLevelBoundsOnce() {
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        let modal = Int(CGWindowLevelForKey(.modalPanelWindow))
        let bounds = min(normal, modal) ... max(normal, modal)
        var calls = 0
        let provider = SystemWindowProcessOrderingProvider(
            selfProcessIdentifier: 265,
            windowList: {
                calls += 1
                return [
                    windowMetadata(pid: 70, layer: bounds.lowerBound - 1, alpha: 1),
                    windowMetadata(pid: 71, layer: bounds.lowerBound, alpha: 1),
                    windowMetadata(pid: 72, layer: bounds.upperBound, alpha: 1),
                    windowMetadata(pid: 73, layer: bounds.upperBound + 1, alpha: 1),
                    windowMetadata(pid: 42, layer: bounds.lowerBound, alpha: 1),
                ]
            }, acceptedLevels: bounds
        )
        XCTAssertEqual(provider.processIdentifiersInFront(of: 42), [71, 72])
        XCTAssertEqual(calls, 1)
    }

    func testWindowOrderingReturnsNilWhenActivationOwnerHasNoAcceptedWindow() {
        XCTAssertNil(
            WindowProcessOrdering.processIdentifiersInFront(
                of: 42,
                excluding: 265,
                windows: [
                    WindowProcessSnapshot(processIdentifier: 70, layer: 8, alpha: 1),
                    WindowProcessSnapshot(processIdentifier: 42, layer: 9, alpha: 1),
                ],
                acceptedLevels: 0 ... 8
            )
        )
    }

    func testWindowOrderingReturnsEmptyListWhenActivationOwnerIsFirstAcceptedWindow() {
        XCTAssertEqual(
            WindowProcessOrdering.processIdentifiersInFront(
                of: 42,
                excluding: 265,
                windows: [
                    WindowProcessSnapshot(processIdentifier: 42, layer: 0, alpha: 1),
                ],
                acceptedLevels: 0 ... 8
            ),
            []
        )
    }

    func testWindowOrderingSystemProviderRejectsMalformedNumericMetadata() {
        let provider = SystemWindowProcessOrderingProvider(
            selfProcessIdentifier: 265,
            windowList: {
                [
                    windowMetadata(pid: true, layer: 8, alpha: 1),
                    windowMetadata(pid: Int64(Int32.max) + 1, layer: 8, alpha: 1),
                    windowMetadata(pid: 70, layer: 8.5, alpha: 1),
                    windowMetadata(pid: 71, layer: 8, alpha: Double.infinity),
                    windowMetadata(pid: 72, layer: 8, alpha: 1),
                    windowMetadata(pid: 42, layer: 0, alpha: 1),
                ]
            }
        )

        XCTAssertEqual(provider.processIdentifiersInFront(of: 42), [72])
    }

    func testWindowOrderingSystemProviderRejectsHighPrecisionFractionalIntegers() {
        let provider = SystemWindowProcessOrderingProvider(
            selfProcessIdentifier: 265,
            windowList: {
                [
                    windowMetadata(
                        pid: NSDecimalNumber(string: "42.0000000000000000001"),
                        layer: 8,
                        alpha: 1
                    ),
                    windowMetadata(
                        pid: 70,
                        layer: NSDecimalNumber(string: "8.0000000000000000001"),
                        alpha: 1
                    ),
                    windowMetadata(pid: 71, layer: 8, alpha: true),
                    windowMetadata(pid: 72, layer: 8, alpha: 1),
                    windowMetadata(pid: 42, layer: 0, alpha: 1),
                ]
            }
        )

        XCTAssertEqual(provider.processIdentifiersInFront(of: 42), [72])
    }

    func testWindowOrderingSystemProviderReturnsNilWhenWindowListIsUnavailable() {
        let provider = SystemWindowProcessOrderingProvider(
            selfProcessIdentifier: 265,
            windowList: { nil }
        )

        XCTAssertNil(provider.processIdentifiersInFront(of: 42))
    }

    func testInteractionContextUsesUniqueFocusedProcessAheadOfActivationOwner() {
        let accessibility = PerProcessAccessibilityFocusProvider(elements: [
            70: focusElement(identifier: "panel-search")
        ])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70]
            )
        )

        XCTAssertEqual(
            provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
            FocusContext(
                processIdentifier: 70,
                elementIdentifier: "panel-search",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
        XCTAssertEqual(accessibility.requestedProcessIdentifiers, [70])
    }

    func testInteractionContextSkipsStableAbsenceBeforeLaterFocusedCandidate() {
        let accessibility = SnapshotAccessibilityFocusProvider(snapshots: [
            70: .stablyAbsent,
            71: .focused(focusElement(identifier: "panel-search")),
        ])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(processIdentifiers: [70, 71])
        )

        XCTAssertEqual(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42)?.processIdentifier, 71)
        XCTAssertEqual(accessibility.requestedProcessIdentifiers, [70, 71])
    }

    func testInteractionContextFailsClosedForUnavailableAheadFocus() {
        let accessibility = SnapshotAccessibilityFocusProvider(snapshots: [70: .unavailable])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(processIdentifiers: [70])
        )

        XCTAssertNil(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42))
        XCTAssertEqual(accessibility.requestedProcessIdentifiers, [70])
    }

    func testInteractionContextRejectsAheadProcessBudgetOverflowBeforeAXScanning() {
        let accessibility = SnapshotAccessibilityFocusProvider(snapshots: [:])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70, 71, 72, 73, 74]
            )
        )

        XCTAssertNil(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42))
        XCTAssertTrue(accessibility.requestedProcessIdentifiers.isEmpty)
    }

    func testInteractionContextRejectsDuplicateOrderingOutputBeforeAXScanning() {
        let accessibility = SnapshotAccessibilityFocusProvider(snapshots: [:])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70, 70, 70, 70, 70]
            )
        )

        XCTAssertNil(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42))
        XCTAssertTrue(accessibility.requestedProcessIdentifiers.isEmpty)
    }

    func testInteractionContextFallsBackWhenAheadProcessesHaveNoFocusedElement() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: PerProcessAccessibilityFocusProvider(elements: [
                42: focusElement(identifier: "owner-field")
            ]),
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70]
            )
        )

        XCTAssertEqual(
            provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
            FocusContext(
                processIdentifier: 42,
                elementIdentifier: "owner-field",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
    }

    func testInteractionContextFallsBackToActivationOwnerForSuccessfulEmptyOrdering() {
        let accessibility = PerProcessAccessibilityFocusProvider(elements: [
            42: focusElement(identifier: "owner-field")
        ])
        let ordering = FakeWindowProcessOrderingProvider(processIdentifiers: [])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: ordering
        )

        XCTAssertEqual(
            provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
            FocusContext(
                processIdentifier: 42,
                elementIdentifier: "owner-field",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
        XCTAssertEqual(ordering.activationOwnerRequests, [42])
        XCTAssertEqual(accessibility.requestedProcessIdentifiers, [42])
    }

    func testInteractionContextReturnsNilForTwoFocusedProcessesAheadOfActivationOwner() {
        let accessibility = PerProcessAccessibilityFocusProvider(elements: [
            70: focusElement(identifier: "panel-search"),
            71: focusElement(identifier: "modal-search"),
            72: focusElement(identifier: "unexamined-search"),
        ])
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70, 71, 72]
            )
        )

        XCTAssertNil(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42))
        XCTAssertEqual(accessibility.requestedProcessIdentifiers, [70, 71])
    }

    func testInteractionContextReturnsSecureFocusedProcessAheadOfActivationOwner() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: PerProcessAccessibilityFocusProvider(elements: [
                42: focusElement(identifier: "owner-field"),
                70: focusElement(identifier: "secure-field", role: "AXSecureTextField"),
            ]),
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70]
            )
        )

        XCTAssertEqual(
            provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
            FocusContext(
                processIdentifier: 70,
                elementIdentifier: "secure-field",
                isSecureField: true,
                isEditableTextInput: false
            )
        )
    }

    func testInteractionContextReturnsReadOnlyFocusedProcessAheadOfActivationOwner() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: PerProcessAccessibilityFocusProvider(elements: [
                42: focusElement(identifier: "owner-field"),
                70: focusElement(identifier: "read-only", isValueSettable: false),
            ]),
            windowProcessOrderingProvider: FakeWindowProcessOrderingProvider(
                processIdentifiers: [70]
            )
        )

        XCTAssertEqual(
            provider.currentInteractionContext(activationOwnerProcessIdentifier: 42),
            FocusContext(
                processIdentifier: 70,
                elementIdentifier: "read-only",
                isSecureField: false,
                isEditableTextInput: false
            )
        )
    }

    func testInteractionContextReturnsNilWhenWindowOrderingFails() {
        let accessibility = PerProcessAccessibilityFocusProvider(elements: [
            42: focusElement(identifier: "owner-field")
        ])
        let ordering = FakeWindowProcessOrderingProvider(processIdentifiers: nil)
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: ordering
        )

        XCTAssertNil(provider.currentInteractionContext(activationOwnerProcessIdentifier: 42))
        XCTAssertEqual(ordering.activationOwnerRequests, [42])
        XCTAssertTrue(accessibility.requestedProcessIdentifiers.isEmpty)
    }

    func testInteractionContextUsesStableFrontmostAfterExplicitResolution() {
        let timeline = ResolutionTimeline()
        let frontmost = TimelineFrontmostProcessProvider(
            processIdentifier: 42,
            timeline: timeline
        )
        let accessibility = PerProcessAccessibilityFocusProvider(
            elements: [42: focusElement(identifier: "owner-field")],
            onFocusedElementRequest: { processIdentifier in
                timeline.record("accessibility:\(processIdentifier)")
            }
        )
        let ordering = FakeWindowProcessOrderingProvider(
            processIdentifiers: [],
            onRequest: { processIdentifier in
                timeline.record("ordering:\(processIdentifier)")
            }
        )
        let provider = FocusContextProvider(
            frontmostProcessProvider: frontmost,
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: ordering
        )

        XCTAssertEqual(
            provider.currentInteractionContext(),
            FocusContext(
                processIdentifier: 42,
                elementIdentifier: "owner-field",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
        XCTAssertEqual(timeline.events, [
            "frontmost:42",
            "ordering:42",
            "accessibility:42",
            "frontmost:42",
        ])
    }

    func testInteractionContextRejectsFrontmostProcessChangeAfterExplicitResolution() {
        let timeline = ResolutionTimeline()
        let frontmost = TimelineFrontmostProcessProvider(
            processIdentifier: 42,
            timeline: timeline
        )
        let accessibility = PerProcessAccessibilityFocusProvider(
            elements: [42: focusElement(identifier: "owner-field")],
            onFocusedElementRequest: { processIdentifier in
                timeline.record("accessibility:\(processIdentifier)")
            }
        )
        let ordering = FakeWindowProcessOrderingProvider(
            processIdentifiers: [],
            onRequest: { processIdentifier in
                timeline.record("ordering:\(processIdentifier)")
                frontmost.processIdentifier = 43
            }
        )
        let provider = FocusContextProvider(
            frontmostProcessProvider: frontmost,
            accessibilityProvider: accessibility,
            windowProcessOrderingProvider: ordering
        )

        XCTAssertNil(provider.currentInteractionContext())
        XCTAssertEqual(timeline.events, [
            "frontmost:42",
            "ordering:42",
            "accessibility:42",
            "frontmost:43",
        ])
    }

    func testAccessibilityTextMatcherComputesOnlyRangeBeforeCollapsedCaret() {
        let value = "prefix 😀 שמג "
        let caretAtEnd = NSRange(
            location: (value as NSString).length,
            length: 0
        )

        XCTAssertEqual(AccessibilityTextMatcher.precedingRange(
            selectedRange: caretAtEnd,
            expectedText: "שמג "
        ), NSRange(location: 10, length: 4))
        XCTAssertNil(AccessibilityTextMatcher.precedingRange(
            selectedRange: NSRange(location: 3, length: 0),
            expectedText: "שמג "
        ))
        XCTAssertNil(AccessibilityTextMatcher.precedingRange(
            selectedRange: NSRange(location: caretAtEnd.location, length: 1),
            expectedText: "שמג "
        ))
    }

    func testFocusContextPreviousTextValidationFailsClosedAfterReturnSubmission() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "field",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: true
                ),
                previousTextMatches: false
            )
        )
        let context = FocusContext(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )

        XCTAssertFalse(provider.hasExactTextImmediatelyBeforeCaret(
            "שמג\r",
            context: context
        ))
    }

    func testFocusContextReturnsOnlyRequestedTextBeforeStableEditableCaret() {
        let context = FocusContext(
            processIdentifier: 42,
            elementIdentifier: "field",
            isSecureField: false,
            isEditableTextInput: true
        )
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 42),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "field",
                    role: "AXTextField",
                    subrole: .absent,
                    isEnabled: .value(true),
                    isValueSettable: true
                ),
                precedingText: "akuo"
            )
        )

        XCTAssertEqual(
            provider.textImmediatelyBeforeCaret(utf16Length: 4, context: context),
            "akuo"
        )
    }

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

        XCTAssertEqual(provider.focusSnapshot(for: 42), .unavailable)
    }

    func testSystemFocusProviderRejectsFocusChangeDuringEvidenceCollection() {
        let first = AXUIElementCreateApplication(42)
        let second = AXUIElementCreateApplication(43)
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [first, second])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        XCTAssertEqual(provider.focusSnapshot(for: 42), .unavailable)
    }

    func testSystemFocusProviderRejectsMalformedFinalFocusSnapshot() {
        let element = AXUIElementCreateApplication(42)
        let reader = ScriptedAccessibilityAttributeReader(focusedElementValues: [
            element,
            kCFBooleanTrue,
        ])
        let provider = SystemAccessibilityFocusProvider(reader: reader)

        XCTAssertEqual(provider.focusSnapshot(for: 42), .unavailable)
    }

    func testSystemFocusProviderRequiresTwoDefinitiveAbsenceReads() {
        let provider = SystemAccessibilityFocusProvider(reader: FocusSnapshotReader([
            .init(result: .noValue, value: nil),
            .init(result: .noValue, value: nil),
        ]))

        XCTAssertEqual(provider.focusSnapshot(for: 42), .stablyAbsent)
    }

    func testSystemFocusProviderTreatsCannotCompleteAndTimeoutAsUnavailable() {
        let cannotComplete = SystemAccessibilityFocusProvider(reader: FocusSnapshotReader([
            .init(result: .cannotComplete, value: nil),
        ]))
        let timeout = SystemAccessibilityFocusProvider(
            reader: FocusSnapshotReader([]),
            configureMessagingTimeout: { _, _ in .cannotComplete }
        )

        XCTAssertEqual(cannotComplete.focusSnapshot(for: 42), .unavailable)
        XCTAssertEqual(timeout.focusSnapshot(for: 42), .unavailable)
    }

    func testCallbackBudgetUsesOneMonotonicDeadlineAndShrinksPreparationTimeout() {
        var now: TimeInterval = 0
        var timeouts: [Float] = []
        let provider = SystemAccessibilityFocusProvider(
            reader: FocusSnapshotReader([]),
            configureMessagingTimeout: { _, timeout in timeouts.append(timeout); return .success },
            now: { now }
        )
        let end = provider.beginCallbackBudget()
        now = 0.098
        XCTAssertEqual(provider.focusSnapshot(for: 42), .stablyAbsent)
        now = 0.101
        XCTAssertEqual(provider.focusSnapshot(for: 42), .unavailable)
        end()
        XCTAssertEqual(timeouts.count, 1)
        XCTAssertLessThan(timeouts[0], 0.005)
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

    func testSystemFocusProviderValidatesExactTextAgainstStableElementAndCaret() {
        let element = AXUIElementCreateApplication(42)
        let value = "prefix go "
        var caret = CFRange(location: (value as NSString).length, length: 0)
        guard let caretValue = AXValueCreate(.cfRange, &caret) else {
            return XCTFail("Expected AX caret range")
        }
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "go " as CFString,
            selectedTextRangeValues: [caretValue, caretValue]
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader)
        guard let snapshot = provider.focusedElement(for: 42) else {
            return XCTFail("Expected focused element snapshot")
        }

        XCTAssertTrue(provider.hasExactTextImmediatelyBeforeCaret(
            "go ",
            processIdentifier: 42,
            elementIdentifier: snapshot.identifier
        ))
        XCTAssertEqual(reader.parameterizedRanges, [
            NSRange(location: 7, length: 3),
        ])
    }

    func testExactSuffixTextReadPreparesApplicationAndFocusedElementBeforeIPC() {
        let element = AXUIElementCreateApplication(43)
        var caret = CFRange(location: 3, length: 0)
        let caretValue = AXValueCreate(.cfRange, &caret)!
        let timeline = AccessibilityTimeline()
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "go " as CFString,
            selectedTextRangeValues: [caretValue, caretValue],
            onRead: { timeline.record(readEvent($0, $1)) }
        )
        let provider = SystemAccessibilityFocusProvider(
            reader: reader,
            configureMessagingTimeout: { element, _ in
                timeline.record("prepare:\(elementPID(element))")
                return .success
            }
        )
        let identifier = provider.focusedElement(for: 42)!.identifier
        timeline.reset()

        XCTAssertTrue(provider.hasExactTextImmediatelyBeforeCaret(
            "go ", processIdentifier: 42, elementIdentifier: identifier
        ))
        XCTAssertEqual(timeline.events, [
            "prepare:42", "focused:42", "prepare:43", "selected:43",
            "parameterized:43", "selected:43", "focused:42",
        ])
    }

    func testRecoveryTextReadPreparesApplicationAndFocusedElementBeforeIPC() {
        let element = AXUIElementCreateApplication(43)
        var caret = CFRange(location: 3, length: 0)
        let caretValue = AXValueCreate(.cfRange, &caret)!
        let timeline = AccessibilityTimeline()
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "go " as CFString,
            selectedTextRangeValues: [caretValue, caretValue],
            onRead: { timeline.record(readEvent($0, $1)) }
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader, configureMessagingTimeout: { element, _ in
            timeline.record("prepare:\(elementPID(element))"); return .success
        })
        let identifier = provider.focusedElement(for: 42)!.identifier
        timeline.reset()

        XCTAssertEqual(provider.textImmediatelyBeforeCaret(
            utf16Length: 3, processIdentifier: 42, elementIdentifier: identifier
        ), "go ")
        XCTAssertEqual(timeline.events.prefix(3), ["prepare:42", "focused:42", "prepare:43"])
    }

    func testTextReadPreparationFailureStopsBeforeIPC() {
        let timeline = AccessibilityTimeline()
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [],
            onRead: { timeline.record(readEvent($0, $1)) }
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader, configureMessagingTimeout: { _, _ in .cannotComplete })

        XCTAssertFalse(provider.hasExactTextImmediatelyBeforeCaret(
            "go ", processIdentifier: 42, elementIdentifier: "field"
        ))
        XCTAssertNil(provider.textImmediatelyBeforeCaret(
            utf16Length: 3, processIdentifier: 42, elementIdentifier: "field"
        ))
        XCTAssertTrue(timeline.events.isEmpty)
    }

    func testSystemFocusProviderReturnsRequestedRecoverySpanAtDocumentStart() {
        let element = AXUIElementCreateApplication(42)
        let value = "akuo"
        var caret = CFRange(location: (value as NSString).length, length: 0)
        guard let caretValue = AXValueCreate(.cfRange, &caret) else {
            return XCTFail("Expected AX caret range")
        }
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "akuo" as CFString,
            selectedTextRangeValues: [caretValue, caretValue]
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader)
        guard let snapshot = provider.focusedElement(for: 42) else {
            return XCTFail("Expected focused element snapshot")
        }

        XCTAssertEqual(provider.textImmediatelyBeforeCaret(
            utf16Length: 4,
            processIdentifier: 42,
            elementIdentifier: snapshot.identifier
        ), "akuo")
        XCTAssertEqual(reader.parameterizedRanges, [
            NSRange(location: 0, length: 4),
        ])
    }

    func testSystemFocusProviderRejectsRecoverySpanInsideLargerToken() {
        let element = AXUIElementCreateApplication(42)
        let value = "xakuo"
        var caret = CFRange(location: (value as NSString).length, length: 0)
        guard let caretValue = AXValueCreate(.cfRange, &caret) else {
            return XCTFail("Expected AX caret range")
        }
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "akuo" as CFString,
            selectedTextRangeValues: [caretValue, caretValue]
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader)
        guard let snapshot = provider.focusedElement(for: 42) else {
            return XCTFail("Expected focused element snapshot")
        }

        XCTAssertNil(provider.textImmediatelyBeforeCaret(
            utf16Length: 4,
            processIdentifier: 42,
            elementIdentifier: snapshot.identifier
        ))
        XCTAssertTrue(reader.parameterizedRanges.isEmpty)
    }

    func testSystemFocusProviderRejectsCaretMovementDuringTextValidation() {
        let element = AXUIElementCreateApplication(42)
        var initialCaret = CFRange(location: 10, length: 0)
        var movedCaret = CFRange(location: 4, length: 0)
        guard let initialCaretValue = AXValueCreate(.cfRange, &initialCaret),
              let movedCaretValue = AXValueCreate(.cfRange, &movedCaret) else {
            return XCTFail("Expected AX caret ranges")
        }
        let reader = ScriptedAccessibilityAttributeReader(
            focusedElementValues: [element, element, element, element],
            parameterizedTextValue: "go " as CFString,
            selectedTextRangeValues: [initialCaretValue, movedCaretValue]
        )
        let provider = SystemAccessibilityFocusProvider(reader: reader)
        guard let snapshot = provider.focusedElement(for: 42) else {
            return XCTFail("Expected focused element snapshot")
        }

        XCTAssertFalse(provider.hasExactTextImmediatelyBeforeCaret(
            "go ",
            processIdentifier: 42,
            elementIdentifier: snapshot.identifier
        ))
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

    func testFocusContextCanInspectEventTargetProcessWithoutActivation() {
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 7),
            accessibilityProvider: FakeAccessibilityFocusProvider(
                element: .init(
                    identifier: "panel-search",
                    role: "AXTextField",
                    subrole: .value("raycast_searchField"),
                    isEnabled: .value(true),
                    isValueSettable: true
                )
            )
        )

        XCTAssertEqual(
            provider.current(processIdentifier: 42),
            .init(
                processIdentifier: 42,
                elementIdentifier: "panel-search",
                isSecureField: false,
                isEditableTextInput: true
            )
        )
    }

    func testExactTextValidationUsesContextProcessRatherThanActivatedProcess() {
        let accessibility = FakeAccessibilityFocusProvider(
            element: nil,
            previousTextMatches: true
        )
        let provider = FocusContextProvider(
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifier: 7),
            accessibilityProvider: accessibility
        )
        let context = FocusContext(
            processIdentifier: 42,
            elementIdentifier: "panel-search",
            isSecureField: false,
            isEditableTextInput: true
        )

        XCTAssertTrue(provider.hasExactTextImmediatelyBeforeCaret(
            "akuo ",
            context: context
        ))
        XCTAssertEqual(accessibility.exactTextProcessIdentifiers, [42])
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

private func windowMetadata(pid: Any, layer: Any, alpha: Any) -> [String: Any] {
    [
        kCGWindowOwnerPID as String: pid,
        kCGWindowLayer as String: layer,
        kCGWindowAlpha as String: alpha,
    ]
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

private final class FakeWindowProcessOrderingProvider: WindowProcessOrderingProviding {
    let processIdentifiers: [Int32]?
    let onRequest: ((Int32) -> Void)?
    private(set) var activationOwnerRequests: [Int32] = []

    init(
        processIdentifiers: [Int32]?,
        onRequest: ((Int32) -> Void)? = nil
    ) {
        self.processIdentifiers = processIdentifiers
        self.onRequest = onRequest
    }

    func processIdentifiersInFront(of activationOwner: Int32) -> [Int32]? {
        activationOwnerRequests.append(activationOwner)
        onRequest?(activationOwner)
        return processIdentifiers
    }
}

private final class ResolutionTimeline {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private final class TimelineFrontmostProcessProvider: FrontmostProcessProviding {
    private var currentProcessIdentifier: Int32?
    private let timeline: ResolutionTimeline

    init(processIdentifier: Int32?, timeline: ResolutionTimeline) {
        currentProcessIdentifier = processIdentifier
        self.timeline = timeline
    }

    var processIdentifier: Int32? {
        get {
            timeline.record("frontmost:\(currentProcessIdentifier.map(String.init) ?? "nil")")
            return currentProcessIdentifier
        }
        set {
            currentProcessIdentifier = newValue
        }
    }
}

private final class PerProcessAccessibilityFocusProvider: AccessibilityFocusProviding {
    let elements: [Int32: AccessibilityFocusElement]
    let onFocusedElementRequest: ((Int32) -> Void)?
    private(set) var requestedProcessIdentifiers: [Int32] = []

    init(
        elements: [Int32: AccessibilityFocusElement],
        onFocusedElementRequest: ((Int32) -> Void)? = nil
    ) {
        self.elements = elements
        self.onFocusedElementRequest = onFocusedElementRequest
    }

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        requestedProcessIdentifiers.append(processIdentifier)
        onFocusedElementRequest?(processIdentifier)
        return elements[processIdentifier]
    }

    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> Bool {
        false
    }
}

private final class SnapshotAccessibilityFocusProvider: AccessibilityFocusProviding {
    let snapshots: [Int32: AccessibilityFocusSnapshot]
    private(set) var requestedProcessIdentifiers: [Int32] = []

    init(snapshots: [Int32: AccessibilityFocusSnapshot]) {
        self.snapshots = snapshots
    }

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        guard case let .focused(element) = focusSnapshot(for: processIdentifier) else {
            return nil
        }
        return element
    }

    func focusSnapshot(for processIdentifier: Int32) -> AccessibilityFocusSnapshot {
        requestedProcessIdentifiers.append(processIdentifier)
        return snapshots[processIdentifier] ?? .stablyAbsent
    }

    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> Bool {
        false
    }
}

private func focusElement(
    identifier: String,
    role: String = "AXTextField",
    isValueSettable: Bool? = true
) -> AccessibilityFocusElement {
    .init(
        identifier: identifier,
        role: role,
        subrole: .absent,
        isEnabled: .value(true),
        isValueSettable: isValueSettable
    )
}

private final class FakeAccessibilityFocusProvider: AccessibilityFocusProviding {
    let element: AccessibilityFocusElement?
    var previousTextMatches = false
    var precedingText: String?
    private(set) var exactTextProcessIdentifiers: [Int32] = []

    init(
        element: AccessibilityFocusElement?,
        previousTextMatches: Bool = false,
        precedingText: String? = nil
    ) {
        self.element = element
        self.previousTextMatches = previousTextMatches
        self.precedingText = precedingText
    }

    func focusedElement(for processIdentifier: Int32) -> AccessibilityFocusElement? {
        element
    }

    func hasExactTextImmediatelyBeforeCaret(
        _ expectedText: String,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> Bool {
        exactTextProcessIdentifiers.append(processIdentifier)
        return previousTextMatches
    }

    func textImmediatelyBeforeCaret(
        utf16Length: Int,
        processIdentifier: Int32,
        elementIdentifier: String
    ) -> String? {
        precedingText
    }
}

private final class FocusSnapshotReader: AccessibilityAttributeReading {
    private var focusReads: [AccessibilityAttributeRead]

    init(_ focusReads: [AccessibilityAttributeRead]) {
        self.focusReads = focusReads
    }

    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead {
        if attribute == kAXFocusedUIElementAttribute {
            guard !focusReads.isEmpty else { return .init(result: .noValue, value: nil) }
            return focusReads.removeFirst()
        }
        return .init(result: .attributeUnsupported, value: nil)
    }

    func parameterizedAttribute(
        _ attribute: String,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead {
        .init(result: .attributeUnsupported, value: nil)
    }

    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool? {
        nil
    }
}

private final class ScriptedAccessibilityAttributeReader: AccessibilityAttributeReading {
    private var focusedElementValues: [CFTypeRef?]
    private let parameterizedTextValue: CFTypeRef?
    private var selectedTextRangeValues: [CFTypeRef?]
    private let onRead: ((String, AXUIElement) -> Void)?
    private(set) var parameterizedRanges: [NSRange] = []

    init(
        focusedElementValues: [CFTypeRef?],
        parameterizedTextValue: CFTypeRef? = nil,
        selectedTextRangeValues: [CFTypeRef?] = [],
        onRead: ((String, AXUIElement) -> Void)? = nil
    ) {
        self.focusedElementValues = focusedElementValues
        self.parameterizedTextValue = parameterizedTextValue
        self.selectedTextRangeValues = selectedTextRangeValues
        self.onRead = onRead
    }

    func attribute(_ attribute: String, of element: AXUIElement) -> AccessibilityAttributeRead {
        onRead?(attribute, element)
        switch attribute {
        case kAXFocusedUIElementAttribute:
            guard !focusedElementValues.isEmpty else {
                return .init(result: .noValue, value: nil)
            }
            return .init(result: .success, value: focusedElementValues.removeFirst())
        case kAXRoleAttribute:
            return .init(result: .success, value: "AXTextArea" as CFString)
        case kAXSelectedTextRangeAttribute:
            guard !selectedTextRangeValues.isEmpty else {
                return .init(result: .noValue, value: nil)
            }
            return .init(result: .success, value: selectedTextRangeValues.removeFirst())
        case kAXSubroleAttribute, kAXEnabledAttribute:
            return .init(result: .attributeUnsupported, value: nil)
        default:
            return .init(result: .attributeUnsupported, value: nil)
        }
    }

    func parameterizedAttribute(
        _ attribute: String,
        parameter: CFTypeRef,
        of element: AXUIElement
    ) -> AccessibilityAttributeRead {
        onRead?(attribute, element)
        guard attribute == kAXStringForRangeParameterizedAttribute,
              let range = AccessibilityAttributeDecoder.range(from: parameter) else {
            return .init(result: .parameterizedAttributeUnsupported, value: nil)
        }
        parameterizedRanges.append(range)
        return .init(
            result: parameterizedTextValue == nil ? .noValue : .success,
            value: parameterizedTextValue
        )
    }

    func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool? {
        attribute == kAXValueAttribute ? true : nil
    }
}

private final class AccessibilityTimeline {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func reset() { events.removeAll() }
}

private func elementPID(_ element: AXUIElement) -> Int32 {
    var pid: pid_t = 0
    _ = AXUIElementGetPid(element, &pid)
    return Int32(pid)
}

private func readEvent(_ attribute: String, _ element: AXUIElement) -> String {
    let name: String
    switch attribute {
    case kAXFocusedUIElementAttribute: name = "focused"
    case kAXSelectedTextRangeAttribute: name = "selected"
    case kAXStringForRangeParameterizedAttribute: name = "parameterized"
    default: name = "other"
    }
    return "\(name):\(elementPID(element))"
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
