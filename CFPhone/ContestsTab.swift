import SwiftUI

struct ContestsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var contests: [CFContest] = []
    @State private var error = ""
    @State private var loading = false
    @State private var registering: CFContest?
    @State private var live: CFContest?

    var running: [CFContest] { contests.filter { $0.phase == "CODING" } }
    var upcoming: [CFContest] { contests.filter { $0.phase == "BEFORE" } }

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                if !running.isEmpty {
                    Section("Live now") {
                        ForEach(running) { c in
                            Button { live = c } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Circle().fill(.red).frame(width: 8, height: 8); Text("LIVE").font(.caption.bold()).foregroundStyle(.red) }
                                    Text(c.name).font(.headline).foregroundStyle(.primary)
                                    if let e = c.end { Text("Ends in ").font(.caption).foregroundColor(.secondary) + Text(e, style: .timer).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                        }
                    }
                }
                Section("Upcoming") {
                    ForEach(upcoming) { c in ContestRow(c: c, onRegister: { registering = c }) }
                }
            }
            .navigationTitle("Contests")
            .refreshable { await load() }
            .overlay { if loading && contests.isEmpty { ProgressView() } }
            .sheet(item: $registering) { RegisterSheet(contest: $0) }
            .sheet(item: $live) { LiveContestSheet(contest: $0) }
        }
        .task { await load() }
        .onChange(of: settings.notifyDay) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
        .onChange(of: settings.notifyQuarter) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
        .onChange(of: settings.muted) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            contests = try await CFAPI.contests()
            error = ""
            if await Notifier.requestPermission() { await Notifier.schedule(contests: contests, settings: settings) }
        } catch { self.error = error.localizedDescription }
    }
}

struct ContestRow: View {
    @EnvironmentObject var settings: Settings
    let c: CFContest
    let onRegister: () -> Void

    var muted: Bool { settings.muted.contains(c.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.name).font(.headline)
            if let s = c.start {
                HStack(spacing: 6) {
                    Text(s.formatted(date: .abbreviated, time: .shortened))
                    Text("· \(c.durationSeconds / 3600)h \(c.durationSeconds % 3600 / 60)m")
                }.font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text("Starts in ").font(.caption).foregroundColor(.secondary) + Text(s, style: .relative).font(.caption.bold())
                    Spacer()
                    Button {
                        if muted { settings.muted.removeAll { $0 == c.id } } else { settings.muted.append(c.id) }
                    } label: { Image(systemName: muted ? "bell.slash" : "bell.fill") }.buttonStyle(.borderless)
                    Button("Register", action: onRegister).buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }.padding(.vertical, 3)
    }
}

/// Problems A…F of a running contest, with your verdict on each. Tap one to load it into the editor.
struct LiveContestSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    let contest: CFContest
    @State private var problems: [CFProblem] = []
    @State private var subs: [CFSubmission] = []
    @State private var error = ""
    @State private var importTarget: ProblemsSheet.ImportTarget?

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                if let e = contest.end {
                    Section { Text("Ends in ") + Text(e, style: .timer).bold() }
                }
                Section("Problems") {
                    ForEach(problems, id: \.index) { p in
                        Button { importTarget = .init(contestId: contest.id, index: p.index) } label: {
                            HStack {
                                Text(p.index).font(.title3.bold()).frame(width: 28)
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                chip(for: p.index)
                            }
                        }
                    }
                }
            }
            .navigationTitle(contest.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $importTarget, onDismiss: { if app.currentID != "scratch" { dismiss() } }) { t in
                ImportProblemSheet(contestId: t.contestId, index: t.index)
            }
        }
        .task {
            do { problems = try await CFAPI.contestProblems(contest.id) } catch { self.error = error.localizedDescription }
            while !Task.isCancelled {
                if !settings.handle.isEmpty,
                   let all = try? await CFAPI.submissions(handle: settings.handle, count: 60) {
                    subs = all.filter { $0.contestId == contest.id }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    @ViewBuilder func chip(for index: String) -> some View {
        let mine = subs.filter { $0.problem.index == index }
        if mine.contains(where: { $0.verdict == "OK" }) {
            Label("Solved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else if let last = mine.first {
            Text(CFAPI.verdictText(last.verdict)).font(.caption).foregroundColor(last.isPending ? Color.blue : Color.red)
        }
    }
}
