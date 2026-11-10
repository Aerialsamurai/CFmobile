import SwiftUI
import WebKit

/// A visible browser used for every flow that needs the real Codeforces site:
/// login, problem import, submitting and contest registration.
/// It uses the default (persistent) website data store, so the login survives app restarts.
final class WebFlow: NSObject, ObservableObject, WKNavigationDelegate {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    @Published var title = ""
    @Published var loading = false
    @Published var currentURL = ""
    var onFinish: ((WKWebView) -> Void)?

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        title = webView.title ?? ""
        currentURL = webView.url?.absoluteString ?? ""
        onFinish?(webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false }
}

struct FlowWebView: UIViewRepresentable {
    let flow: WebFlow
    func makeUIView(context: Context) -> WKWebView { flow.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - JavaScript used on codeforces.com pages

enum CFScripts {
    /// JavaScript lives in Scripts/*.js (bundled) so it can be tested outside the app.
    static func load(_ name: String) -> String {
        guard let u = Bundle.main.url(forResource: name, withExtension: "js"),
              let t = try? String(contentsOf: u, encoding: .utf8) else { return "return JSON.stringify({ok:false, reason:'missing script \(name)'});" }
        return t
    }
    static var extractProblem: String { load("extractProblem") }
    static var submissionDetail: String { load("submissionDetail") }
    static var registeredContests: String { load("registeredContests") }

    /// Fills the submit form. Arguments: code, index, autoSubmit. Returns a status string.
    static let fillSubmit = """
    var f = document.querySelector('form.submit-form') || document.querySelector('#submit-form') || document.querySelector('form[action*="submit"]');
    if (!f) { return 'noform:' + document.title; }
    var sel = f.querySelector('select[name=submittedProblemIndex]');
    if (sel) { sel.value = index; sel.dispatchEvent(new Event('change', {bubbles:true})); }
    var lang = f.querySelector('select[name=programTypeId]');
    if (lang) {
      var pats = [/G\\+\\+\\s?23/i, /G\\+\\+\\s?20/i, /G\\+\\+\\s?17/i, /G\\+\\+/i];
      var best = null;
      for (var p = 0; p < pats.length && !best; p++) {
        var cands = Array.from(lang.options).filter(function(o){ return pats[p].test(o.text); });
        best = cands.find(function(o){ return /64/.test(o.text); }) || cands[0] || null;
      }
      if (best) { lang.value = best.value; lang.dispatchEvent(new Event('change', {bubbles:true})); }
    }
    var ta = f.querySelector('textarea[name=source]') || document.getElementById('sourceCodeTextarea');
    if (!ta) { return 'nosource'; }
    ta.value = code;
    try { if (window.ace) { var ed = window.ace.edit('editor'); if (ed) ed.setValue(code, -1); } } catch (e) {}
    var btn = document.getElementById('singlePageSubmitButton') || f.querySelector('input[type=submit]');
    if (autoSubmit && btn) { btn.click(); return 'submitted'; }
    return 'filled';
    """

    /// Ticks the terms box on the registration page and presses Register.
    static let register = """
    var boxes = document.querySelectorAll('form input[type=checkbox]');
    boxes.forEach(function(b){ b.checked = true; });
    var btn = document.querySelector('form input[type=submit], form .submit, form button[type=submit]');
    if (btn) { btn.click(); return 'clicked'; }
    return 'nobutton:' + document.title;
    """

    /// Returns the logged-in handle, or '' if logged out.
    static let whoami = """
    var a = document.querySelector('#header a[href^="/profile/"], .lang-chooser a[href^="/profile/"]');
    return a ? a.textContent.trim() : '';
    """
}

// MARK: - Sheets

struct SheetChrome<Content: View>: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// Opens a problem page, waits for the statement, copies the samples into the app, closes itself.
struct ImportProblemSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let contestId: Int
    let index: String
    var tags: [String]? = nil
    var rating: Int? = nil
    @StateObject private var flow = WebFlow()
    @State private var status = "Loading problem…"
    @State private var done = false

    var body: some View {
        SheetChrome(title: "Import \(contestId)\(index)") {
            VStack(spacing: 0) {
                Text(status).font(.footnote).foregroundStyle(.secondary).padding(8)
                FlowWebView(flow: flow)
            }
        }
        .task {
            let url = CFAPI.problemURL(contestId: contestId, index: index)
            flow.onFinish = { wv in
                guard !done else { return }
                Task { @MainActor in
                    let js = try? await wv.callAsyncJavaScript(CFScripts.extractProblem, arguments: [:], in: nil, contentWorld: .page)
                    guard let s = js as? String, let d = s.data(using: .utf8),
                          let ip = try? JSONDecoder().decode(ImportedProblem.self, from: d) else { return }
                    if ip.ok {
                        done = true
                        app.addImported(ip, contestId: contestId, index: index, url: url.absoluteString, tags: tags, rating: rating)
                        dismiss()
                    } else {
                        status = "Waiting for the problem page… (if you see a check, complete it)"
                    }
                }
            }
            flow.load(url)
        }
    }
}

/// Opens the contest submit page, fills language + code, presses Submit, and closes when Codeforces shows "my submissions".
struct SubmitSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let problem: Problem
    let code: String
    @StateObject private var flow = WebFlow()
    @State private var status = "Opening the submit page…"
    @State private var attempted = false

    var body: some View {
        SheetChrome(title: "Submit \(problem.id)") {
            VStack(spacing: 0) {
                Text(status).font(.footnote).foregroundStyle(.secondary).padding(8)
                FlowWebView(flow: flow)
            }
        }
        .task {
            guard let cid = problem.contestId, let idx = problem.index else { status = "This problem isn't from Codeforces."; return }
            flow.onFinish = { wv in
                let url = wv.url?.absoluteString ?? ""
                if attempted && (url.contains("/my") || url.contains("/status")) {
                    status = "Submitted ✓"
                    app.submissionsNeedRefresh += 1
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        app.selectedTab = 2
                        dismiss()
                    }
                    return
                }
                if url.contains("/enter") { status = "Log in to Codeforces, then submission continues."; return }
                if attempted && url.contains("/submit") {
                    status = "Codeforces didn't accept it — read the message on the page (for example: same code submitted before)."
                    return
                }
                if url.contains("/submit") && !attempted {
                    Task { @MainActor in
                        let r = try? await wv.callAsyncJavaScript(CFScripts.fillSubmit,
                                                                   arguments: ["code": code, "index": idx, "autoSubmit": true],
                                                                   in: nil, contentWorld: .page)
                        let res = (r as? String) ?? "error"
                        if res == "submitted" { attempted = true; status = "Submitting…" }
                        else { status = "Couldn't fill the form automatically (\(res)). Paste your code and press Submit on the page." }
                    }
                }
            }
            flow.load(URL(string: "https://codeforces.com/contest/\(cid)/submit")!)
        }
    }
}

struct RegisterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contest: CFContest
    @StateObject private var flow = WebFlow()
    @State private var status = "Opening registration…"
    @State private var tried = false

    var body: some View {
        SheetChrome(title: "Register") {
            VStack(spacing: 0) {
                Text(status).font(.footnote).foregroundStyle(.secondary).padding(8)
                FlowWebView(flow: flow)
            }
        }
        .task {
            flow.onFinish = { wv in
                let url = wv.url?.absoluteString ?? ""
                if url.contains("/enter") { status = "Log in first, then registration continues."; return }
                if url.contains("contestRegistration") && !tried {
                    tried = true
                    Task { @MainActor in
                        let r = try? await wv.callAsyncJavaScript(CFScripts.register, arguments: [:], in: nil, contentWorld: .page)
                        status = (r as? String) == "clicked" ? "Registering…" : "Tick the box and press Register on the page."
                    }
                } else if tried {
                    status = "Done — check the page above for confirmation."
                }
            }
            flow.load(URL(string: "https://codeforces.com/contestRegistration/\(contest.id)")!)
        }
    }
}

struct LoginSheet: View {
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow = WebFlow()
    @State private var status = "Log in to Codeforces below."

    var body: some View {
        SheetChrome(title: "Codeforces login") {
            VStack(spacing: 0) {
                Text(status).font(.footnote).foregroundStyle(.secondary).padding(8)
                FlowWebView(flow: flow)
            }
        }
        .task {
            flow.onFinish = { wv in
                Task { @MainActor in
                    let r = try? await wv.callAsyncJavaScript(CFScripts.whoami, arguments: [:], in: nil, contentWorld: .page)
                    if let h = r as? String, !h.isEmpty {
                        settings.handle = h
                        status = "Logged in as \(h) ✓"
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        dismiss()
                    }
                }
            }
            flow.load(URL(string: "https://codeforces.com/enter")!)
        }
    }
}
