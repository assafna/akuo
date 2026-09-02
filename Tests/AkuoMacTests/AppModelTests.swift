import AppKit
import Carbon
import Foundation
import XCTest
import AkuoCore
@testable import AkuoMac

@MainActor
final class AppModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDisabledModelIsOffAndDoesNotStartMonitoring() {
        let fixture = makeFixture()

        XCTAssertEqual(fixture.model.status, .off)
        XCTAssertFalse(fixture.model.isEnabled)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testEnabledModelRequiresAccessibilityWithoutPrompting() {
        let fixture = makeFixture()

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .needsAccessibility)
        XCTAssertEqual(fixture.permission.requestCalls, 0)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testReadinessRequiresEnglishInputSource() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: false, hebrewAvailable: true)

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .needsEnglishInputSource)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testReadinessRequiresPermissionAndBothSources() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: false)

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .needsHebrewInputSource)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testSecureInputPausesOtherwiseReadyModel() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .pausedForSecureInput)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testReadyEnabledModelStartsMonitoring() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .active)
        XCTAssertEqual(fixture.monitor.startCalls, 1)
    }

    func testUnavailableEventMonitorIsSurfaced() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.monitor.startResult = false

        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .eventMonitorUnavailable)
        XCTAssertEqual(fixture.monitor.startCalls, 1)
    }

    func testRuntimeMonitorDegradationIsSurfaced() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notify(.degraded)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .eventMonitorUnavailable)
    }

    func testStoppedMonitorDerivesPausedSecureInputStatus() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)
        fixture.secureInput.isSecureInputEnabled = true

        fixture.monitor.notify(.stopped)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .pausedForSecureInput)
        XCTAssertEqual(fixture.recoveryScheduler.scheduleCalls, 1)
        XCTAssertEqual(fixture.recoveryScheduler.delays, [1])
    }

    func testSecureInputRecoveryRestartsMonitoringFromPausedState() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.model.setEnabled(true)
        XCTAssertEqual(fixture.model.status, .pausedForSecureInput)

        fixture.secureInput.isSecureInputEnabled = false
        fixture.recoveryScheduler.fireLatest()
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .active)
        XCTAssertEqual(fixture.monitor.startCalls, 1)
        XCTAssertTrue(fixture.recoveryScheduler.jobs.allSatisfy(\.isCancelled))
    }

    func testLeavingPausedStateCancelsSecureInputRecovery() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.model.setEnabled(true)
        let pendingRecovery = fixture.recoveryScheduler.jobs.last

        fixture.model.setEnabled(false)

        XCTAssertTrue(pendingRecovery?.isCancelled == true)
        XCTAssertEqual(fixture.model.status, .off)
    }

    func testRecoveryRechecksWithoutRestartingWhileSecureInputContinues() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.model.setEnabled(true)

        fixture.recoveryScheduler.fireLatest()
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .pausedForSecureInput)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
        XCTAssertEqual(fixture.recoveryScheduler.delays, [1, 1])
    }

    func testLosingPrerequisiteCancelsSecureInputRecovery() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.model.setEnabled(true)
        let pendingRecovery = fixture.recoveryScheduler.jobs.last

        fixture.permission.isGranted = false
        fixture.model.refresh()

        XCTAssertTrue(pendingRecovery?.isCancelled == true)
        XCTAssertEqual(fixture.model.status, .needsAccessibility)
        XCTAssertEqual(fixture.recoveryScheduler.scheduleCalls, 1)
    }

    func testModelDeinitCancelsSecureInputRecovery() {
        let preferences = AppPreferences(defaults: defaults)
        let permission = FakeAccessibilityPermission()
        permission.isGranted = true
        let secureInput = FakeSecureInputChecker()
        secureInput.isSecureInputEnabled = true
        let sources = FakeInputSourceStateProvider()
        sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        let monitor = FakeEventMonitor()
        let scheduler = FakeSecureInputRecoveryScheduler()
        let launchAtLogin = FakeLaunchAtLoginController(status: .disabled)
        let lifecycle = FakeRuntimeLifecycleObserver()
        var model: AppModel? = AppModel(
            preferences: preferences,
            permission: permission,
            secureInput: secureInput,
            inputSources: sources,
            monitor: monitor,
            secureInputRecoveryScheduler: scheduler,
            launchAtLoginController: launchAtLogin,
            lifecycleObserver: lifecycle
        )
        model?.setEnabled(true)
        let pendingRecovery = scheduler.jobs.last
        weak let weakModel = model

        model = nil

        XCTAssertNil(weakModel)
        XCTAssertTrue(pendingRecovery?.isCancelled == true)
    }

    func testQueuedDegradedCallbackCannotOverrideSuccessfulRestart() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notify(.degraded)
        fixture.model.refresh()
        XCTAssertEqual(fixture.monitor.state, .active)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .active)
    }

    func testQueuedMonitorDegradationCannotOverrideDisabledStatus() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notify(.degraded)
        fixture.model.setEnabled(false)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .off)
    }

    func testCorrectionSelectionFailureRefreshesDisplayWithoutRestartOrRetry() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        let startCalls = fixture.monitor.startCalls
        let stopCalls = fixture.monitor.stopCalls
        let refreshCalls = fixture.monitor.refreshCalls

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertEqual(fixture.model.currentLanguage, .english)
        XCTAssertEqual(fixture.monitor.startCalls, startCalls)
        XCTAssertEqual(fixture.monitor.stopCalls, stopCalls)
        XCTAssertEqual(fixture.monitor.refreshCalls, refreshCalls)
    }

    func testUndoSelectionFailureUsesSameActionableStatusAndRefreshOnly() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        let startCalls = fixture.monitor.startCalls
        fixture.sources.currentLanguage = .hebrew

        fixture.monitor.notifySelectionFailure(.immediateUndo, expectedLanguage: .english)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
        XCTAssertEqual(fixture.monitor.startCalls, startCalls)
        XCTAssertEqual(
            fixture.model.status.menuLabel,
            "Input source switch failed — select a language manually"
        )
    }

    func testPassiveMenuRefreshPreservesSelectionFailureStatus() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)

        fixture.model.refresh()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
    }

    func testApplicationActivationPreservesSelectionFailureStatus() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)

        fixture.lifecycle.sendApplicationActivated()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
    }

    func testInputSourceChangeClearsSelectionFailureAfterManualRecovery() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)

        fixture.sources.currentLanguage = .hebrew
        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.model.status, .active)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
    }

    func testWrongLanguageSourceNotificationPreservesSelectionFailure() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertEqual(fixture.model.currentLanguage, .english)
    }

    func testUnsupportedSourceNotificationPreservesSelectionFailure() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        fixture.sources.currentLanguage = nil
        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertNil(fixture.model.currentLanguage)
    }

    func testDelayedCorrectionNotificationDoesNotClearFailedUndo() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .hebrew
        fixture.sources.consumeAkuoSelectionNotificationResult = true
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.immediateUndo, expectedLanguage: .english)
        await Task.yield()

        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
    }

    func testQueuedFailureAfterConfirmedTargetLanguageIsIgnored() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        fixture.sources.currentLanguage = .hebrew
        fixture.lifecycle.sendInputSourceChanged()
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .active)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
    }

    func testMonitorRecoveryKeepsSelectionFailureUntilSourceRecoveryIsConfirmed() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        fixture.monitor.notify(.degraded)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .eventMonitorUnavailable)

        fixture.monitor.notify(.active)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
    }

    func testPrerequisiteRecoveryKeepsSelectionFailureUntilSourceRecoveryIsConfirmed() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        fixture.permission.isGranted = false
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.status, .needsAccessibility)

        fixture.permission.isGranted = true
        fixture.model.refresh()

        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)
    }

    func testDisableClearsEstablishedSelectionFailure() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)
        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        await Task.yield()

        fixture.model.setEnabled(false)
        fixture.model.setEnabled(true)

        XCTAssertEqual(fixture.model.status, .active)
    }

    func testQueuedFailureFromPriorEnabledSessionCannotReappearAfterReenable() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        fixture.model.setEnabled(false)
        fixture.model.setEnabled(true)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .active)
    }

    func testQueuedSameSessionFailureSurvivesMonitorDegradationUntilTargetNotification() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.sources.currentLanguage = .english
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        fixture.monitor.notify(.degraded)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .eventMonitorUnavailable)

        fixture.monitor.notify(.active)
        await Task.yield()
        XCTAssertEqual(fixture.model.status, .inputSourceSelectionFailed)

        fixture.sources.currentLanguage = .hebrew
        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.model.status, .active)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
    }

    func testQueuedSelectionFailureCannotOverrideDisabledStatus() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        fixture.model.setEnabled(false)
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .off)
    }

    func testQueuedSelectionFailureCannotOverridePrerequisiteLoss() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.immediateUndo, expectedLanguage: .english)
        fixture.permission.isGranted = false
        fixture.model.refresh()
        await Task.yield()

        XCTAssertEqual(fixture.model.status, .needsAccessibility)
    }

    func testQueuedSelectionFailureIsIgnoredAfterTermination() async {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)

        fixture.monitor.notifySelectionFailure(.correction, expectedLanguage: .hebrew)
        fixture.lifecycle.sendTermination()
        await Task.yield()

        XCTAssertNotEqual(fixture.model.status, .inputSourceSelectionFailed)
        XCTAssertEqual(fixture.monitor.state, .stopped)
    }

    func testRefreshUpdatesCurrentLanguageAndReadinessWithoutTextState() {
        let fixture = makeFixture()
        fixture.sources.currentLanguage = .hebrew
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: false)

        fixture.model.refresh()

        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
        XCTAssertEqual(
            fixture.model.inputSourceReadiness,
            .init(englishAvailable: true, hebrewAvailable: false)
        )
        XCTAssertFalse(
            Set(Mirror(reflecting: fixture.model).children.compactMap(\.label))
                .contains(where: { label in
                    ["word", "text", "replacement", "event", "payload"]
                        .contains(where: label.lowercased().contains)
                })
        )
    }

    func testCorrectionCountPublishesAggregateUpdates() {
        let fixture = makeFixture()

        fixture.preferences.incrementCorrectionCount()

        XCTAssertEqual(fixture.model.correctionCount, 1)
    }

    func testForceConversionGestureDefaultsAndPersistsThroughModel() {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.model.forceConversionGesture, .doubleShift)

        fixture.model.setForceConversionGesture(.bothShifts)

        XCTAssertEqual(fixture.model.forceConversionGesture, .bothShifts)
        XCTAssertEqual(fixture.preferences.forceConversionGesture, .bothShifts)
        XCTAssertEqual(
            AppPreferences(defaults: defaults).forceConversionGesture,
            .bothShifts
        )
    }

    func testAccessibilityRequestOccursOnlyAfterExplicitModelAction() {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.permission.requestCalls, 0)

        fixture.model.requestAccessibility()

        XCTAssertEqual(fixture.permission.requestCalls, 1)
    }

    func testCompletingOnboardingPersistsWithoutStartingTheMonitor() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.refresh()

        fixture.model.completeOnboarding()

        XCTAssertTrue(fixture.model.onboardingCompleted)
        XCTAssertTrue(AppPreferences(defaults: defaults).onboardingCompleted)
        XCTAssertEqual(fixture.monitor.startCalls, 0)
    }

    func testLaunchAtLoginReflectsSystemStatusWithoutRegisteringOnInitialization() {
        let fixture = makeFixture(launchAtLoginStatus: .enabled)

        XCTAssertTrue(fixture.model.launchAtLoginEnabled)
        XCTAssertNil(fixture.model.launchAtLoginMessage)
        XCTAssertEqual(fixture.launchAtLogin.setEnabledCalls, [])
    }

    func testSuccessfulLaunchAtLoginTogglePersistsAfterSystemConfirmation() {
        let fixture = makeFixture()
        fixture.launchAtLogin.status = .enabled

        fixture.model.setLaunchAtLogin(true)

        XCTAssertEqual(fixture.launchAtLogin.setEnabledCalls, [true])
        XCTAssertTrue(fixture.model.launchAtLoginEnabled)
        XCTAssertTrue(fixture.preferences.launchAtLogin)
        XCTAssertNil(fixture.model.launchAtLoginMessage)
    }

    func testApprovalRequiredDoesNotClaimOrPersistLaunchAtLoginEnabled() {
        let fixture = makeFixture()
        fixture.launchAtLogin.status = .requiresApproval

        fixture.model.setLaunchAtLogin(true)

        XCTAssertFalse(fixture.model.launchAtLoginEnabled)
        XCTAssertFalse(fixture.preferences.launchAtLogin)
        XCTAssertEqual(
            fixture.model.launchAtLoginMessage,
            "Allow Akuo in System Settings > General > Login Items."
        )
    }

    func testRevokedLaunchAtLoginApprovalClearsStalePersistedEnabledState() {
        defaults.set(true, forKey: PreferenceKey.launchAtLogin)

        let fixture = makeFixture(launchAtLoginStatus: .requiresApproval)

        XCTAssertFalse(fixture.model.launchAtLoginEnabled)
        XCTAssertFalse(fixture.preferences.launchAtLogin)
        XCTAssertEqual(
            fixture.model.launchAtLoginMessage,
            "Allow Akuo in System Settings > General > Login Items."
        )
    }

    func testUnavailableLaunchAtLoginClearsStalePersistedEnabledState() {
        defaults.set(true, forKey: PreferenceKey.launchAtLogin)

        let fixture = makeFixture(launchAtLoginStatus: .unavailable)

        XCTAssertFalse(fixture.model.launchAtLoginEnabled)
        XCTAssertFalse(fixture.preferences.launchAtLogin)
        XCTAssertEqual(
            fixture.model.launchAtLoginMessage,
            "Launch at Login is unavailable for this copy of Akuo."
        )
    }

    func testLaunchAtLoginFailureReconcilesDisplayAndDoesNotPersistRequest() {
        let fixture = makeFixture()
        fixture.launchAtLogin.status = .disabled
        fixture.launchAtLogin.error = .registrationFailed("Registration failed.")

        fixture.model.setLaunchAtLogin(true)

        XCTAssertEqual(fixture.launchAtLogin.setEnabledCalls, [true])
        XCTAssertFalse(fixture.model.launchAtLoginEnabled)
        XCTAssertFalse(fixture.preferences.launchAtLogin)
        XCTAssertEqual(fixture.model.launchAtLoginMessage, "Registration failed.")
    }

    func testLaunchAtLoginFailureWithApprovalStatusKeepsActionableGuidance() {
        let fixture = makeFixture()
        fixture.launchAtLogin.status = .requiresApproval
        fixture.launchAtLogin.error = .registrationFailed("Registration denied.")

        fixture.model.setLaunchAtLogin(true)

        XCTAssertFalse(fixture.model.launchAtLoginEnabled)
        XCTAssertFalse(fixture.preferences.launchAtLogin)
        XCTAssertEqual(
            fixture.model.launchAtLoginMessage,
            "Allow Akuo in System Settings > General > Login Items."
        )
    }

    func testApplicationActivationClearsTransientStateBeforeRefreshingDisplay() {
        let fixture = makeFixture()
        fixture.sources.currentLanguage = .english
        fixture.monitor.onRefreshState = {
            fixture.sources.currentLanguage = .hebrew
        }

        fixture.lifecycle.sendApplicationActivated()

        XCTAssertEqual(fixture.monitor.refreshCalls, 1)
        XCTAssertEqual(fixture.model.currentLanguage, .hebrew)
    }

    func testInputSourceChangeClearsTransientStateBeforeRefreshingDisplay() {
        let fixture = makeFixture()
        fixture.sources.currentLanguage = .hebrew
        fixture.monitor.onRefreshState = {
            fixture.sources.currentLanguage = .english
        }

        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.monitor.refreshCalls, 1)
        XCTAssertEqual(fixture.model.currentLanguage, .english)
    }

    func testApplicationActivationWithPermissionLossStopsMonitoring() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)
        let stopCallsBeforeActivation = fixture.monitor.stopCalls
        fixture.permission.isGranted = false

        fixture.lifecycle.sendApplicationActivated()

        XCTAssertEqual(fixture.monitor.refreshCalls, 1)
        XCTAssertEqual(fixture.monitor.stopCalls, stopCallsBeforeActivation + 1)
        XCTAssertEqual(fixture.model.status, .needsAccessibility)
    }

    func testTerminationCancelsSecureInputRecoveryAndStopsEventTap() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.secureInput.isSecureInputEnabled = true
        fixture.model.setEnabled(true)
        let recovery = fixture.recoveryScheduler.jobs.last
        let stopCallsBeforeTermination = fixture.monitor.stopCalls

        fixture.lifecycle.sendTermination()

        XCTAssertTrue(recovery?.isCancelled == true)
        XCTAssertEqual(fixture.monitor.stopCalls, stopCallsBeforeTermination + 1)
    }

    func testContextChangeAfterTerminationCannotRestartMonitoring() {
        let fixture = makeFixture()
        fixture.permission.isGranted = true
        fixture.sources.readiness = .init(englishAvailable: true, hebrewAvailable: true)
        fixture.model.setEnabled(true)
        fixture.lifecycle.sendTermination()
        let refreshCallsAfterTermination = fixture.monitor.refreshCalls

        fixture.lifecycle.sendApplicationActivated()
        fixture.lifecycle.sendInputSourceChanged()

        XCTAssertEqual(fixture.monitor.refreshCalls, refreshCallsAfterTermination)
        XCTAssertEqual(fixture.monitor.state, .stopped)
    }

    func testSystemTerminationNotificationRunsCleanupSynchronously() {
        let observer = SystemRuntimeLifecycleObserver()
        var terminationCalls = 0
        observer.start(
            onApplicationActivated: {},
            onInputSourceChanged: {},
            onTermination: { terminationCalls += 1 }
        )

        NotificationCenter.default.post(
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        XCTAssertEqual(terminationCalls, 1)
        observer.stop()
    }

    func testSystemApplicationActivationNotificationRunsRefreshSynchronously() {
        let observer = SystemRuntimeLifecycleObserver()
        var activationCalls = 0
        observer.start(
            onApplicationActivated: { activationCalls += 1 },
            onInputSourceChanged: {},
            onTermination: {}
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        XCTAssertEqual(activationCalls, 1)
        observer.stop()
    }

    func testSystemInputSourceNotificationUsesExactCarbonNameAndRemovesToken() {
        let observer = SystemRuntimeLifecycleObserver()
        let delivered = expectation(description: "Carbon input-source notification delivered")
        var inputSourceChangeCalls = 0
        observer.start(
            onApplicationActivated: {},
            onInputSourceChanged: {
                inputSourceChangeCalls += 1
                delivered.fulfill()
            },
            onTermination: {}
        )

        let distributedCenter = DistributedNotificationCenter.default()
        let inputSourceNotification = Notification.Name(
            rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String
        )

        distributedCenter.postNotificationName(
            inputSourceNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(inputSourceChangeCalls, 1)
        observer.stop()

        distributedCenter.postNotificationName(
            inputSourceNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(inputSourceChangeCalls, 1)
    }

    func testSystemInputSourceCallbackDoesNotHopToAnotherTask() {
        let observer = SystemRuntimeLifecycleObserver()
        var inputSourceChangeCalls = 0
        observer.start(
            onApplicationActivated: {},
            onInputSourceChanged: { inputSourceChangeCalls += 1 },
            onTermination: {}
        )

        observer.handleInputSourceChangeNotification()

        XCTAssertEqual(inputSourceChangeCalls, 1)
        observer.stop()
    }

    private func makeFixture(
        launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    ) -> Fixture {
        let preferences = AppPreferences(defaults: defaults)
        let permission = FakeAccessibilityPermission()
        let secureInput = FakeSecureInputChecker()
        let sources = FakeInputSourceStateProvider()
        let monitor = FakeEventMonitor()
        let recoveryScheduler = FakeSecureInputRecoveryScheduler()
        let launchAtLogin = FakeLaunchAtLoginController(status: launchAtLoginStatus)
        let lifecycle = FakeRuntimeLifecycleObserver()
        let model = AppModel(
            preferences: preferences,
            permission: permission,
            secureInput: secureInput,
            inputSources: sources,
            monitor: monitor,
            secureInputRecoveryScheduler: recoveryScheduler,
            launchAtLoginController: launchAtLogin,
            lifecycleObserver: lifecycle
        )
        return Fixture(
            model: model,
            preferences: preferences,
            permission: permission,
            secureInput: secureInput,
            sources: sources,
            monitor: monitor,
            recoveryScheduler: recoveryScheduler,
            launchAtLogin: launchAtLogin,
            lifecycle: lifecycle
        )
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let preferences: AppPreferences
    let permission: FakeAccessibilityPermission
    let secureInput: FakeSecureInputChecker
    let sources: FakeInputSourceStateProvider
    let monitor: FakeEventMonitor
    let recoveryScheduler: FakeSecureInputRecoveryScheduler
    let launchAtLogin: FakeLaunchAtLoginController
    let lifecycle: FakeRuntimeLifecycleObserver
}

private final class FakeAccessibilityPermission: AccessibilityPermissionChecking {
    var isGranted = false
    private(set) var requestCalls = 0

    func request() {
        requestCalls += 1
    }
}

private final class FakeSecureInputChecker: SecureInputChecking {
    var isSecureInputEnabled = false
}

private final class FakeInputSourceStateProvider: RuntimeInputSourceProviding {
    var readiness = InputSourceReadiness(englishAvailable: false, hebrewAvailable: false)
    var currentLanguage: Language?
    var currentSource: InputSourceSnapshot? {
        currentLanguage.map {
            .init(
                identifier: $0 == .english
                    ? "com.apple.keylayout.ABC"
                    : "com.apple.keylayout.Hebrew",
                language: $0
            )
        }
    }
    var consumeAkuoSelectionNotificationResult = false

    func consumeAkuoSelectionNotification() -> Bool {
        consumeAkuoSelectionNotificationResult
    }
}

private final class FakeEventMonitor: EventMonitoring {
    weak var delegate: (any KeyboardEventMonitorDelegate)?
    var state: KeyboardEventMonitor.State = .stopped
    var startResult = true
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var refreshCalls = 0
    var onRefreshState: (() -> Void)?

    func start() -> Bool {
        startCalls += 1
        state = startResult ? .active : .degraded
        return startResult
    }

    func stop() {
        stopCalls += 1
        state = .stopped
    }

    func refreshState() {
        refreshCalls += 1
        onRefreshState?()
    }

    func refreshAfterAkuoInputSourceChange() {
        onRefreshState?()
    }

    func notify(_ state: KeyboardEventMonitor.State) {
        self.state = state
        delegate?.didChangeMonitorState(state)
    }

    func notifySelectionFailure(
        _ operation: InputSourceSelectionOperation,
        expectedLanguage: Language
    ) {
        delegate?.didFailInputSourceSelection(.init(
            operation: operation,
            expectedLanguage: expectedLanguage
        ))
    }
}

private final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var error: LaunchAtLoginControllerError?
    private(set) var setEnabledCalls: [Bool] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        setEnabledCalls.append(enabled)
        if let error { throw error }
        return status
    }
}

@MainActor
private final class FakeRuntimeLifecycleObserver: RuntimeLifecycleObserving {
    private var onApplicationActivated: (@MainActor () -> Void)?
    private var onInputSourceChanged: (@MainActor () -> Void)?
    private var onTermination: (@MainActor () -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start(
        onApplicationActivated: @escaping @MainActor () -> Void,
        onInputSourceChanged: @escaping @MainActor () -> Void,
        onTermination: @escaping @MainActor () -> Void
    ) {
        startCalls += 1
        self.onApplicationActivated = onApplicationActivated
        self.onInputSourceChanged = onInputSourceChanged
        self.onTermination = onTermination
    }

    func stop() {
        stopCalls += 1
        onApplicationActivated = nil
        onInputSourceChanged = nil
        onTermination = nil
    }

    func sendApplicationActivated() {
        onApplicationActivated?()
    }

    func sendInputSourceChanged() {
        onInputSourceChanged?()
    }

    func sendTermination() {
        onTermination?()
    }
}

@MainActor
private final class FakeSecureInputRecoveryScheduler: SecureInputRecoveryScheduling {
    private(set) var jobs: [FakeSecureInputRecoveryTask] = []
    private(set) var delays: [TimeInterval] = []
    var scheduleCalls: Int { jobs.count }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SecureInputRecoveryCancelling {
        delays.append(delay)
        let job = FakeSecureInputRecoveryTask(action: action)
        jobs.append(job)
        return job
    }

    func fireLatest() {
        jobs.last?.fire()
    }
}

private final class FakeSecureInputRecoveryTask: SecureInputRecoveryCancelling {
    private var action: (() -> Void)?
    private(set) var isCancelled = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = {
            Task { @MainActor in
                action()
            }
        }
    }

    func fire() {
        guard !isCancelled, let action else { return }
        self.action = nil
        isCancelled = true
        action()
    }

    func cancel() {
        isCancelled = true
        action = nil
    }
}
