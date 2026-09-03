import SwiftUI
import AppKit
import AkuoMac

@main
@MainActor
struct AkuoApp: App {
    @StateObject private var model: AppModel
    private let setupWindowController: SetupWindowController
    @NSApplicationDelegateAdaptor(AkuoApplicationDelegate.self) private var applicationDelegate

    init() {
        let sharedModel = AppModel.live()
        _model = StateObject(wrappedValue: sharedModel)

        let setupWindowController = SetupWindowController(
            refreshState: {
                sharedModel.refresh()
            },
            onboardingCompleted: {
                sharedModel.onboardingCompleted
            },
            makeContentViewController: { _, completion in
                NSHostingController(
                    rootView: SetupView(model: sharedModel, completion: completion)
                )
            }
        )
        self.setupWindowController = setupWindowController
        applicationDelegate.configure(setupWindowController)
    }

    var body: some Scene {
        MenuBarExtra("Akuo", systemImage: "character.cursor.ibeam") {
            MenuBarView(model: model) {
                setupWindowController.presentFromMenu()
            }
        }
        .menuBarExtraStyle(.window)

        Window("Akuo Test Area", id: "test-area") {
            TestAreaView()
                .frame(width: 460, height: 340)
        }
        .defaultSize(width: 460, height: 340)
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class AkuoApplicationDelegate: NSObject, NSApplicationDelegate {
    private let setupLaunchCoordinator = SetupWindowLaunchCoordinator()

    func configure(_ setupWindowController: SetupWindowController) {
        setupLaunchCoordinator.configure(setupWindowController)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupLaunchCoordinator.applicationDidFinishLaunching()
    }
}
