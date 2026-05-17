import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @Environment(NoteStore.self) private var store
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.accent.opacity(0.55))

                Text("Drift")
                    .font(.custom("Newsreader16pt-Italic", size: 48))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: 6) {
                    Text("Pick the folder where your notes live.")
                    Text("If you use the desktop app, look for iCloud Drive › Documents › Drift.")
                        .foregroundStyle(Theme.ink.opacity(0.45))
                }
                .font(Theme.rowSub())
                .foregroundStyle(Theme.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            }

            Spacer()

            Button {
                showingPicker = true
            } label: {
                Text("Choose Folder")
                    .font(.custom("JetBrainsMono-Regular", size: 16).weight(.medium))
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Theme.paper.ignoresSafeArea())
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.setFolder(url)
                }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert("Heads up", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

#Preview {
    FolderPickerView()
        .environment(NoteStore())
}
