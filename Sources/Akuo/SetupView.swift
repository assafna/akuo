import SwiftUI
import AkuoMac

struct SetupView: View {
    @ObservedObject var model: AppModel
    private let completion: SetupPresentationCompletion

    init(model: AppModel, completion: SetupPresentationCompletion) {
        self.model = model
        self.completion = completion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Set up Akuo", systemImage: "character.cursor.ibeam")
                .font(.title2.weight(.semibold))

            Text("Akuo needs one permission to recognize and correct typing across your Mac. Processing stays on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SetupStep(
                title: "Accessibility",
                detail: model.permissionGranted
                    ? "Granted"
                    : "Open System Settings → Privacy & Security → Accessibility and enable Akuo.",
                isReady: model.permissionGranted
            )

            if !model.permissionGranted {
                Button("Request Accessibility Access") {
                    model.requestAccessibility()
                }
            }

            SetupStep(
                title: "English keyboard",
                detail: model.inputSourceReadiness.englishAvailable
                    ? "ABC or U.S. is ready."
                    : "Add ABC (preferred) or U.S.",
                isReady: model.inputSourceReadiness.englishAvailable
            )

            SetupStep(
                title: "Hebrew keyboard",
                detail: model.inputSourceReadiness.hebrewAvailable
                    ? "Standard Hebrew is ready."
                    : "Add Hebrew. Hebrew – QWERTY is not supported in version 1.",
                isReady: model.inputSourceReadiness.hebrewAvailable
            )

            if !model.inputSourceReadiness.englishAvailable
                || !model.inputSourceReadiness.hebrewAvailable {
                Text("Add input sources in System Settings → Keyboard → Text Input → Input Sources → Edit…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Recheck Setup") {
                    model.refresh()
                }
                Spacer()
                Button("Finish") {
                    model.completeOnboarding()
                    if model.onboardingCompleted {
                        handleCompletion()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCompleteSetup)
            }
        }
        .padding(20)
        .onAppear {
            model.refresh()
        }
        .onChange(of: model.onboardingCompleted) { completed in
            guard completed else { return }
            handleCompletion()
        }
    }

    private func handleCompletion() {
        completion.complete()
    }
}

private struct SetupStep: View {
    let title: String
    let detail: String
    let isReady: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
