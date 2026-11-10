import SwiftUI

// MARK: - Standings

struct StandingsView: View {
    let contest: CFContest
    @EnvironmentObject var settings: Settings

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", friends = "Friends", me = "Me"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .all
    @State private var page: CFStandingsPage?
    @State private var error = ""
    @State private var loading = false

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            if scope == .friends && settings.friends.isEmpty {
                Text("You have no friends added yet. Add handles in Profile ▸ Friends.").font(.footnote).foregroundStyle(.secondary)
            }
            if scope == .me && settings.handle.isEmpty {
                Text("Set your handle in Settings to see your own row.").font(.footnote).foregroundStyle(.secondary)
            }
            if let page = page {
                Section(footer: Text(contest.phase == "CODING" ? "Updates every 30 seconds while the contest runs." : "")) {
                    ForEach(page.rows) { row in
                        StandingRowView(row: row, problems: page.problems, me: settings.handle, friends: settings.friends)
                    }
                    if page.rows.isEmpty && !loading { Text("No rows to show.").foregroundStyle(.secondary) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if loading && page == nil { ProgressView() } }
        .refreshable { await load() }
        .task(id: scope) { await load() }
        .task {
            // live refresh while the contest is running (Codeforces allows about one call per 2 s)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if contest.phase == "CODING" { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            switch scope {
            case .all:
                page = try await CFAPI.standings(contestId: contest.id)
            case .friends:
                guard !settings.friends.isEmpty else { page = nil; return }
                page = try await CFAPI.standings(contestId: contest.id, handles: settings.friends)
            case .me:
                guard !settings.handle.isEmpty else { page = nil; return }
                page = try await CFAPI.standings(contestId: contest.id, handles: [settings.handle])
            }
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct StandingRowView: View {
    let row: CFStandingRow
    let problems: [CFProblem]
    let me: String
    let friends: [String]

    private var isMe: Bool { !me.isEmpty && row.handle.lowercased() == me.lowercased() }
    private var isFriend: Bool { friends.contains { $0.lowercased() == row.handle.lowercased() } }
    private var unofficial: Bool { (row.party.participantType ?? "CONTESTANT") != "CONTESTANT" }

    private func score(_ p: Double) -> String { p == p.rounded() ? String(Int(p)) : String(format: "%.1f", p) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(unofficial ? "*" : "#\(row.rank)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .leading)
                Text(row.handle).font(.headline).foregroundColor(isMe ? .accentColor : (isFriend ? .orange : .primary)).lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(score(row.points)).font(.headline)
                    if row.penalty > 0 { Text("pen \(row.penalty)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(row.problemResults.enumerated()), id: \.offset) { pair in
                        cell(index: pair.offset < problems.count ? problems[pair.offset].index : "?", result: pair.element)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func cell(index: String, result r: CFStandingRow.PResult) -> some View {
        let solved = r.points > 0
        let tried = !solved && r.rejectedAttemptCount > 0
        VStack(spacing: 1) {
            Text(index).font(.caption2.weight(.bold))
            if solved {
                Text(r.bestSubmissionTimeSeconds.map { "\($0 / 60)m" } ?? score(r.points)).font(.system(size: 10, design: .monospaced))
            } else if tried {
                Text("-\(r.rejectedAttemptCount)").font(.system(size: 10, design: .monospaced))
            } else {
                Text("·").font(.system(size: 10))
            }
        }
        .frame(minWidth: 34).padding(.vertical, 3).padding(.horizontal, 4)
        .background(solved ? Color.green.opacity(0.25) : (tried ? Color.red.opacity(0.22) : Color.secondary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Friends

struct FriendsView: View {
    @EnvironmentObject var settings: Settings
    @State private var users: [String: CFUser] = [:]
    @State private var newHandle = ""
    @State private var error = ""
    @State private var busy = false

    private var sorted: [String] {
        settings.friends.sorted { (users[$0.lowercased()]?.rating ?? -1) > (users[$1.lowercased()]?.rating ?? -1) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a Codeforces handle", text: $newHandle)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await add() } }
                    if busy { ProgressView() } else {
                        Button("Add") { Task { await add() } }.disabled(newHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            } footer: { Text("Friends are saved on this phone. They appear highlighted in contest standings.") }

            Section("Friends (\(settings.friends.count))") {
                ForEach(sorted, id: \.self) { h in
                    let u = users[h.lowercased()]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u?.handle ?? h).font(.headline).foregroundColor(cfRankColor(u?.rating))
                            if let r = u?.rank { Text(r.capitalized).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(u?.rating.map(String.init) ?? "—").font(.headline).foregroundColor(cfRankColor(u?.rating))
                    }
                }
                .onDelete { idx in
                    let drop = idx.map { sorted[$0] }
                    settings.friends.removeAll { f in drop.contains(f) }
                }
                if settings.friends.isEmpty { Text("No friends yet.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        guard let list = try? await CFAPI.users(settings.friends) else { return }
        var m: [String: CFUser] = [:]
        for u in list { m[u.handle.lowercased()] = u }
        users = m
    }

    private func add() async {
        let h = newHandle.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        if settings.friends.contains(where: { $0.lowercased() == h.lowercased() }) { error = "\(h) is already in your list."; return }
        busy = true
        defer { busy = false }
        do {
            let u = try await CFAPI.userInfo(h)      // also checks that the handle exists
            settings.friends.append(u.handle)
            users[u.handle.lowercased()] = u
            newHandle = ""
            error = ""
        } catch { self.error = "Couldn't find \"\(h)\" on Codeforces." }
    }
}

// MARK: - Past contest: problems, standings, virtual participation

struct ContestDetailSheet: View {
    let contest: CFContest
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var problems: [CFProblem] = []
    @State private var error = ""
    @State private var starting = false
    @State private var confirmStart = false
    @State private var importTarget: ProblemsSheet.ImportTarget?

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                Section {
                    NavigationLink { StandingsView(contest: contest) } label: { Label("Standings", systemImage: "list.number") }
                    if app.virtualRun == nil {
                        Button { confirmStart = true } label: { Label("Start a virtual contest", systemImage: "timer") }
                            .disabled(starting)
                    } else {
                        Text("A virtual contest is already running. End it first (Contests tab).").font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("A virtual contest times you on this contest's problems, using your own submissions made after you start.")
                }
                Section("Problems") {
                    ForEach(problems, id: \.index) { p in
                        Button { importTarget = .init(contestId: contest.id, index: p.index) } label: {
                            HStack {
                                Text(p.index).font(.title3.bold()).frame(width: 28)
                                Text(p.name).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(contest.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $importTarget, onDismiss: { if app.codeSegment == 0 && app.selectedTab == 0 { dismiss() } }) { t in
                ImportProblemSheet(contestId: t.contestId, index: t.index)
            }
            .confirmationDialog("Start the virtual contest now?", isPresented: $confirmStart, titleVisibility: .visible) {
                Button("Start (\(contest.durationSeconds / 3600)h \(contest.durationSeconds % 3600 / 60)m)") { Task { await start() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The timer starts immediately. Only submissions you make from now count.") }
        }
        .task {
            do { problems = try await CFAPI.contestProblems(contest.id) } catch { self.error = error.localizedDescription }
        }
    }

    private func start() async {
        starting = true
        defer { starting = false }
        if problems.isEmpty { problems = (try? await CFAPI.contestProblems(contest.id)) ?? [] }
        guard !problems.isEmpty else { error = "Couldn't load the problems. Try again."; return }
        app.virtualRun = VirtualRun(contestId: contest.id, name: contest.name, start: Date(), durationSeconds: contest.durationSeconds,
                                    problems: problems.map { .init(index: $0.index, name: $0.name) })
        dismiss()
    }
}

// MARK: - Virtual contest in progress

struct VirtualContestView: View {
    let run: VirtualRun
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var subs: [CFSubmission] = []
    @State private var error = ""
    @State private var confirmEnd = false
    @State private var importTarget: ProblemsSheet.ImportTarget?

    private struct Line { var solvedAt: Int?; var rejected = 0 }   // minutes into the contest

    private var lines: [String: Line] {
        let from = Int(run.start.timeIntervalSince1970), to = Int(run.end.timeIntervalSince1970)
        var out: [String: Line] = [:]
        for s in subs.sorted(by: { $0.creationTimeSeconds < $1.creationTimeSeconds }) {
            guard s.contestId == run.contestId || s.problem.contestId == run.contestId,
                  s.creationTimeSeconds >= from, s.creationTimeSeconds <= to else { continue }
            var l = out[s.problem.index] ?? Line()
            if l.solvedAt != nil { continue }
            if s.verdict == "OK" { l.solvedAt = (s.creationTimeSeconds - from) / 60 }
            else if let v = s.verdict, v != "TESTING", v != "COMPILATION_ERROR" { l.rejected += 1 }
            out[s.problem.index] = l
        }
        return out
    }

    private var solvedCount: Int { lines.values.filter { $0.solvedAt != nil }.count }
    /// ICPC-style penalty: minutes at each accepted problem + 20 per earlier wrong try.
    private var penalty: Int { lines.values.compactMap { l in l.solvedAt.map { $0 + 20 * l.rejected } }.reduce(0, +) }

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if Date() < run.end {
                            Text(timerInterval: run.start...run.end, countsDown: true).font(.system(size: 40, weight: .bold, design: .monospaced))
                            Text("remaining").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Time's up").font(.title.bold()).foregroundColor(.orange)
                        }
                        HStack(spacing: 18) {
                            Text("Solved \(solvedCount)/\(run.problems.count)").font(.headline)
                            Text("Penalty \(penalty)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                } footer: { Text("Scored like ICPC: problems solved, then penalty (minutes + 20 per wrong try). Codeforces' own virtual scoring may differ.") }

                Section("Problems") {
                    ForEach(run.problems, id: \.index) { p in
                        Button { importTarget = .init(contestId: run.contestId, index: p.index) } label: {
                            HStack {
                                Text(p.index).font(.title3.bold()).frame(width: 28)
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                status(p.index)
                            }
                        }
                    }
                }
                Section { Button("End virtual contest", role: .destructive) { confirmEnd = true } }
            }
            .navigationTitle(run.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $importTarget, onDismiss: { if app.codeSegment == 0 && app.selectedTab == 0 { dismiss() } }) { t in
                ImportProblemSheet(contestId: t.contestId, index: t.index)
            }
            .confirmationDialog("End this virtual contest?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End and discard", role: .destructive) { app.virtualRun = nil; dismiss() }
                Button("Keep going", role: .cancel) {}
            }
        }
        .task {
            while !Task.isCancelled {
                if !settings.handle.isEmpty, let all = try? await CFAPI.submissions(handle: settings.handle, count: 100) { subs = all }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    @ViewBuilder private func status(_ index: String) -> some View {
        if let l = lines[index] {
            if let t = l.solvedAt {
                Label("\(t)m", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
            } else if l.rejected > 0 {
                Text("-\(l.rejected)").font(.caption.weight(.semibold)).foregroundColor(.red)
            }
        }
    }
}
