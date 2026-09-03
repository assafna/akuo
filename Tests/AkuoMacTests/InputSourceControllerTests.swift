import XCTest
import AkuoCore
@testable import AkuoMac

final class InputSourceControllerTests: XCTestCase {
    func testReadinessFindsABCAndStandardHebrew() {
        let controller = InputSourceController(
            backend: FakeInputSourceBackend(sources: Self.allSources)
        )

        XCTAssertEqual(
            controller.readiness,
            .init(englishAvailable: true, hebrewAvailable: true)
        )
    }

    func testEnglishDiscoveryPrefersABCOverUS() {
        let backend = FakeInputSourceBackend(sources: Self.allSources)
        let controller = InputSourceController(backend: backend)

        XCTAssertTrue(controller.select(.english))
        XCTAssertEqual(backend.selectedIdentifiers, ["com.apple.keylayout.ABC"])
    }

    func testEnglishDiscoveryFallsBackToUS() {
        let backend = FakeInputSourceBackend(
            sources: [
                .init(identifier: "com.apple.keylayout.US"),
                .init(identifier: "com.apple.keylayout.Hebrew"),
            ]
        )
        let controller = InputSourceController(backend: backend)

        XCTAssertTrue(controller.select(.english))
        XCTAssertEqual(backend.selectedIdentifiers, ["com.apple.keylayout.US"])
    }

    func testHebrewQWERTYDoesNotSatisfyStandardHebrewRequirement() {
        let controller = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: [.init(identifier: "com.apple.keylayout.Hebrew-QWERTY")]
            )
        )

        XCTAssertFalse(controller.readiness.hebrewAvailable)
        XCTAssertFalse(controller.select(.hebrew))
    }

    func testReadinessReportsMissingEnglishIndependently() {
        let controller = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: [.init(identifier: "com.apple.keylayout.Hebrew")]
            )
        )

        XCTAssertEqual(
            controller.readiness,
            .init(englishAvailable: false, hebrewAvailable: true)
        )
    }

    func testReadinessReportsMissingHebrewIndependently() {
        let controller = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: [.init(identifier: "com.apple.keylayout.ABC")]
            )
        )

        XCTAssertEqual(
            controller.readiness,
            .init(englishAvailable: true, hebrewAvailable: false)
        )
    }

    func testHebrewSelectionUsesStandardHebrewIdentifier() {
        let backend = FakeInputSourceBackend(sources: Self.allSources)
        let controller = InputSourceController(backend: backend)

        XCTAssertTrue(controller.select(.hebrew))
        XCTAssertEqual(backend.selectedIdentifiers, ["com.apple.keylayout.Hebrew"])
    }

    func testCurrentLanguageMapsOnlyApprovedSources() {
        let abc = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.ABC"
            )
        )
        let us = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.US"
            )
        )
        let hebrew = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.Hebrew"
            )
        )
        let phonetic = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.Hebrew-QWERTY"
            )
        )

        XCTAssertEqual(abc.currentLanguage, .english)
        XCTAssertEqual(us.currentLanguage, .english)
        XCTAssertEqual(hebrew.currentLanguage, .hebrew)
        XCTAssertNil(phonetic.currentLanguage)
    }

    func testCurrentSourcePreservesExactApprovedIdentifierAndLanguage() {
        let abc = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.ABC"
            )
        )
        let phonetic = InputSourceController(
            backend: FakeInputSourceBackend(
                sources: Self.allSources,
                currentIdentifier: "com.apple.keylayout.Hebrew-QWERTY"
            )
        )

        XCTAssertEqual(
            abc.currentSource,
            .init(identifier: "com.apple.keylayout.ABC", language: .english)
        )
        XCTAssertNil(phonetic.currentSource)
    }

    func testSuccessfulSelectionOriginIsSharedAcrossControllerCopiesAndConsumedOnce() {
        let now: TimeInterval = 100
        let originTracker = InputSourceSelectionOriginTracker(
            validityInterval: 1,
            now: { now }
        )
        let backend = FakeInputSourceBackend(
            sources: Self.allSources,
            currentIdentifier: "com.apple.keylayout.ABC"
        )
        let selectingController = InputSourceController(
            backend: backend,
            selectionOriginTracker: originTracker
        )
        let observingController = selectingController

        XCTAssertTrue(selectingController.select(.hebrew))
        XCTAssertTrue(observingController.consumeAkuoSelectionNotification())
        XCTAssertFalse(selectingController.consumeAkuoSelectionNotification())
    }

    func testFailedSelectionDoesNotArmAkuoSelectionOrigin() {
        let backend = FakeInputSourceBackend(
            sources: Self.allSources,
            currentIdentifier: "com.apple.keylayout.Hebrew",
            selectionResult: false
        )
        let controller = InputSourceController(backend: backend)

        XCTAssertFalse(controller.select(.hebrew))
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())
    }

    func testABCSelectionOriginRejectsAndClearsUSNotification() {
        let backend = FakeInputSourceBackend(
            sources: Self.allSources,
            currentIdentifier: "com.apple.keylayout.Hebrew"
        )
        let controller = InputSourceController(backend: backend)
        XCTAssertTrue(controller.select(.english))

        backend.currentIdentifier = "com.apple.keylayout.US"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())

        backend.currentIdentifier = "com.apple.keylayout.ABC"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())
    }

    func testUSSelectionOriginRejectsAndClearsABCNotification() {
        let backend = FakeInputSourceBackend(
            sources: [
                .init(identifier: "com.apple.keylayout.US"),
                .init(identifier: "com.apple.keylayout.Hebrew"),
            ],
            currentIdentifier: "com.apple.keylayout.Hebrew"
        )
        let controller = InputSourceController(backend: backend)
        XCTAssertTrue(controller.select(.english))

        backend.currentIdentifier = "com.apple.keylayout.ABC"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())

        backend.currentIdentifier = "com.apple.keylayout.US"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())
    }

    func testMismatchedCurrentLanguageRejectsAndClearsAkuoSelectionOrigin() {
        let backend = FakeInputSourceBackend(
            sources: Self.allSources,
            currentIdentifier: "com.apple.keylayout.ABC"
        )
        let controller = InputSourceController(backend: backend)
        XCTAssertTrue(controller.select(.hebrew))

        backend.currentIdentifier = "com.apple.keylayout.ABC"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())

        backend.currentIdentifier = "com.apple.keylayout.Hebrew"
        XCTAssertFalse(controller.consumeAkuoSelectionNotification())
    }

    func testExpiredAkuoSelectionOriginCannotPreserveLaterSourceChange() {
        var now: TimeInterval = 100
        let originTracker = InputSourceSelectionOriginTracker(
            validityInterval: 1,
            now: { now }
        )
        let backend = FakeInputSourceBackend(
            sources: Self.allSources,
            currentIdentifier: "com.apple.keylayout.ABC"
        )
        let controller = InputSourceController(
            backend: backend,
            selectionOriginTracker: originTracker
        )
        XCTAssertTrue(controller.select(.hebrew))

        now = 101.001

        XCTAssertFalse(controller.consumeAkuoSelectionNotification())
    }

    private static let allSources: [InputSourceDescriptor] = [
        .init(identifier: "com.apple.keylayout.Hebrew-QWERTY"),
        .init(identifier: "com.apple.keylayout.US"),
        .init(identifier: "com.apple.keylayout.Hebrew"),
        .init(identifier: "com.apple.keylayout.ABC"),
    ]
}

private final class FakeInputSourceBackend: InputSourceBackend {
    let sources: [InputSourceDescriptor]
    var currentIdentifier: String?
    let selectionResult: Bool
    private(set) var selectedIdentifiers: [String] = []

    init(
        sources: [InputSourceDescriptor],
        currentIdentifier: String? = nil,
        selectionResult: Bool = true
    ) {
        self.sources = sources
        self.currentIdentifier = currentIdentifier
        self.selectionResult = selectionResult
    }

    func select(identifier: String) -> Bool {
        selectedIdentifiers.append(identifier)
        if selectionResult {
            currentIdentifier = identifier
        }
        return selectionResult
    }
}
