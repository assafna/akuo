import AppKit
import SwiftUI
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
        var closeCount = 0
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: setupWindow,
            queue: .main
        ) { _ in
            closeCount += 1
        }
        defer { NotificationCenter.default.removeObserver(closeObserver) }

        XCTAssertTrue(firstCompletion.complete())
        XCTAssertFalse(firstCompletion.complete())
        XCTAssertFalse(setupWindow.isVisible)
        XCTAssertEqual(closeCount, 1)

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
        XCTAssertEqual(closeCount, 2)
    }

    func testCompletionDuringContentConstructionDoesNotPresentTheWindow() {
        var completionResult: Bool?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, completion in
                completionResult = completion.complete()
                return NSViewController()
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        XCTAssertEqual(completionResult, true)
        XCTAssertFalse(controller.setupWindow?.isVisible == true)
    }

    func testNestedPresentationDuringInitialContentConstructionKeepsOneCurrentWindow() {
        var contentFactoryCalls = 0
        var nestedPresentedWindow: NSWindow?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { controller, completion in
                contentFactoryCalls += 1
                if contentFactoryCalls == 1 {
                    XCTAssertTrue(completion.complete())
                    controller.presentFromMenu()
                    nestedPresentedWindow = controller.setupWindow
                }
                return NSViewController()
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        let retainedWindow = try! XCTUnwrap(controller.setupWindow)
        let nestedWindow = try! XCTUnwrap(nestedPresentedWindow)
        let visibleSetupWindows = NSApplication.shared.windows.filter {
            $0.title == "Akuo Setup" && $0.isVisible
        }
        XCTAssertEqual(contentFactoryCalls, 2)
        XCTAssertTrue(retainedWindow === nestedWindow)
        XCTAssertTrue(retainedWindow.isVisible)
        XCTAssertEqual(visibleSetupWindows.count, 1)
    }

    func testCompletionDuringContentAttachmentDoesNotShowCompletedWindow() {
        var completionResult: Bool?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, completion in
                CompletingOnLoadViewController {
                    completionResult = completion.complete()
                }
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        XCTAssertEqual(completionResult, true)
        XCTAssertFalse(controller.setupWindow?.isVisible == true)
    }

    func testNestedPresentationDuringContentAttachmentRetainsNestedContent() {
        var contentFactoryCalls = 0
        var createdOuterContentController: NSViewController?
        var createdNestedContentController: NSViewController?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { controller, completion in
                contentFactoryCalls += 1
                if contentFactoryCalls == 1 {
                    let contentController = CompletingOnLoadViewController {
                        XCTAssertTrue(completion.complete())
                        controller.presentFromMenu()
                    }
                    createdOuterContentController = contentController
                    return contentController
                }

                let contentController = NSViewController()
                createdNestedContentController = contentController
                return contentController
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        let retainedWindow = try! XCTUnwrap(controller.setupWindow)
        let outerContentController = try! XCTUnwrap(createdOuterContentController)
        let nestedContentController = try! XCTUnwrap(createdNestedContentController)
        XCTAssertEqual(contentFactoryCalls, 2)
        XCTAssertTrue(retainedWindow.isVisible)
        XCTAssertTrue(retainedWindow.contentViewController === nestedContentController)
        XCTAssertTrue(retainedWindow.contentView === nestedContentController.view)
        XCTAssertFalse(retainedWindow.contentViewController === outerContentController)
    }

    func testStaleReturnedControllerIsNotLoadedAfterNestedPresentation() {
        var contentFactoryCalls = 0
        var staleLoadCalls = 0
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { controller, completion in
                contentFactoryCalls += 1
                if contentFactoryCalls == 1 {
                    XCTAssertTrue(completion.complete())
                    controller.presentFromMenu()
                    return CompletingOnLoadViewController {
                        staleLoadCalls += 1
                        controller.close()
                    }
                }
                return NSViewController()
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        XCTAssertEqual(contentFactoryCalls, 2)
        XCTAssertEqual(staleLoadCalls, 0)
        XCTAssertTrue(controller.setupWindow?.isVisible == true)
    }

    func testNestedPresentationDuringContentControllerAssignmentRetainsNestedContent() {
        var contentFactoryCalls = 0
        var createdNestedContentController: NSViewController?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { controller, completion in
                contentFactoryCalls += 1
                if contentFactoryCalls == 1 {
                    return CompletingOnMoveToWindowViewController {
                        XCTAssertTrue(completion.complete())
                        controller.presentFromMenu()
                    }
                }

                let contentController = NSViewController()
                createdNestedContentController = contentController
                return contentController
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()

        let retainedWindow = try! XCTUnwrap(controller.setupWindow)
        let nestedContentController = try! XCTUnwrap(createdNestedContentController)
        XCTAssertEqual(contentFactoryCalls, 2)
        XCTAssertTrue(retainedWindow.isVisible)
        XCTAssertTrue(retainedWindow.contentViewController === nestedContentController)
        XCTAssertTrue(retainedWindow.contentView === nestedContentController.view)
    }

    func testCompletionDuringHostingOnAppearDoesNotShowCompletedWindow() {
        var completionResult: Bool?
        let controller = SetupWindowController(
            refreshState: {},
            onboardingCompleted: { false },
            makeContentViewController: { _, completion in
                NSHostingController(
                    rootView: CompletingOnAppearView {
                        completionResult = completion.complete()
                    }
                )
            }
        )
        defer { controller.close() }

        controller.presentFromMenu()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(completionResult, true)
        XCTAssertFalse(controller.setupWindow?.isVisible == true)
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

private final class CompletingOnLoadViewController: NSViewController {
    private let onLoad: () -> Void

    init(onLoad: @escaping () -> Void) {
        self.onLoad = onLoad
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        onLoad()
        view = NSView()
    }
}

private final class CompletingOnMoveToWindowViewController: NSViewController {
    private let onMoveToWindow: () -> Void

    init(onMoveToWindow: @escaping () -> Void) {
        self.onMoveToWindow = onMoveToWindow
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = CompletingOnMoveToWindowView(onMoveToWindow: onMoveToWindow)
    }
}

private final class CompletingOnMoveToWindowView: NSView {
    private let onMoveToWindow: () -> Void
    private var didMoveToWindow = false

    init(onMoveToWindow: @escaping () -> Void) {
        self.onMoveToWindow = onMoveToWindow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didMoveToWindow else { return }
        didMoveToWindow = true
        onMoveToWindow()
    }
}

private struct CompletingOnAppearView: View {
    let onAppear: () -> Void

    var body: some View {
        Color.clear.onAppear(perform: onAppear)
    }
}
