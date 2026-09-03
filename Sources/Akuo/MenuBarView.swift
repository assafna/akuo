import AppKit
import SwiftUI
import AkuoCore
import AkuoMac

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Akuo")
                        .font(.headline)
                    Text(model.status.menuLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Toggle("Automatic correction", isOn: Binding(
                get: { model.isEnabled },
                set: model.setEnabled
            ))
            .toggleStyle(.switch)

            Picker("Force conversion", selection: Binding(
                get: { model.forceConversionGesture },
                set: model.setForceConversionGesture
            )) {
                Text("Double-tap Shift")
                    .tag(ForceConversionGesture.doubleShift)
                Text("Press both Shift keys")
                    .tag(ForceConversionGesture.bothShifts)
            }
            .pickerStyle(.menu)

            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: model.setLaunchAtLogin
            ))
            .toggleStyle(.switch)

            if let message = model.launchAtLoginMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    title: "Accessibility",
                    detail: model.permissionGranted ? "Granted" : "Needed",
                    isReady: model.permissionGranted
                )
                StatusRow(
                    title: "English input",
                    detail: model.inputSourceReadiness.englishAvailable ? "Ready" : "Missing",
                    isReady: model.inputSourceReadiness.englishAvailable
                )
                StatusRow(
                    title: "Hebrew input",
                    detail: model.inputSourceReadiness.hebrewAvailable ? "Ready" : "Missing",
                    isReady: model.inputSourceReadiness.hebrewAvailable
                )
            }

            Divider()

            DetailRow(title: "Current language", value: languageLabel)
            DetailRow(title: "Corrections", value: model.correctionCount.formatted())

            Divider()

            Button {
                openWindow(id: "test-area")
            } label: {
                Label("Open Test Area", systemImage: "rectangle.and.pencil.and.ellipsis")
            }

            if model.needsSetup {
                Button {
                    openSetup()
                } label: {
                    Label("Open Setup", systemImage: "gearshape")
                }
            }

            Button("Quit Akuo", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 300)
        .onAppear {
            model.refresh()
        }
    }

    private var languageLabel: String {
        switch model.currentLanguage {
        case .english:
            "English"
        case .hebrew:
            "Hebrew"
        case nil:
            "Unknown"
        }
    }
}

private struct StatusRow: View {
    let title: String
    let detail: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
