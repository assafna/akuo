import ApplicationServices
import Foundation

struct WindowProcessSnapshot: Equatable {
    let processIdentifier: Int32
    let layer: Int
    let alpha: Double
}

protocol WindowProcessOrderingProviding {
    func processIdentifiersInFront(of activationOwner: Int32) -> [Int32]?
}

enum WindowProcessOrdering {
    static func processIdentifiersInFront(
        of activationOwner: Int32,
        excluding excludedProcessIdentifier: Int32,
        windows: [WindowProcessSnapshot],
        acceptedLevels: ClosedRange<Int>
    ) -> [Int32]? {
        var processIdentifiers: [Int32] = []
        var seenProcessIdentifiers = Set<Int32>()

        for window in windows {
            guard window.processIdentifier > 0,
                  window.alpha.isFinite,
                  window.alpha > 0,
                  acceptedLevels.contains(window.layer) else {
                continue
            }

            if window.processIdentifier == activationOwner {
                return processIdentifiers
            }

            guard window.processIdentifier != excludedProcessIdentifier,
                  seenProcessIdentifiers.insert(window.processIdentifier).inserted else {
                continue
            }
            processIdentifiers.append(window.processIdentifier)
        }

        return nil
    }
}

final class SystemWindowProcessOrderingProvider: WindowProcessOrderingProviding {
    private let selfProcessIdentifier: Int32
    private let windowList: () -> [[String: Any]]?
    private let acceptedLevels: ClosedRange<Int>

    init() {
        selfProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        windowList = Self.copyVisibleWindowMetadata
        acceptedLevels = Self.acceptedWindowLevels
    }

    init(
        selfProcessIdentifier: Int32,
        windowList: @escaping () -> [[String: Any]]?
    ) {
        self.selfProcessIdentifier = selfProcessIdentifier
        self.windowList = windowList
        acceptedLevels = Self.acceptedWindowLevels
    }

    func processIdentifiersInFront(of activationOwner: Int32) -> [Int32]? {
        guard let windowList = windowList() else {
            return nil
        }
        let windows = windowList.compactMap(WindowProcessSnapshotDecoder.snapshot)
        return WindowProcessOrdering.processIdentifiersInFront(
            of: activationOwner,
            excluding: selfProcessIdentifier,
            windows: windows,
            acceptedLevels: acceptedLevels
        )
    }

    private static var acceptedWindowLevels: ClosedRange<Int> {
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        let modalPanel = Int(CGWindowLevelForKey(.modalPanelWindow))
        return min(normal, modalPanel) ... max(normal, modalPanel)
    }

    private static func copyVisibleWindowMetadata() -> [[String: Any]]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    }
}

private enum WindowProcessSnapshotDecoder {
    static func snapshot(from metadata: [String: Any]) -> WindowProcessSnapshot? {
        guard let processIdentifier = integer(from: metadata[kCGWindowOwnerPID as String]),
              processIdentifier > 0,
              processIdentifier <= Int(Int32.max),
              let layer = integer(from: metadata[kCGWindowLayer as String]),
              let alpha = finiteDouble(from: metadata[kCGWindowAlpha as String]),
              alpha > 0 else {
            return nil
        }

        return WindowProcessSnapshot(
            processIdentifier: Int32(processIdentifier),
            layer: layer,
            alpha: alpha
        )
    }

    private static func integer(from value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              let integer = Int(exactly: value) else {
            return nil
        }
        return integer
    }

    private static func finiteDouble(from value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            return nil
        }
        return number.doubleValue
    }
}
