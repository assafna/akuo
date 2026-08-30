import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

public enum LaunchAtLoginControllerError: LocalizedError, Equatable, Sendable {
    case unavailable
    case registrationFailed(String)
    case unregistrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Launch at Login is unavailable for this copy of Akuo."
        case let .registrationFailed(message), let .unregistrationFailed(message):
            message
        }
    }
}

public protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
}

enum LaunchAtLoginBackendStatus {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LaunchAtLoginBackend: AnyObject {
    var serviceStatus: LaunchAtLoginBackendStatus { get }
    func register() throws
    func unregister() throws
}

public final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let backend: any LaunchAtLoginBackend

    public convenience init() {
        self.init(backend: SystemLaunchAtLoginBackend())
    }

    init(backend: any LaunchAtLoginBackend) {
        self.backend = backend
    }

    public var status: LaunchAtLoginStatus {
        switch backend.serviceStatus {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        }
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let currentStatus = status
        if enabled {
            switch currentStatus {
            case .enabled, .requiresApproval:
                return currentStatus
            case .unavailable:
                throw LaunchAtLoginControllerError.unavailable
            case .disabled:
                do {
                    try backend.register()
                } catch {
                    throw LaunchAtLoginControllerError.registrationFailed(
                        error.localizedDescription
                    )
                }
            }
        } else {
            switch currentStatus {
            case .disabled:
                return .disabled
            case .unavailable:
                throw LaunchAtLoginControllerError.unavailable
            case .enabled, .requiresApproval:
                do {
                    try backend.unregister()
                } catch {
                    throw LaunchAtLoginControllerError.unregistrationFailed(
                        error.localizedDescription
                    )
                }
            }
        }

        return status
    }
}

private final class SystemLaunchAtLoginBackend: LaunchAtLoginBackend {
    private let service = SMAppService.mainApp

    var serviceStatus: LaunchAtLoginBackendStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
