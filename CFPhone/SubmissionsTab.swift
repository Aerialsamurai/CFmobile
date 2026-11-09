import SwiftUI

struct SubmissionsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var items: [CFSubmission] = []
    @State private var error = ""
    @State private var loading = false
    @State private var polling: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if settings.handle.isEmpty {
                    Text("Set your Codeforces handle in Settings to see your submissions.").foregroundStyle(.secondary)
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                ForEach(items) { s in SubmissionRow(s: s) }
            }
            .navigationTitle("Submissions")
            .refreshable { await load() }
            .overlay { if loading && items.isEmpty { ProgressView() } }
        }
        .onAppear { startPolling() }
        .onDisappear { polling?.cancel() }
        .onChange(of: app.submissionsNeedRefresh) { _ in Task { await load() }; startPolling() }
        .onChange(of: settings.handle) { _ in Task { await load() } }
    }

    private func load() async {
        guard !settings.handle.isEmpty else { return }
        loading = true
        defer { loading = false }
        do { items = try await CFAPI.submissions(handle: settings.handle); error = "" }
        catch { self.error = error.localizedDescription }
    }

    /// Refreshes every 3 s while something is still being judged (Codeforces allows ~1 request / 2 s), otherwise every 30 s.
    private func startPolling() {
        polling?.cancel()
        polling = Task {
            await load()
            while !Task.isCancelled {
                let busy = items.contains { $0.isPending }
                try? await Task.sleep(nanoseconds: (busy ? 3 : 30) * 1_000_000_000)
                if Task.isCancelled { break }
                await load()
            }
        }
    }
}

struct SubmissionRow: View {
    let s: CFSubmission

    var color: Color {
        switch s.verdict {
        case "OK": return .green
        case nil, "TESTING": return .blue
        case "TIME_LIMIT_EXCEEDED", "MEMORY_LIMIT_EXCEEDED": return .orange
        default: return .red
        }
    }

    var verdictLine: String {
        var t = CFAPI.verdictText(s.verdict)
        if s.verdict == "WRONG_ANSWER" || s.verdict == "RUNTIME_ERROR" || s.verdict == "TIME_LIMIT_EXCEEDED" || s.verdict == "MEMORY_LIMIT_EXCEEDED" {
            t += " on test \(s.passedTestCount + 1)"
        } else if s.isPending && s.passedTestCount > 0 {
            t += " · test \(s.passedTestCount + 1)"
        }
        return t
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(s.problem.contestId.map(String.init) ?? "")\(s.problem.index) · \(s.problem.name)").font(.headline).lineLimit(1)
                Text(verdictLine).foregroundStyle(color).font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    if !s.isPending { Text("\(s.timeConsumedMillis) ms"); Text("\(s.memoryConsumedBytes / 1024) KB") }
                    Text(s.date, style: .relative)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 2)
    }
}
