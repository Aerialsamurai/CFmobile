import SwiftUI

/// Tap a submission to see exactly which test failed, with input / expected / yours, without opening the browser.
struct SubmissionDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let sub: CFSubmission
    @StateObject private var flow = WebFlow()
    @State private var detail: SubmissionDetail?
    @State private var status = "Loading details…"
    @State private var needsBrowser = false
    @State private var added = false

    private var failed: Bool { sub.verdict != nil && sub.verdict != "OK" && sub.verdict != "TESTING" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(sub.problem.contestId.map(String.init) ?? "")\(sub.problem.index) · \(sub.problem.name)").font(.title3.bold())
                        Text(CFAPI.verdictText(sub.verdict)).foregroundColor(sub.verdict == "OK" ? .green : (failed ? .red : .blue)).font(.headline)
                        Text("\(sub.programmingLanguage) · \(sub.timeConsumedMillis) ms · \(sub.memoryConsumedBytes / 1024) KB").font(.footnote).foregroundStyle(.secondary)
                    }

                    if sub.verdict == "OK" {
                        Label("All tests passed.", systemImage: "checkmark.seal.fill").foregroundColor(.green)
                    } else if failed {
                        let ex = FailureExplainer.explain(verdict: sub.verdict, passed: sub.passedTestCount, detail: detail)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ex.headline).font(.headline)
                            if let d = ex.detail { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))

                        if let d = detail, d.ok, (d.testCount ?? 0) > 0 {
                            block("Test input", d.input)
                            block("Expected (jury)", d.answer)
                            block("Your output", d.output)
                            if let input = d.input, !input.isEmpty, problemInApp != nil {
                                Button {
                                    app.addFailingTest(problemID: "\(sub.problem.contestId ?? 0)\(sub.problem.index)", input: input, expected: d.answer ?? "")
                                    added = true
                                } label: {
                                    Label(added ? "Added to Tests" : "Add this test to my Tests tab", systemImage: added ? "checkmark" : "plus.circle")
                                }
                                .buttonStyle(.bordered).disabled(added)
                                if input.hasSuffix("...") { Text("Codeforces shortens long inputs, so this copy may be cut off.").font(.caption).foregroundStyle(.secondary) }
                            }
                        } else {
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Still being judged — this updates on the Submissions tab.").foregroundStyle(.secondary)
                    }

                    if failed, detail == nil, let url = pageURL {
                        Text("Test details need the in-app Codeforces login (Profile ▸ ⚙︎ ▸ Log in). You can also view this submission in your browser.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { Browser.open(url) } label: { Label("Open submission in browser", systemImage: "safari") }.buttonStyle(.bordered)
                    }
                    if needsBrowser {
                        Text("Codeforces wants a check first. Finish it below, then reopen this screen.").font(.footnote).foregroundStyle(.orange)
                    }
                    FlowWebView(flow: flow)
                        .frame(height: needsBrowser ? 360 : 1)
                        .opacity(needsBrowser ? 1 : 0.01)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }
            .navigationTitle("Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let url = pageURL { Button { Browser.open(url) } label: { Label("Open in browser", systemImage: "safari") } }
                }
            }
        }
        .task { await fetch() }
    }

    private var pageURL: URL? {
        guard let cid = sub.contestId ?? sub.problem.contestId else { return nil }
        return URL(string: "https://codeforces.com/contest/\(cid)/submission/\(sub.id)")
    }

    private var problemInApp: Problem? { app.problems.first { $0.id == "\(sub.problem.contestId ?? 0)\(sub.problem.index)" } }

    @ViewBuilder private func block(_ title: String, _ text: String?) -> some View {
        if let t = text, !t.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(t.count > 2000 ? String(t.prefix(2000)) + "…" : t)
                    .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func fetch() async {
        guard failed, let cid = sub.contestId ?? sub.problem.contestId else { return }
        let sid = sub.id
        flow.onFinish = { wv in
            Task { @MainActor in
                guard detail == nil else { return }
                let r = try? await wv.callAsyncJavaScript(CFScripts.submissionDetail, arguments: ["sid": sid], in: nil, contentWorld: .page)
                guard let s = r as? String, let data = s.data(using: .utf8),
                      let d = try? JSONDecoder().decode(SubmissionDetail.self, from: data) else { status = "Couldn't read details."; return }
                if d.ok { detail = d; needsBrowser = false; if (d.testCount ?? 0) == 0 { status = "Codeforces didn't share test details for this submission." } }
                else { status = "Couldn't load test details (\(d.reason ?? "unknown"))."; needsBrowser = true }
            }
        }
        flow.load(URL(string: "https://codeforces.com/contest/\(cid)/submission/\(sid)")!)
    }
}
