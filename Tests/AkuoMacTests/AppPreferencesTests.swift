import Combine
import Foundation
import XCTest
@testable import AkuoMac

final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsArePrivateAndInactive() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertFalse(preferences.onboardingCompleted)
        XCTAssertEqual(preferences.correctionCount, 0)
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertEqual(preferences.forceConversionGesture, .doubleShift)
    }

    func testPersistsEveryAllowlistedPreference() {
        var preferences: AppPreferences? = AppPreferences(defaults: defaults)
        preferences?.isEnabled = true
        preferences?.onboardingCompleted = true
        preferences?.launchAtLogin = true
        preferences?.forceConversionGesture = .bothShifts
        preferences?.incrementCorrectionCount()
        preferences?.incrementCorrectionCount()
        preferences = nil

        let restored = AppPreferences(defaults: defaults)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertTrue(restored.onboardingCompleted)
        XCTAssertTrue(restored.launchAtLogin)
        XCTAssertEqual(restored.forceConversionGesture, .bothShifts)
        XCTAssertEqual(restored.correctionCount, 2)
    }

    func testWritesOnlyFiveAllowlistedKeysAndNoWordData() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.isEnabled = true
        preferences.onboardingCompleted = true
        preferences.launchAtLogin = true
        preferences.forceConversionGesture = .bothShifts
        preferences.incrementCorrectionCount()

        XCTAssertEqual(
            Set(defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? []),
            Set([
                PreferenceKey.isEnabled,
                PreferenceKey.onboardingCompleted,
                PreferenceKey.correctionCount,
                PreferenceKey.launchAtLogin,
                PreferenceKey.forceConversionGesture,
            ])
        )
    }

    func testInvalidStoredForceGestureFallsBackToDoubleShift() {
        defaults.set("unsupported", forKey: PreferenceKey.forceConversionGesture)

        XCTAssertEqual(
            AppPreferences(defaults: defaults).forceConversionGesture,
            .doubleShift
        )
    }

    func testCorrectionCountPublishesOnMainThread() {
        let preferences = AppPreferences(defaults: defaults)
        let published = expectation(description: "count published")
        var publishedOnMainThread = false
        let observation = preferences.$correctionCount
            .dropFirst()
            .sink { _ in
                publishedOnMainThread = Thread.isMainThread
                published.fulfill()
            }

        DispatchQueue.global(qos: .userInitiated).async {
            preferences.incrementCorrectionCount()
        }

        wait(for: [published], timeout: 1)
        XCTAssertTrue(publishedOnMainThread)
        withExtendedLifetime(observation) {}
    }
}
