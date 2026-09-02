import Combine
import Foundation
import AkuoCore

enum PreferenceKey {
    static let isEnabled = "isEnabled"
    static let onboardingCompleted = "onboardingCompleted"
    static let correctionCount = "correctionCount"
    static let launchAtLogin = "launchAtLogin"
    static let forceConversionGesture = "forceConversionGesture"
}

public final class AppPreferences: ObservableObject, CorrectionCounting {
    private let defaults: UserDefaults

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: PreferenceKey.isEnabled) }
    }

    @Published public var onboardingCompleted: Bool {
        didSet {
            defaults.set(onboardingCompleted, forKey: PreferenceKey.onboardingCompleted)
        }
    }

    @Published public private(set) var correctionCount: Int {
        didSet { defaults.set(correctionCount, forKey: PreferenceKey.correctionCount) }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: PreferenceKey.launchAtLogin) }
    }

    @Published public var forceConversionGesture: ForceConversionGesture {
        didSet {
            defaults.set(
                forceConversionGesture.rawValue,
                forKey: PreferenceKey.forceConversionGesture
            )
        }
    }

    public convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: PreferenceKey.isEnabled)
        onboardingCompleted = defaults.bool(forKey: PreferenceKey.onboardingCompleted)
        correctionCount = defaults.integer(forKey: PreferenceKey.correctionCount)
        launchAtLogin = defaults.bool(forKey: PreferenceKey.launchAtLogin)
        forceConversionGesture = ForceConversionGesture(
            rawValue: defaults.string(forKey: PreferenceKey.forceConversionGesture) ?? ""
        ) ?? .doubleShift
    }

    public func incrementCorrectionCount() {
        if Thread.isMainThread {
            correctionCount += 1
        } else {
            DispatchQueue.main.sync { [self] in
                correctionCount += 1
            }
        }
    }
}
