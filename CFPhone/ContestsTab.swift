import SwiftUI

struct ContestsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var contests: [CFContest] = []
    @State private var error = ""
    @State private var loading = false
    @State private var registering: CFContest?
    @State private var live: CFContest?
    @State private var detail: CFContest?
    @State private var showVirtual = false
    @State private var confirmRegistered = false
    @StateObject private var checker = WebFlow()      // invisible: asks codeforces.com which contests you're registered for
    @Environment(\.scenePhase) private var scenePhase

    var running: [CFContest] { contests.filter { $0.phase == "CODING" } }
    var upcoming: [CFContest] { contests.filter { $0.phase == "BEFORE" }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) } }
    var past: [CFContest] { Array(contests.filter { $0.phase == "FINISHED" }.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }.prefix(25)) }

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                if let run = app.virtualRun {
                    Section("Virtual contest") {
                        Button { showVirtual = true } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("In progress", systemImage: "timer").font(.caption.bold()).foregroundColor(.orange)
                                Text(run.name).font(.headline).foregroundStyle(.primary)
                                if Date() < run.end {
                                    Text("Ends in ").font(.caption).foregroundColor(.secondary) + Text(run.end, style: .timer).font(.caption).foregroundColor(.secondary)
                                } else { Text("Time's up — tap for your result").font(.caption).foregroundColor(.secondary) }
                            }
                        }
                    }
                }
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
                    ForEach(upcoming) { c in
                        ContestRow(c: c, registered: app.registeredContests.contains(c.id),
                                   onRegister: { register(c, inApp: !settings.useDefaultBrowser) },
                                   onRegisterOther: { register(c, inApp: settings.useDefaultBrowser) },
                                   onUnmark: { app.markRegistered(c.id, false) })
                    }
                }
                if !past.isEmpty {
                    Section("Past contests") {
                        ForEach(past) { c in
                            Button { detail = c } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.name).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                    if let st = c.start { Text(st.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contests")
            .refreshable { await load() }
            .overlay { if loading && contests.isEmpty { ProgressView() } }
            .sheet(item: $registering) { RegisterSheet(contest: $0) }
            .sheet(item: $live) { LiveContestSheet(contest: $0) }
            .sheet(item: $detail) { ContestDetailSheet(contest: $0) }
            .sheet(isPresented: $showVirtual) { if let r = app.virtualRun { VirtualContestView(run: r) } }
            .background(FlowWebView(flow: checker).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false))
            .alert("Did you register?", isPresented: $confirmRegistered, presenting: app.pendingRegistration) { c in
                Button("Yes, I registered") { app.markRegistered(c.id); app.pendingRegistration = nil }
                Button("Not yet", role: .cancel) { app.pendingRegistration = nil }
            } message: { c in
                Text("Mark \(c.name) as registered so it shows here.")
            }
        }
        .task { await load(); await checkRegistrations() }
        .onChange(of: scenePhase) { phase in
            if phase == .active, app.pendingRegistration != nil { confirmRegistered = true }
        }
        .onChange(of: registering?.id) { id in
            // the in-app registration sheet was closed: ask Codeforces whether it worked
            if id == nil { Task { try? await Task.sleep(nanoseconds: 800_000_000); await checkRegistrations() } }
        }
        .onChange(of: settings.notifyDay) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
        .onChange(of: settings.notifyQuarter) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
        .onChange(of: settings.muted) { _ in Task { await Notifier.schedule(contests: contests, settings: settings) } }
    }

    /// inApp = automatic form in the app's own browser; otherwise your default browser (Safari, Brave…).
    private func register(_ c: CFContest, inApp: Bool) {
        if inApp {
            registering = c
        } else {
            app.pendingRegistration = c
            if let url = URL(string: "https://codeforces.com/contestRegistration/\(c.id)") { Browser.open(url) }
        }
    }

    private struct RegisteredResult: Decodable {
        struct Item: Decodable { let id: Int; let registered: Bool }
        let ok: Bool
        let loggedIn: Bool
        let contests: [Item]
    }

    /// Works when you're logged in inside the app; otherwise the "Registered" marks you set yourself are used.
    private func checkRegistrations() async {
        checker.onFinish = { wv in
            Task { @MainActor in
                let r = try? await wv.callAsyncJavaScript(CFScripts.registeredContests, arguments: [:], in: nil, contentWorld: .page)
                guard let str = r as? String, let d = str.data(using: .utf8),
                      let res = try? JSONDecoder().decode(RegisteredResult.self, from: d), res.ok, res.loggedIn else { return }
                for c in res.contests where app.registeredContests.contains(c.id) != c.registered { app.markRegistered(c.id, c.registered) }
            }
        }
        if let url = URL(string: "https://codeforces.com/contests") { checker.load(url) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            contests = try await CFAPI.contests()
            app.liveContestActive = contests.contains { $0.phase == "CODING" }
            error = ""
            if await Notifier.requestPermission() { await Notifier.schedule(contests: contests, settings: settings) }
        } catch { self.error = error.localizedDescription }
    }
}

struct ContestRow: View {
    @EnvironmentObject var settings: Settings
    let c: CFContest
    let registered: Bool
    let onRegister: () -> Void
    let onRegisterOther: () -> Void
    let onUnmark: () -> Void

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
                    if registered {
                        Menu {
                            Button("Mark as not registered", role: .destructive, action: onUnmark)
                        } label: {
                            Label("Registered", systemImage: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold)).foregroundColor(.green)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.green.opacity(0.15)).clipShape(Capsule())
                        }
                    } else {
                        Button("Register", action: onRegister)
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .contextMenu {
                                Button(settings.useDefaultBrowser ? "Register inside the app" : "Register in my browser", action: onRegisterOther)
                            }
                    }
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
                Section {
                    Button {
                        app.enterContestMode(contest, problems: problems)
                        dismiss()
                    } label: { Label("Enter contest mode", systemImage: "scope") }
                        .disabled(problems.isEmpty)
                } footer: {
                    Text("Pins a countdown and your A–F verdicts above the editor, so you can switch problems with one tap.")
                }
                Section { NavigationLink { StandingsView(contest: contest) } label: { Label("Standings", systemImage: "list.number") } }
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
