import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(NoteStore.self) private var store

    var body: some View {
        Group {
            if store.folderURL != nil {
                NoteListView()
            } else {
                FolderPickerView()
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .background(WindowPaperBackground())
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
}

private struct WindowPaperBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> PaperBackgroundView {
        let view = PaperBackgroundView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PaperBackgroundView, context: Context) {
        uiView.applyPaperBackground()
    }
}

private final class PaperBackgroundView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPaperBackground()
    }

    func applyPaperBackground() {
        window?.backgroundColor = Theme.paperUIColor
        window?.rootViewController?.applyPaperBackdrop()
    }
}

private extension UIViewController {
    func applyPaperBackdrop() {
        view.backgroundColor = Theme.paperUIColor
        view.isOpaque = true

        for child in children {
            child.applyPaperBackdrop()
        }

        presentedViewController?.applyPaperBackdrop()
    }
}
