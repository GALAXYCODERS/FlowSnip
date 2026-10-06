import Cocoa
import SwiftUI
import WebKit

@MainActor
struct AnswerMarkdownView: View {
    let text: String
    @State private var height: CGFloat = 24
    @State private var failed = false

    var body: some View {
        if failed {
            Text(text).font(.system(size: 13)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            AnswerWebView(text: text, height: $height, failed: $failed)
                .frame(height: height)
        }
    }
}

@MainActor
struct AnswerWebView: NSViewRepresentable {
    let text: String
    @Binding var height: CGFloat
    @Binding var failed: Bool

    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = Self.configuration()
        configuration.userContentController.add(context.coordinator, name: "answerHeight")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "AnswerRenderer") {
            context.coordinator.documentURL = url
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            Task { failed = true }
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleRender()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.renderTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "answerHeight")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AnswerWebView
        weak var webView: WKWebView?
        var documentURL: URL?
        var renderTask: Task<Void, Never>?
        private var ready = false
        private var renderedText: String?

        init(_ parent: AnswerWebView) { self.parent = parent }

        func scheduleRender() {
            guard ready, parent.text != renderedText else { return }
            renderTask?.cancel()
            renderTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard let self, let webView = self.webView else { return }
                let text = self.parent.text
                do {
                    _ = try await webView.callAsyncJavaScript("window.renderAnswer(text)", arguments: ["text": text], in: nil, contentWorld: .page)
                    self.renderedText = text
                } catch {
                    if !Task.isCancelled { self.parent.failed = true }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            scheduleRender()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.failed = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.failed = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.failed = true }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let value = message.body as? Double, value.isFinite else { return }
            let height = max(24, ceil(value))
            if abs(parent.height - height) > 0.5 { parent.height = height }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if !ready && navigationAction.request.url == documentURL {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}