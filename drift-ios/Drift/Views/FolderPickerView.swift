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
                    .foregroundStyle(.tint)

                Text("Drift")
                    .font(.largeTitle.weight(.semibold))

                Text("Pick the folder where your notes live.\niCloud Drive works great.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                showingPicker = true
            } label: {
                Text("Choose Folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
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
