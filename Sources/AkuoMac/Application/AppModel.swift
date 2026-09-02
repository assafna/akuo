import AppKit
import Carbon
import Combine
import Foundation
import AkuoCore

protocol EventMonitoring: AnyObject {
    var delegate: (any KeyboardEventMonitorDelegate)? { get set }
    var state: KeyboardEventMonitor.State { get }

    @discardableResult func start() -> Bool
    func stop()
    func refreshState()
    func refreshAfterAkuoInputSourceChange()
}

extension KeyboardEventMonitor: EventMonitoring {}

protocol RuntimeInputSourceProviding: InputSourceStateProviding {
    func consumeAkuoSelectionNotification() -> Bool
}

extension InputSourceController: RuntimeInputSourceProviding {}

protocol SecureInputRecoveryCancelling: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeLifecycleObserving: AnyObject {
    func start(
        onApplicationActivated: @escaping @MainActor () -> Void,
        onInputSourceChanged: @escaping @MainActor () -> Void,
        onTermination: @escaping @MainActor () -> Void
    )
    func stop()
}

@MainActor
final class SystemRuntimeLifecycleObserver: RuntimeLifecycleObserving {
    private var removeObservers: [() -> Void] = []
    private var inputSourceChangeAction: (@MainActor () -> Void)?

    func start(
        onApplicationActivated: @escaping @MainActor () -> Void,
        onInputSourceChanged: @escaping @MainActor () -> Void,
        onTermination: @escaping @MainActor () -> Void
    ) {
        stop()
        inputSourceChangeAction = onInputSourceChanged

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let activationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onApplicationActivated()
            }
        }
        removeObservers.append {
            workspaceCenter.removeObserver(activationObserver)
        }

        let distributedCenter = DistributedNotificationCenter.default()
        let inputSourceObserver = distributedCenter.addObserver(
            forName: Notification.Name(
                rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String
            ),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleInputSourceChangeNotification()
            }
        }
        removeObservers.append {
            distributedCenter.removeObserver(inputSourceObserver)
        }

        let applicationCenter = NotificationCenter.default
        let terminationObserver = applicationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onTermination()
            }
        }
        removeObservers.append {
            applicationCenter.removeObserver(terminationObserver)
        }
    }

    func stop() {
        removeObservers.forEach { $0() }
        removeObservers.removeAll()
        inputSourceChangeAction = nil
    }

    func handleInputSourceChangeNotification() {
        inputSourceChangeAction?()
    }

    deinit {
        removeObservers.forEach { $0() }
    }
}

@MainActor
protocol SecureInputRecoveryScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SecureInputRecoveryCancelling
}

private final class EnabledSessionGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var isActive = false

    func update(isActive: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard self.isActive != isActive else { return }
        generation += 1
        self.isActive = isActive
    }

    func capture() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return isActive ? generation : nil
    }

    func matches(_ capturedGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive && generation == capturedGeneration
    }
}

@MainActor
public final class AppModel: ObservableObject, KeyboardEventMonitorDelegate {
    public enum Status: Equatable, Sendable {
        case off
        case needsAccessibility
        case needsEnglishInputSource
        case needsHebrewInputSource
        case pausedForSecureInput
        case active
        case eventMonitorUnavailable
        case inputSourceSelectionFailed

        public var menuLabel: String {
            switch self {
            case .off:
                "Off"
            case .needsAccessibility:
                "Accessibility needed"
            case .needsEnglishInputSource:
                "English input source missing"
            case .needsHebrewInputSource:
                "Hebrew input source missing"
            case .pausedForSecureInput:
                "Paused for Secure Input"
            case .active:
                "Active"
            case .eventMonitorUnavailable:
                "Keyboard monitoring unavailable"
            case .inputSourceSelectionFailed:
                "Input source switch failed — select a language manually"
            }
        }
    }

    @Published public private(set) var status: Status = .off
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var onboardingCompleted: Bool
    @Published public private(set) var correctionCount: Int
    @Published public private(set) var permissionGranted = false
    @Published public private(set) var inputSourceReadiness = InputSourceReadiness(
        englishAvailable: false,
        hebrewAvailable: false
    )
    @Published public private(set) var currentLanguage: Language?
    @Published public private(set) var launchAtLoginEnabled = false
    @Published public private(set) var launchAtLoginMessage: String?
    @Published public private(set) var forceConversionGesture: ForceConversionGesture

    public var canCompleteSetup: Bool {
        permissionGranted
            && inputSourceReadiness.englishAvailable
            && inputSourceReadiness.hebrewAvailable
    }

    public var needsSetup: Bool {
        !onboardingCompleted || !canCompleteSetup
    }

    private let preferences: AppPreferences
    private let permission: any AccessibilityPermissionChecking
    private let secureInput: any SecureInputChecking
    private let inputSources: any RuntimeInputSourceProviding
    private let monitor: any EventMonitoring
    private let enabledSessionGeneration = EnabledSessionGeneration()
    private let secureInputRecoveryScheduler: any SecureInputRecoveryScheduling
    private let launchAtLoginController: any LaunchAtLoginControlling
    private let lifecycleObserver: any RuntimeLifecycleObserving
    private var correctionCountObservation: AnyCancellable?
    private var secureInputRecoveryTask: (any SecureInputRecoveryCancelling)?
    private var pendingInputSourceSelectionFailure: InputSourceSelectionFailure?
    private var isTerminating = false

    init(
        preferences: AppPreferences,
        permission: any AccessibilityPermissionChecking,
        secureInput: any SecureInputChecking,
        inputSources: any RuntimeInputSourceProviding,
        monitor: any EventMonitoring,
        secureInputRecoveryScheduler: (any SecureInputRecoveryScheduling)? = nil,
        launchAtLoginController: any LaunchAtLoginControlling,
        lifecycleObserver: any RuntimeLifecycleObserving
    ) {
        self.preferences = preferences
        self.permission = permission
        self.secureInput = secureInput
        self.inputSources = inputSources
        self.monitor = monitor
        self.secureInputRecoveryScheduler = secureInputRecoveryScheduler
            ?? SystemSecureInputRecoveryScheduler()
        self.launchAtLoginController = launchAtLoginController
        self.lifecycleObserver = lifecycleObserver
        isEnabled = preferences.isEnabled
        onboardingCompleted = preferences.onboardingCompleted
        correctionCount = preferences.correctionCount
        forceConversionGesture = preferences.forceConversionGesture
        currentLanguage = inputSources.currentLanguage
        enabledSessionGeneration.update(isActive: isEnabled)

        monitor.delegate = self
        correctionCountObservation = preferences.$correctionCount
            .removeDuplicates()
            .sink { [weak self] count in
                self?.correctionCount = count
            }
        lifecycleObserver.start(
            onApplicationActivated: { [weak self] in
                self?.handleRuntimeContextChange()
            },
            onInputSourceChanged: { [weak self] in
                self?.handleInputSourceChange()
            },
            onTermination: { [weak self] in
                self?.handleTermination()
            }
        )
        refresh()
    }

    deinit {
        secureInputRecoveryTask?.cancel()
    }

    nonisolated static func makeRecognitionPolicy(
        fallback: some WordRecognizing
    ) -> CorrectionPolicy {
        let recognizer = CompositeWordRecognizer(
            primary: SeedLexicon(),
            fallback: fallback
        )
        let scorer = WordScorer(recognizer: recognizer)
        return CorrectionPolicy(
            layoutMap: KeyboardLayoutMap(),
            originalScorer: scorer,
            candidateScorer: scorer,
            excluder: TokenExcluder()
        )
    }

    public static func live(preferences: AppPreferences = AppPreferences()) -> AppModel {
        let permission = SystemAccessibilityPermission()
        let secureInput = SystemSecureInputChecker()
        let inputSources = InputSourceController()
        let policy = makeRecognitionPolicy(fallback: SystemSpellChecker())
        let coordinator = CorrectionCoordinator(
            policy: policy,
            textReplacer: CGEventEmitter(),
            inputSourceSelector: inputSources,
            counter: preferences,
            clock: SystemRuntimeClock(),
            undoController: UndoController()
        )
        let monitor = KeyboardEventMonitor(
            coordinator: coordinator,
            permission: permission,
            secureInput: secureInput,
            focusContextProvider: FocusContextProvider(),
            inputSources: inputSources,
            forceConversionGesture: { [weak preferences] in
                preferences?.forceConversionGesture ?? .doubleShift
            },
            isAkuoEnabled: { [weak preferences] in
                preferences?.isEnabled ?? false
            }
        )

        return AppModel(
            preferences: preferences,
            permission: permission,
            secureInput: secureInput,
            inputSources: inputSources,
            monitor: monitor,
            launchAtLoginController: LaunchAtLoginController(),
            lifecycleObserver: SystemRuntimeLifecycleObserver()
        )
    }

    public func setEnabled(_ enabled: Bool) {
        enabledSessionGeneration.update(isActive: enabled)
        if !enabled {
            pendingInputSourceSelectionFailure = nil
        }
        guard isEnabled != enabled else {
            refresh()
            return
        }
        preferences.isEnabled = enabled
        isEnabled = enabled
        refresh()
    }

    public func requestAccessibility() {
        permission.request()
        refresh()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let systemStatus = try launchAtLoginController.setEnabled(enabled)
            reconcileLaunchAtLogin(systemStatus)

            if enabled, systemStatus == .enabled {
                preferences.launchAtLogin = true
            } else if !enabled, systemStatus == .disabled {
                preferences.launchAtLogin = false
            } else if enabled, systemStatus == .disabled {
                launchAtLoginMessage = "macOS did not enable Launch at Login."
            } else if !enabled, systemStatus == .enabled {
                launchAtLoginMessage = "macOS did not disable Launch at Login."
            }
        } catch {
            let systemStatus = launchAtLoginController.status
            reconcileLaunchAtLogin(systemStatus)
            guard systemStatus != .requiresApproval else { return }
            launchAtLoginMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    public func setForceConversionGesture(_ gesture: ForceConversionGesture) {
        preferences.forceConversionGesture = gesture
        forceConversionGesture = gesture
    }

    public func completeOnboarding() {
        guard canCompleteSetup else { return }
        preferences.onboardingCompleted = true
        onboardingCompleted = true
    }

    public func refresh() {
        guard !isTerminating else { return }
        cancelSecureInputRecovery()
        refreshPublishedState()
        reconcileLaunchAtLogin(launchAtLoginController.status)

        guard isEnabled else {
            pendingInputSourceSelectionFailure = nil
            monitor.stop()
            status = .off
            return
        }
        guard permissionGranted else {
            monitor.stop()
            status = .needsAccessibility
            return
        }
        guard inputSourceReadiness.englishAvailable else {
            monitor.stop()
            status = .needsEnglishInputSource
            return
        }
        guard inputSourceReadiness.hebrewAvailable else {
            monitor.stop()
            status = .needsHebrewInputSource
            return
        }
        guard !secureInput.isSecureInputEnabled else {
            monitor.stop()
            status = .pausedForSecureInput
            scheduleSecureInputRecovery()
            return
        }

        guard monitor.start() else {
            status = .eventMonitorUnavailable
            return
        }
        status = activeSessionStatus
    }

    nonisolated public func didChangeMonitorState(_ state: KeyboardEventMonitor.State) {
        Task { @MainActor [weak self] in
            self?.updateMonitorState(state)
        }
    }

    nonisolated public func didFailInputSourceSelection(
        _ failure: InputSourceSelectionFailure
    ) {
        guard let capturedGeneration = enabledSessionGeneration.capture() else { return }
        Task { @MainActor [weak self] in
            self?.updateAfterInputSourceSelectionFailure(
                failure,
                capturedGeneration: capturedGeneration
            )
        }
    }

    private func updateMonitorState(_ state: KeyboardEventMonitor.State) {
        guard !isTerminating else { return }
        guard monitor.state == state else { return }

        switch state {
        case .active:
            if runtimePrerequisitesAreMet {
                cancelSecureInputRecovery()
                status = activeSessionStatus
            } else {
                refresh()
            }
        case .degraded:
            if runtimePrerequisitesAreMet {
                cancelSecureInputRecovery()
                status = .eventMonitorUnavailable
            } else {
                refresh()
            }
        case .stopped:
            refresh()
        }
    }

    private func updateAfterInputSourceSelectionFailure(
        _ failure: InputSourceSelectionFailure,
        capturedGeneration: UInt64
    ) {
        let monitorState = monitor.state
        guard !isTerminating,
              enabledSessionGeneration.matches(capturedGeneration),
              monitorState == .active || monitorState == .degraded,
              runtimePrerequisitesAreMet else {
            return
        }

        inputSourceReadiness = inputSources.readiness
        currentLanguage = inputSources.currentLanguage
        guard currentLanguage != failure.expectedLanguage else { return }
        pendingInputSourceSelectionFailure = failure
        status = monitorState == .degraded
            ? .eventMonitorUnavailable
            : .inputSourceSelectionFailed
    }

    private func scheduleSecureInputRecovery() {
        guard secureInputRecoveryTask == nil else { return }
        secureInputRecoveryTask = secureInputRecoveryScheduler.schedule(after: 1) {
            [weak self] in
            guard let self else { return }
            self.secureInputRecoveryTask = nil
            self.refresh()
        }
    }

    private func handleRuntimeContextChange() {
        guard !isTerminating else { return }
        cancelSecureInputRecovery()
        monitor.refreshState()
        reconcileRuntimeContextAfterRefresh()
    }

    private func handleInputSourceChange() {
        guard !isTerminating else { return }
        cancelSecureInputRecovery()
        if inputSources.consumeAkuoSelectionNotification() {
            monitor.refreshAfterAkuoInputSourceChange()
        } else {
            monitor.refreshState()
        }
        reconcileRuntimeContextAfterRefresh(confirmingInputSourceChange: true)
    }

    private func reconcileRuntimeContextAfterRefresh(
        confirmingInputSourceChange: Bool = false
    ) {
        refreshPublishedState()
        if confirmingInputSourceChange,
           currentLanguage == pendingInputSourceSelectionFailure?.expectedLanguage {
            pendingInputSourceSelectionFailure = nil
        }

        guard isEnabled else {
            pendingInputSourceSelectionFailure = nil
            monitor.stop()
            status = .off
            return
        }
        guard permissionGranted else {
            monitor.stop()
            status = .needsAccessibility
            return
        }
        guard inputSourceReadiness.englishAvailable else {
            monitor.stop()
            status = .needsEnglishInputSource
            return
        }
        guard inputSourceReadiness.hebrewAvailable else {
            monitor.stop()
            status = .needsHebrewInputSource
            return
        }
        guard !secureInput.isSecureInputEnabled else {
            monitor.stop()
            status = .pausedForSecureInput
            scheduleSecureInputRecovery()
            return
        }

        guard monitor.state == .active else {
            status = .eventMonitorUnavailable
            return
        }
        status = activeSessionStatus
    }

    private func handleTermination() {
        isTerminating = true
        enabledSessionGeneration.update(isActive: false)
        pendingInputSourceSelectionFailure = nil
        cancelSecureInputRecovery()
        monitor.stop()
    }

    private func refreshPublishedState() {
        isEnabled = preferences.isEnabled
        enabledSessionGeneration.update(isActive: isEnabled)
        onboardingCompleted = preferences.onboardingCompleted
        correctionCount = preferences.correctionCount
        forceConversionGesture = preferences.forceConversionGesture
        permissionGranted = permission.isGranted
        inputSourceReadiness = inputSources.readiness
        currentLanguage = inputSources.currentLanguage
    }

    private func reconcileLaunchAtLogin(_ systemStatus: LaunchAtLoginStatus) {
        launchAtLoginEnabled = systemStatus == .enabled
        switch systemStatus {
        case .requiresApproval:
            preferences.launchAtLogin = false
            launchAtLoginMessage =
                "Allow Akuo in System Settings > General > Login Items."
        case .unavailable:
            preferences.launchAtLogin = false
            launchAtLoginMessage = "Launch at Login is unavailable for this copy of Akuo."
        case .disabled:
            preferences.launchAtLogin = false
            launchAtLoginMessage = nil
        case .enabled:
            preferences.launchAtLogin = true
            launchAtLoginMessage = nil
        }
    }

    private func cancelSecureInputRecovery() {
        secureInputRecoveryTask?.cancel()
        secureInputRecoveryTask = nil
    }

    private var runtimePrerequisitesAreMet: Bool {
        let readiness = inputSources.readiness
        return isEnabled
            && permission.isGranted
            && readiness.englishAvailable
            && readiness.hebrewAvailable
            && !secureInput.isSecureInputEnabled
    }

    private var activeSessionStatus: Status {
        pendingInputSourceSelectionFailure == nil
            ? .active
            : .inputSourceSelectionFailed
    }
}

private struct SystemRuntimeClock: RuntimeClock {
    var now: Date { Date() }
}

@MainActor
private struct SystemSecureInputRecoveryScheduler: SecureInputRecoveryScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SecureInputRecoveryCancelling {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerSecureInputRecoveryTask(timer: timer)
    }
}

private final class TimerSecureInputRecoveryTask: SecureInputRecoveryCancelling {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
