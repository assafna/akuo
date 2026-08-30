import XCTest
@testable import AkuoMac

final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitializationOnlyReadsStatus() {
        let backend = FakeLaunchAtLoginBackend(status: .enabled)

        let controller = LaunchAtLoginController(backend: backend)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testEnablingRegistersMainAppAndReflectsEnabledStatus() throws {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.statusAfterRegister = .enabled
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(true)

        XCTAssertEqual(status, .enabled)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testDisablingUnregistersMainAppAndReflectsDisabledStatus() throws {
        let backend = FakeLaunchAtLoginBackend(status: .enabled)
        backend.statusAfterUnregister = .notRegistered
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(false)

        XCTAssertEqual(status, .disabled)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 1)
    }

    func testAlreadyEnabledRequestIsIdempotent() throws {
        let backend = FakeLaunchAtLoginBackend(status: .enabled)
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(true)

        XCTAssertEqual(status, .enabled)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testAlreadyDisabledRequestIsIdempotent() throws {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(false)

        XCTAssertEqual(status, .disabled)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertEqual(backend.unregisterCalls, 0)
    }

    func testExistingApprovalRequirementDoesNotRegisterAgain() throws {
        let backend = FakeLaunchAtLoginBackend(status: .requiresApproval)
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(true)

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(backend.registerCalls, 0)
    }

    func testSuccessfulRegistrationThatRequiresApprovalDoesNotClaimEnabled() throws {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(backend: backend)

        let status = try controller.setEnabled(true)

        XCTAssertEqual(status, .requiresApproval)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(backend.registerCalls, 1)
    }

    func testNotFoundMapsToUnavailable() {
        let backend = FakeLaunchAtLoginBackend(status: .notFound)
        let controller = LaunchAtLoginController(backend: backend)

        XCTAssertEqual(controller.status, .unavailable)
        XCTAssertFalse(controller.isEnabled)
    }

    func testRegistrationFailureIsMappedWithoutRetry() {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.registerError = FakeLaunchAtLoginError.registration
        let controller = LaunchAtLoginController(backend: backend)

        XCTAssertThrowsError(try controller.setEnabled(true)) { error in
            XCTAssertEqual(
                error as? LaunchAtLoginControllerError,
                .registrationFailed("The registration operation failed.")
            )
        }
        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertEqual(controller.status, .disabled)
    }

    func testUnregistrationFailureIsMappedWithoutRetry() {
        let backend = FakeLaunchAtLoginBackend(status: .enabled)
        backend.unregisterError = FakeLaunchAtLoginError.unregistration
        let controller = LaunchAtLoginController(backend: backend)

        XCTAssertThrowsError(try controller.setEnabled(false)) { error in
            XCTAssertEqual(
                error as? LaunchAtLoginControllerError,
                .unregistrationFailed("The unregistration operation failed.")
            )
        }
        XCTAssertEqual(backend.unregisterCalls, 1)
        XCTAssertEqual(controller.status, .enabled)
    }
}

private final class FakeLaunchAtLoginBackend: LaunchAtLoginBackend {
    var serviceStatus: LaunchAtLoginBackendStatus
    var statusAfterRegister: LaunchAtLoginBackendStatus?
    var statusAfterUnregister: LaunchAtLoginBackendStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: LaunchAtLoginBackendStatus) {
        serviceStatus = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { serviceStatus = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { serviceStatus = statusAfterUnregister }
    }
}

private enum FakeLaunchAtLoginError: LocalizedError {
    case registration
    case unregistration

    var errorDescription: String? {
        switch self {
        case .registration:
            "The registration operation failed."
        case .unregistration:
            "The unregistration operation failed."
        }
    }
}
