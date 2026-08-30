import AppKit

@MainActor
public final class SetupWindowController {
    private static let setupContentSize = NSSize(width: 440, height: 460)
    private let refreshState: () -> Void
    private let onboardingCompleted: () -> Bool
    private let makeContentViewController: (SetupWindowController) -> NSViewController
    public private(set) var setupWindow: NSWindow?

    public init(
        refreshState: @escaping () -> Void,
        onboardingCompleted: @escaping () -> Bool,
        makeContentViewController: @escaping (SetupWindowController) -> NSViewController
    ) {
        self.refreshState = refreshState
        self.onboardingCompleted = onboardingCompleted
        self.makeContentViewController = makeContentViewController
    }

    public func presentFirstLaunchIfNeeded() {
        refreshState()
        guard !onboardingCompleted() else { return }
        presentWindow()
    }

    public func presentFromMenu() {
        refreshState()
        presentWindow()
    }

    public func close() {
        setupWindow?.close()
    }

    private func presentWindow() {
        let window = setupWindow ?? makeWindow()
        setupWindow = window
        window.center()
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.setupContentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Akuo Setup"
        window.isReleasedWhenClosed = false
        window.contentViewController = makeContentViewController(self)
        window.contentMinSize = Self.setupContentSize
        window.contentMaxSize = Self.setupContentSize
        window.setContentSize(Self.setupContentSize)
        return window
    }
}

@MainActor
public final class SetupWindowLaunchCoordinator {
    private weak var setupWindowController: SetupWindowController?
    private var launchHasCompleted = false
    private var deliveredFirstLaunchPresentation = false

    public init() {}

    public func configure(_ setupWindowController: SetupWindowController) {
        self.setupWindowController = setupWindowController
        deliverFirstLaunchPresentationIfReady()
    }

    public func applicationDidFinishLaunching() {
        launchHasCompleted = true
        deliverFirstLaunchPresentationIfReady()
    }

    private func deliverFirstLaunchPresentationIfReady() {
        guard launchHasCompleted,
              !deliveredFirstLaunchPresentation,
              let setupWindowController
        else {
            return
        }

        deliveredFirstLaunchPresentation = true
        setupWindowController.presentFirstLaunchIfNeeded()
    }
}
