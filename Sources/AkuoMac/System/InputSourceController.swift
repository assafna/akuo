import Carbon
import Foundation
import AkuoCore

public struct InputSourceDescriptor: Equatable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

public struct InputSourceReadiness: Equatable, Sendable {
    public let englishAvailable: Bool
    public let hebrewAvailable: Bool

    public init(englishAvailable: Bool, hebrewAvailable: Bool) {
        self.englishAvailable = englishAvailable
        self.hebrewAvailable = hebrewAvailable
    }
}

struct InputSourceSnapshot: Equatable, Sendable {
    let identifier: String
    let language: Language
}

protocol InputSourceBackend {
    var sources: [InputSourceDescriptor] { get }
    var currentIdentifier: String? { get }
    func select(identifier: String) -> Bool
}

private struct CarbonInputSourceBackend: InputSourceBackend {
    var sources: [InputSourceDescriptor] {
        inputSources.compactMap { source in
            identifier(for: source).map(InputSourceDescriptor.init(identifier:))
        }
    }

    var currentIdentifier: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return identifier(for: source)
    }

    func select(identifier: String) -> Bool {
        guard let source = inputSources.first(where: { self.identifier(for: $0) == identifier }) else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    private var inputSources: [TISInputSource] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
            return []
        }
        return sourceList as NSArray as? [TISInputSource] ?? []
    }

    private func identifier(for source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

final class InputSourceSelectionOriginTracker {
    private struct PendingSelection {
        let language: Language
        let expiresAt: TimeInterval
    }

    private let validityInterval: TimeInterval
    private let now: () -> TimeInterval
    private var pendingSelection: PendingSelection?

    init(
        validityInterval: TimeInterval = 1,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        // Carbon posts this notification asynchronously after selection. Keep
        // the origin hint long enough for delivery, but never indefinitely.
        self.validityInterval = validityInterval
        self.now = now
    }

    func recordSuccessfulSelection(to language: Language) {
        pendingSelection = .init(
            language: language,
            expiresAt: now() + validityInterval
        )
    }

    func consumeIfMatching(_ currentLanguage: Language?) -> Bool {
        guard let pendingSelection else { return false }
        self.pendingSelection = nil
        return now() <= pendingSelection.expiresAt
            && currentLanguage == pendingSelection.language
    }
}

public struct InputSourceController: InputSourceSelecting {
    static let englishPreference = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US",
    ]
    static let standardHebrew = "com.apple.keylayout.Hebrew"

    private let backend: any InputSourceBackend
    private let selectionOriginTracker: InputSourceSelectionOriginTracker

    public init() {
        backend = CarbonInputSourceBackend()
        selectionOriginTracker = InputSourceSelectionOriginTracker()
    }

    init(
        backend: some InputSourceBackend,
        selectionOriginTracker: InputSourceSelectionOriginTracker = .init()
    ) {
        self.backend = backend
        self.selectionOriginTracker = selectionOriginTracker
    }

    public var readiness: InputSourceReadiness {
        let identifiers = Set(backend.sources.map(\.identifier))
        return InputSourceReadiness(
            englishAvailable: Self.englishPreference.contains(where: identifiers.contains),
            hebrewAvailable: identifiers.contains(Self.standardHebrew)
        )
    }

    public var currentLanguage: Language? {
        currentSource?.language
    }

    var currentSource: InputSourceSnapshot? {
        guard let identifier = backend.currentIdentifier else { return nil }
        if Self.englishPreference.contains(identifier) {
            return .init(identifier: identifier, language: .english)
        }
        if identifier == Self.standardHebrew {
            return .init(identifier: identifier, language: .hebrew)
        }
        return nil
    }

    func preferredSource(for language: Language) -> InputSourceSnapshot? {
        let availableIdentifiers = Set(backend.sources.map(\.identifier))
        let identifier: String?
        switch language {
        case .english:
            identifier = Self.englishPreference.first(where: availableIdentifiers.contains)
        case .hebrew:
            identifier = availableIdentifiers.contains(Self.standardHebrew)
                ? Self.standardHebrew
                : nil
        }
        return identifier.map { .init(identifier: $0, language: language) }
    }

    @discardableResult
    public func select(_ language: Language) -> Bool {
        guard let identifier = preferredSource(for: language)?.identifier else { return false }
        guard backend.select(identifier: identifier) else { return false }
        selectionOriginTracker.recordSuccessfulSelection(to: language)
        return true
    }

    func consumeAkuoSelectionNotification() -> Bool {
        selectionOriginTracker.consumeIfMatching(currentLanguage)
    }
}
