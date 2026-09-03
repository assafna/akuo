import AppKit

@MainActor
public final class SetupPresentationCompletion {
    private let completePresentation: () -> Bool

    init(completePresentation: @escaping () -> Bool) {
        self.completePresentation = completePresentation
    }

    @discardableResult
    public func complete() -> Bool {
        completePresentation()
    }
}

@MainActor
public final class SetupWindowController {
    private struct Presentation {
        let generation: Int
        let completion: SetupPresentationCompletion
    }

    private static let setupContentSize = NSSize(width: 440, height: 460)
    private let refreshState: () -> Void
    private let onboardingCompleted: () -> Bool
    private let makeContentViewController: (SetupWindowController, SetupPresentationCompletion) -> NSViewController
    private var presentationGeneration = 0
    private var completedPresentationGeneration: Int?
    public private(set) var setupWindow: NSWindow?

    public init(
        refreshState: @escaping () -> Void,
        onboardingCompleted: @escaping () -> Bool,
        makeContentViewController: @escaping (SetupWindowController, SetupPresentationCompletion) -> NSViewController
    ) {
        self.refreshState = refreshState
        self.onboardingCompleted = onboardingCompleted
        self.makeContentViewController = makeContentViewController
    }

    public convenience init(
        refreshState: @escaping () -> Void,
        onboardingCompleted: @escaping () -> Bool,
        makeContentViewController: @escaping (SetupWindowController) -> NSViewController
    ) {
        self.init(
            refreshState: refreshState,
            onboardingCompleted: onboardingCompleted,
            makeContentViewController: { controller, _ in
                makeContentViewController(controller)
            }
        )
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
        guard !window.isVisible else {
            _ = activate(window, generation: presentationGeneration)
            return
        }
        let presentation = makePresentation()
        guard installPresentationContent(in: window, presentation: presentation) else { return }
        _ = activate(window, generation: presentation.generation)
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
        window.contentMinSize = Self.setupContentSize
        window.contentMaxSize = Self.setupContentSize
        window.setContentSize(Self.setupContentSize)
        return window
    }

    private func installPresentationContent(in window: NSWindow, presentation: Presentation) -> Bool {
        let contentViewController = makeContentViewController(self, presentation.completion)
        _ = contentViewController.view
        guard isCurrent(presentation, for: window) else { return false }

        window.contentViewController = contentViewController
        guard isCurrent(presentation, for: window) else { return false }
        window.setContentSize(Self.setupContentSize)
        return isCurrent(presentation, for: window)
    }

    private func activate(_ window: NSWindow, generation: Int) -> Bool {
        guard isCurrent(generation, for: window) else { return false }
        window.center()
        guard isCurrent(generation, for: window) else { return false }
        window.orderFrontRegardless()
        guard isCurrent(generation, for: window) else { return false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard isCurrent(generation, for: window) else { return false }
        window.makeKey()
        return isCurrent(generation, for: window)
    }

    private func makePresentation() -> Presentation {
        presentationGeneration += 1
        let generation = presentationGeneration
        completedPresentationGeneration = nil
        let completion = SetupPresentationCompletion { [weak self] in
            self?.completePresentation(generation: generation) ?? false
        }
        return Presentation(generation: generation, completion: completion)
    }

    private func isCurrent(_ presentation: Presentation, for window: NSWindow) -> Bool {
        isCurrent(presentation.generation, for: window)
    }

    private func isCurrent(_ generation: Int, for window: NSWindow) -> Bool {
        setupWindow === window
            && presentationGeneration == generation
            && completedPresentationGeneration != generation
    }

    private func completePresentation(generation: Int) -> Bool {
        guard presentationGeneration == generation,
              completedPresentationGeneration != generation
        else {
            return false
        }

        completedPresentationGeneration = generation
        close()
        return true
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
