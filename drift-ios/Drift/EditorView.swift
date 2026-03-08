import SwiftUI
import WebKit

struct EditorView: UIViewRepresentable {
    @Binding var content: String
    var onContentChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Register message handlers for JS -> Swift communication
        userContentController.add(context.coordinator, name: "contentChanged")
        userContentController.add(context.coordinator, name: "editorReady")
        userContentController.add(context.coordinator, name: "openUrl")

        config.userContentController = userContentController

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false // CodeMirror handles scrolling

        // Disable link preview and data detectors
        webView.allowsLinkPreview = false

        // Load the editor HTML
        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only push content if it changed externally (not from JS)
        if context.coordinator.lastContentFromJS != content {
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            webView.evaluateJavaScript("setContent(`\(escaped)`)")
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: EditorView
        var webView: WKWebView?
        var lastContentFromJS: String = ""

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "contentChanged":
                if let content = message.body as? String {
                    lastContentFromJS = content
                    DispatchQueue.main.async {
                        self.parent.content = content
                        self.parent.onContentChange(content)
                    }
                }
            case "editorReady":
                // Editor is loaded, set initial content
                let escaped = parent.content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                webView?.evaluateJavaScript("setContent(`\(escaped)`)")

                // Set theme based on current appearance
                let isDark = UITraitCollection.current.userInterfaceStyle == .dark
                webView?.evaluateJavaScript("setTheme('\(isDark ? "dark" : "light")')")
            case "openUrl":
                if let urlString = message.body as? String, let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            default:
                break
            }
        }
    }
}
