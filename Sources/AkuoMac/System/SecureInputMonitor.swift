import Carbon

public protocol SecureInputChecking {
    var isSecureInputEnabled: Bool { get }
}

protocol SecureInputBackend {
    var isSecureInputEnabled: Bool { get }
}

private struct CarbonSecureInputBackend: SecureInputBackend {
    var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}

public struct SystemSecureInputChecker: SecureInputChecking {
    private let backend: any SecureInputBackend

    public init() {
        backend = CarbonSecureInputBackend()
    }

    init(backend: some SecureInputBackend) {
        self.backend = backend
    }

    public var isSecureInputEnabled: Bool {
        backend.isSecureInputEnabled
    }
}
