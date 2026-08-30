import SwiftUI

struct TestAreaView: View {
    @State private var editorText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Akuo Test Area", systemImage: "character.cursor.ibeam")
                .font(.title2.weight(.semibold))

            Text("Try a wrong-layout word, then type a space. Akuo uses the same global correction path here as in every other app.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Text("akuo → שלום")
                Text("יקךךם → hello")
            }
            .font(.callout.monospaced())

            TextEditor(text: $editorText)
                .font(.body)
                .padding(6)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35))
                }
                .frame(minHeight: 150)
        }
        .padding(20)
        .onDisappear {
            editorText = ""
        }
    }
}
