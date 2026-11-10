import SwiftUI
import WebKit

// MARK: - Editor (CodeMirror in a WKWebView)

final class EditorHost: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var onCode: ((String) -> Void)?
    private var ready = false
    private var queue: [String] = []

    init(base: URL) {
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.configuration.userContentController.add(self, name: "bridge")
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: base.appendingPathComponent("index.html")))
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let t = d["t"] as? String else { return }
        if t == "ready" {
            ready = true
            queue.forEach { webView.evaluateJavaScript($0) }
            queue.removeAll()
        } else if t == "code", let code = d["code"] as? String {
            onCode?(code)
        } else if t == "haptic" {
            haptic.impactOccurred()
        }
    }

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    func setOptions(indent: Int, autoClose: Bool, chips: Bool, haptics: Bool) {
        run("window.cf.setOptions({indent: \(indent), autoClose: \(autoClose), chips: \(chips), haptics: \(haptics)})")
    }

    private func run(_ js: String) {
        if ready { webView.evaluateJavaScript(js) } else { queue.append(js) }
    }

    private func lit(_ s: String) -> String {
        // JSON string literal is a valid JS string literal.
        if let d = try? JSONSerialization.data(withJSONObject: [s]), let j = String(data: d, encoding: .utf8) {
            return String(j.dropFirst().dropLast())
        }
        return "\"\""
    }

    func setCode(_ code: String) { run("window.cf.setCode(\(lit(code)))") }
    func setTheme(_ name: String) { run("window.cf.setTheme(\(lit(name)))") }
    func setFontSize(_ px: Double) { run("window.cf.setFontSize(\(px))") }
    func clearDiagnostics() { run("window.cf.clearDiagnostics()") }
    func setDiagnostics(_ list: [Diagnostic]) {
        guard let d = try? JSONEncoder().encode(list), let s = String(data: d, encoding: .utf8) else { return }
        run("window.cf.setDiagnostics(\(s))")
    }

    func currentCode() async -> String? {
        guard ready else { return nil }
        let r = try? await webView.callAsyncJavaScript("return window.cf.getCode();", arguments: [:], in: nil, contentWorld: .page)
        return r as? String
    }

    @objc private func keyboardChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              webView.window != nil else { return }
        let frame = webView.convert(webView.bounds, to: nil)
        let overlap = max(0, frame.maxY - end.minY)
        run("window.cf.setKeyboard(\(Int(overlap)))")
    }
    @objc private func keyboardHidden(_ n: Notification) { run("window.cf.setKeyboard(0)") }
}

struct EditorWebView: UIViewRepresentable {
    let host: EditorHost
    func makeUIView(context: Context) -> WKWebView { host.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Engine (Clang-in-WebAssembly, headless)

final class EngineHost: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    private(set) var ready = false

    init(base: URL) {
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
        super.init()
        webView.configuration.userContentController.add(self, name: "bridge")
        webView.load(URLRequest(url: base.appendingPathComponent("engine.html")))
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let d = message.body as? [String: Any], d["t"] as? String == "engineReady" { ready = true }
    }

    private func waitReady() async {
        var n = 0
        while !ready && n < 300 { try? await Task.sleep(nanoseconds: 100_000_000); n += 1 }
    }

    private func call<T: Decodable>(_ body: String, _ args: [String: Any]) async throws -> T {
        await waitReady()
        let r = try await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
        guard let s = r as? String, let d = s.data(using: .utf8) else {
            throw NSError(domain: "engine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engine returned nothing"])
        }
        return try JSONDecoder().decode(T.self, from: d)
    }

    func compile(_ code: String, std: String, checks: Bool) async throws -> CompileResult {
        try await call("return JSON.stringify(await cfEngine.compile(code, { std: std, checks: checks }));",
                       ["code": code, "std": std, "checks": checks])
    }

    func runOne(input: String, expected: String?, timeLimitMs: Int) async throws -> RunResult {
        let exp: Any = expected ?? NSNull()
        return try await call("return JSON.stringify(await cfEngine.runOne(input, expected, { timeLimitMs: tl }));",
                              ["input": input, "expected": exp, "tl": timeLimitMs])
    }
}

struct EngineWebView: UIViewRepresentable {
    let host: EngineHost
    func makeUIView(context: Context) -> WKWebView { host.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Problem reader (statement rendered with KaTeX)

final class ReaderHost: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private var ready = false
    private var queue: [String] = []

    init(base: URL) {
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.configuration.userContentController.add(self, name: "bridge")
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.load(URLRequest(url: base.appendingPathComponent("reader.html")))
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let d = message.body as? [String: Any], d["t"] as? String == "readerReady" {
            ready = true
            queue.forEach { webView.evaluateJavaScript($0) }
            queue.removeAll()
        }
    }

    /// Links inside statements open nothing: this is a reader, not a browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    private func run(_ js: String) { if ready { webView.evaluateJavaScript(js) } else { queue.append(js) } }

    private func json(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]),
              let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }

    func render(_ p: Problem?) {
        guard let p = p, let html = p.statementHTML else { run("window.cfReader.render(null)"); return }
        // The reader shows the original samples; split-out cases carry a label and are test-tab only.
        let samples = p.tests.filter { $0.isSample && ($0.isCombined == true || $0.label == nil) }
            .map { ["input": $0.input, "output": $0.expected] }
        let title = p.title
        var payload: [String: Any] = [
            "title": title, "html": html, "samples": samples,
            "timeLimit": "\(Double(p.timeLimitMs) / 1000) seconds".replacingOccurrences(of: ".0 ", with: " "),
        ]
        if let m = p.memoryLimit { payload["memoryLimit"] = m }
        if let io = p.ioMode { payload["input"] = io; payload["output"] = io.replacingOccurrences(of: "input", with: "output") }
        if let t = p.tags { payload["tags"] = t }
        if let r = p.rating { payload["rating"] = r }
        run("window.cfReader.render(\(json(payload)))")
    }

    func setTheme(_ name: String) { run("window.cfReader.setTheme(\(json(name)))") }
    func setFontSize(_ px: Double) { run("window.cfReader.setFontSize(\(px))") }
}

struct ReaderWebView: UIViewRepresentable {
    let host: ReaderHost
    func makeUIView(context: Context) -> WKWebView { host.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
