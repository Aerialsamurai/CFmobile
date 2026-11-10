import SwiftUI

// MARK: - Model

struct ContestModeState: Equatable {
    let contest: CFContest
    let problems: [CFProblem]
}

struct ProblemStatus: Equatable {
    var solvedMinute: Int? = nil     // minutes after the contest started
    var rejected = 0
    var pending = false
}

struct ImportRequest: Identifiable {
    let contestId: Int
    let index: String
    var id: String { "\(contestId)\(index)" }
}

extension AppState {
    /// Pins the contest bar above the editor and starts watching your submissions for this contest.
    func enterContestMode(_ c: CFContest, problems: [CFProblem]) {
        contestMode = ContestModeState(contest: c, problems: problems)
        contestStatus = [:]
        selectedTab = 0
        contestTask?.cancel()
        contestTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshContestStatus()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func exitContestMode() {
        contestTask?.cancel()
        contestTask = nil
        contestMode = nil
        contestStatus = [:]
    }

    /// Opens problem `index` of the running contest: instantly if it's already imported, otherwise imports it first.
    func openContestProblem(_ index: String) {
        guard let cm = contestMode else { return }
        let id = "\(cm.contest.id)\(index)"
        if problems.contains(where: { $0.id == id }) {
            openProblem(id)
        } else {
            importRequest = ImportRequest(contestId: cm.contest.id, index: index)
        }
    }

    func refreshContestStatus() async {
        guard let cm = contestMode, !settings.handle.isEmpty, let start = cm.contest.start,
              let subs = try? await CFAPI.submissions(handle: settings.handle, count: 60) else { return }
        let from = Int(start.timeIntervalSince1970)
        var out: [String: ProblemStatus] = [:]
        for s in subs.sorted(by: { $0.creationTimeSeconds < $1.creationTimeSeconds }) {
            guard (s.contestId ?? s.problem.contestId) == cm.contest.id, s.creationTimeSeconds >= from else { continue }
            var st = out[s.problem.index] ?? ProblemStatus()
            if st.solvedMinute != nil { continue }
            if s.verdict == "OK" {
                st.solvedMinute = (s.creationTimeSeconds - from) / 60
                st.pending = false
            } else if s.isPending {
                st.pending = true
            } else if let v = s.verdict, v != "COMPILATION_ERROR" {
                st.rejected += 1
            }
            out[s.problem.index] = st
        }
        if out != contestStatus { contestStatus = out }
    }
}

// MARK: - Bar above the editor

struct ContestBar: View {
    let state: ContestModeState
    @EnvironmentObject var app: AppState
    @State private var showStandings = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(state.contest.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let end = state.contest.end {
                    if Date() < end {
                        Text(end, style: .timer).font(.system(.title3, design: .monospaced).weight(.bold)).monospacedDigit()
                    } else {
                        Text("Contest over").font(.caption.weight(.semibold)).foregroundColor(.orange)
                    }
                }
                Button { showStandings = true } label: { Image(systemName: "list.number") }
                Button { app.exitContestMode() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.problems, id: \.index) { p in letter(p) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .sheet(isPresented: $showStandings) {
            NavigationStack {
                StandingsView(contest: state.contest)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showStandings = false } } }
            }
        }
    }

    private func letter(_ p: CFProblem) -> some View {
        let st = app.contestStatus[p.index] ?? ProblemStatus()
        let current = app.currentID == "\(state.contest.id)\(p.index)"
        let tint: Color = st.solvedMinute != nil ? .green : (st.pending ? .blue : (st.rejected > 0 ? .red : .gray))
        let sub: String = st.solvedMinute.map { "✓ \($0)m" } ?? (st.pending ? "…" : (st.rejected > 0 ? "-\(st.rejected)" : "·"))
        return Button { app.openContestProblem(p.index) } label: {
            VStack(spacing: 1) {
                Text(p.index).font(.headline)
                Text(sub).font(.system(size: 10, design: .monospaced))
            }
            .frame(width: 50, height: 44)
            .background(tint.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(current ? Color.accentColor : Color.clear, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}
