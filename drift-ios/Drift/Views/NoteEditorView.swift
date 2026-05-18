import SwiftUI
import UIKit

struct NoteEditorView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let note: Note
    let autoFocus: Bool
    /// Called when the user taps the back chevron. The parent clears its
    /// selection state so the NavigationSplitView pops back to the list on
    /// iPhone and shows `detailEmpty` on iPad.
    let onDismiss: (() -> Void)?
    @State private var workingNote: Note
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isReadMode: Bool = false
    @State private var scrollY: CGFloat = 0

    init(note: Note, autoFocus: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.note = note
        self.autoFocus = autoFocus
        self.onDismiss = onDismiss
        self._workingNote = State(initialValue: note)
        // Read file contents synchronously here so `text` is populated before
        // the push transition begins. Loading in `.onAppear` causes a visible
        // pop-in: the body and large italic title only render after the slide
        // settles, instead of riding in with the rest of the view.
        let initial = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        self._text = State(initialValue: initial)
        self._initialText = State(initialValue: initial)
    }

    private var backButtonOpacity: Double {
        let fadeStart: CGFloat = 8
        let fadeEnd: CGFloat = 76
        let raw = 1 - ((max(0, scrollY) - fadeStart) / (fadeEnd - fadeStart))
        return Double(min(1, max(0, raw)))
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = windowSafeAreaTop(for: proxy)

            ZStack(alignment: .topLeading) {
                EditorTextView(
                    text: $text,
                    isEditable: !isReadMode,
                    autoFocus: autoFocus,
                    topContentInset: topInset + 70,
                    onToggleReadMode: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReadMode.toggle()
                        }
                    },
                    onScroll: { y in scrollY = y }
                )
                .ignoresSafeArea(.container, edges: .top)

                LinearGradient(
                    stops: [
                        .init(color: Theme.paper.opacity(0.92), location: 0),
                        .init(color: Theme.paper.opacity(0.58), location: 0.58),
                        .init(color: Theme.paper.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topInset + 88)
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)

                floatingBackButton
                    .opacity(backButtonOpacity)
                    .allowsHitTesting(backButtonOpacity > 0.05)
                    .animation(.easeOut(duration: 0.14), value: backButtonOpacity)
                    .padding(.leading, 18)
                    .padding(.top, topInset + 4)

                if isReadMode {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent.opacity(0.45))
                        .padding(.top, topInset + 18)
                        .padding(.trailing, 18)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.paper.ignoresSafeArea())
        .background(SystemBackGestureEnabler())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: text) { _, newValue in
            guard newValue != initialText else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
                workingNote = store.saveContents(newValue, for: workingNote)
                initialText = newValue
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if text != initialText {
                workingNote = store.saveContents(text, for: workingNote)
            }
            isReadMode = false
        }
    }

    private func windowSafeAreaTop(for proxy: GeometryProxy) -> CGFloat {
        if let windowInset = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?
            .safeAreaInsets
            .top,
           windowInset > 0 {
            return windowInset
        }

        if proxy.safeAreaInsets.top > 0 {
            return proxy.safeAreaInsets.top
        }

        return UIDevice.current.userInterfaceIdiom == .phone ? 59 : 24
    }

    private var floatingBackButton: some View {
        Button(action: dismissEditor) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Back")
        .floatingGlassIconButton()
    }

    private func dismissEditor() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

private struct SystemBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Host { Host() }

    func updateUIViewController(_ uiViewController: Host, context: Context) {
        DispatchQueue.main.async {
            uiViewController.enableSystemPopGesture()
        }
    }

    final class Host: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSystemPopGesture()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if activeNavigationController()?.interactivePopGestureRecognizer?.delegate === self {
                activeNavigationController()?.interactivePopGestureRecognizer?.delegate = nil
            }
        }

        func enableSystemPopGesture() {
            guard let navigationController = activeNavigationController(),
                  navigationController.viewControllers.count > 1,
                  let popGesture = navigationController.interactivePopGestureRecognizer
            else { return }

            popGesture.isEnabled = true
            popGesture.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer == activeNavigationController()?.interactivePopGestureRecognizer else {
                return true
            }
            return (activeNavigationController()?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer == activeNavigationController()?.interactivePopGestureRecognizer
        }

        private func activeNavigationController() -> UINavigationController? {
            if let navigationController {
                return navigationController
            }
            return view.window?.rootViewController?.findNavigationController()
        }
    }
}

private extension UIViewController {
    func findNavigationController() -> UINavigationController? {
        if let navigationController = self as? UINavigationController {
            return navigationController
        }
        if let navigationController {
            return navigationController
        }
        for child in children {
            if let navigationController = child.findNavigationController() {
                return navigationController
            }
        }
        return presentedViewController?.findNavigationController()
    }
}

extension View {
    func floatingGlassIconButton() -> some View {
        buttonStyle(FloatingGlassIconButtonStyle())
    }
}

private struct FloatingGlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular.tint(Theme.paper.opacity(0.22)).interactive(), in: Circle())
            .shadow(color: Theme.accent.opacity(0.10), radius: 20, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
