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

    func testLegacyOneArgumentContentFactoryInitializerRemainsAvailable() {
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _ in NSViewController() }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        XCTAssertTrue(controller.setupWindow?.isVisible == true)
    }

    func testMenuReopenRetainsWindowButCreatesFreshSetupContent() {
        var contentControllerFactoryCalls = 0
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, _ in
                contentControllerFactoryCalls += 1
                return NSViewController()
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()
        let firstWindow = try! XCTUnwrap(controller.setupWindow)
        let firstContentController = try! XCTUnwrap(firstWindow.contentViewController)

        controller.close()
        controller.presentFromMenu()

        let secondContentController = try! XCTUnwrap(firstWindow.contentViewController)
        XCTAssertTrue(controller.setupWindow === firstWindow)
        XCTAssertEqual(contentControllerFactoryCalls, 2)
        XCTAssertFalse(firstContentController === secondContentController)
    }

    func testMenuReopenRearmsCompletionAndRejectsStaleOrDuplicateCallbacks() {
        var completions: [SetupPresentationCompletion] = []
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, completion in
                completions.append(completion)
                return NSViewController()
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()
        let setupWindow = try! XCTUnwrap(controller.setupWindow)
        let firstCompletion = try! XCTUnwrap(completions.first)

        XCTAssertTrue(firstCompletion.complete())
        XCTAssertFalse(firstCompletion.complete())
        XCTAssertFalse(setupWindow.isVisible)

        controller.presentFromMenu()
        let secondCompletion = try! XCTUnwrap(completions.last)
        XCTAssertEqual(completions.count, 2)
        XCTAssertTrue(setupWindow.isVisible)

        controller.presentFromMenu()
        XCTAssertEqual(completions.count, 2)

        XCTAssertFalse(firstCompletion.complete())
        XCTAssertTrue(setupWindow.isVisible)
        XCTAssertTrue(secondCompletion.complete())
        XCTAssertFalse(secondCompletion.complete())
        XCTAssertFalse(setupWindow.isVisible)
    }

    func testMenuPresentationEnforcesSetupContentSizeAfterAttachingCollapsingContent() {
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, _ in CollapsingContentViewController() }
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
            makeContentViewController: { _, _ in NSViewController() }
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
