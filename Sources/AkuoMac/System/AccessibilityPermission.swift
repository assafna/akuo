import ApplicationServices

public protocol AccessibilityPermissionChecking {
    var isGranted: Bool { get }
    func request()
}

protocol AccessibilityPermissionBackend {
    var isGranted: Bool { get }
    func request()
}

private struct SystemAccessibilityPermissionBackend: AccessibilityPermissionBackend {
    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    func request() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

public struct SystemAccessibilityPermission: AccessibilityPermissionChecking {
    private let backend: any AccessibilityPermissionBackend

    public init() {
        backend = SystemAccessibilityPermissionBackend()
    }

    init(backend: some AccessibilityPermissionBackend) {
        self.backend = backend
    }

    public var isGranted: Bool {
        backend.isGranted
    }

    public func request() {
        backend.request()
    }
}
