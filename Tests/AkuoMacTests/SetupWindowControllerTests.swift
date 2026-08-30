import AppKit
import XCTest
@testable import AkuoMac

@MainActor
final class SetupWindowControllerTests: XCTestCase {
    func testFirstLaunchWaitsForApplicationLaunchCompletionBeforeShowingSetup() {
        let controller = makeController(onboardingCompleted: { false })
        defer { controller.close() }
        let launchCoordinator = SetupWindowLaunchCoordinator()

        launchCoordinator.configure(controller)

        XCTAssertNil(controller.setupWindow)

        launchCoordinator.applicationDidFinishLaunching()

        XCTAssertTrue(controller.setupWindow?.isVisible == true)
    }

    func testLateControllerConfigurationStillPresentsAfterApplicationLaunchCompletion() {
        let controller = makeController(onboardingCompleted: { false })
        defer { controller.close() }
        let launchCoordinator = SetupWindowLaunchCoordinator()

        launchCoordinator.applicationDidFinishLaunching()
        XCTAssertNil(controller.setupWindow)

        launchCoordinator.configure(controller)

        XCTAssertTrue(controller.setupWindow?.isVisible == true)
    }

    func testRepeatedLaunchCompletionReusesTheSameVisibleSetupWindow() {
        let controller = makeController(onboardingCompleted: { false })
        defer { controller.close() }
        let launchCoordinator = SetupWindowLaunchCoordinator()
        launchCoordinator.configure(controller)
        launchCoordinator.applicationDidFinishLaunching()
        let firstWindow = try! XCTUnwrap(controller.setupWindow)

        launchCoordinator.applicationDidFinishLaunching()

        XCTAssertTrue(controller.setupWindow === firstWindow)
        XCTAssertTrue(firstWindow.isVisible)
    }

    func testCompletedOnboardingAtLaunchCompletionDoesNotCreateSetupWindow() {
        var onboardingCompleted = false
        let controller = makeController(onboardingCompleted: { onboardingCompleted })
        defer { controller.close() }
        let launchCoordinator = SetupWindowLaunchCoordinator()
        launchCoordinator.configure(controller)
        onboardingCompleted = true

        launchCoordinator.applicationDidFinishLaunching()

        XCTAssertNil(controller.setupWindow)
    }

    func testMenuPresentationReusesAndReopensTheSameSetupWindow() {
        let controller = makeController(onboardingCompleted: { false })
        defer { controller.close() }

        controller.presentFromMenu()
        let firstWindow = try! XCTUnwrap(controller.setupWindow)
        XCTAssertTrue(firstWindow.isVisible)

        controller.close()
        XCTAssertFalse(firstWindow.isVisible)

        controller.presentFromMenu()

        XCTAssertTrue(controller.setupWindow === firstWindow)
        XCTAssertTrue(firstWindow.isVisible)
    }

    func testMenuPresentationEnforcesSetupContentSizeAfterAttachingCollapsingContent() {
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _ in CollapsingContentViewController() }
        )
        defer { controller.close() }

        controller.presentFromMenu()
        let firstWindow = try! XCTUnwrap(controller.setupWindow)

        assertSetupContentSize(firstWindow)
        XCTAssertTrue(firstWindow.isVisible)

        controller.close()
        controller.presentFromMenu()

        XCTAssertTrue(controller.setupWindow === firstWindow)
        XCTAssertTrue(firstWindow.isVisible)
        assertSetupContentSize(firstWindow)
    }

    private func makeController(
        onboardingCompleted: @escaping () -> Bool
    ) -> SetupWindowController {
        SetupWindowController(
            refreshState: {},
            onboardingCompleted: onboardingCompleted,
            makeContentViewController: { _ in NSViewController() }
        )
    }

    private func assertSetupContentSize(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let contentSize = window.contentView?.bounds.size else {
            XCTFail("setup window has no content view", file: file, line: line)
            return
        }

        XCTAssertEqual(contentSize.width, 440, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(contentSize.height, 460, accuracy: 0.5, file: file, line: line)
    }
}

private final class CollapsingContentViewController: NSViewController {
    override var preferredContentSize: NSSize {
        get { NSSize(width: 70, height: 3141) }
        set {}
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 70, height: 3141))
    }
}
