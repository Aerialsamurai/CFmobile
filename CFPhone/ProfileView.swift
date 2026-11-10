import SwiftUI
import Charts

// MARK: - Colours (Codeforces rank colours)

func cfRankColor(_ rating: Int?) -> Color {
    guard let r = rating else { return .gray }
    switch r {
    case ..<1200: return .gray
    case ..<1400: return .green
    case ..<1600: return .cyan
    case ..<1900: return .blue
    case ..<2100: return .purple
    case ..<2400: return .orange
    default: return .red
    }
}

// MARK: - Data

private struct ProfileCache: Codable {
    var user: CFUser?
    var history: [CFRatingChange]
    var subs: [CFSubmission]
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var user: CFUser?
    @Published var history: [CFRatingChange] = []
    @Published var stats = UserStats()
    @Published var loading = false
    @Published var error = ""
    @Published var loadedHandle = ""

    private func cacheURL(_ handle: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("cfphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile-\(handle.lowercased()).json")
    }

    func load(handle: String) async {
        guard !handle.isEmpty else { return }
        loading = true
        defer { loading = false }

        // show the saved copy immediately, then refresh
        if loadedHandle != handle, let d = try? Data(contentsOf: cacheURL(handle)),
           let c = try? JSONDecoder().decode(ProfileCache.self, from: d) {
            apply(c, handle: handle)
        }
        do {
            let u = try await CFAPI.userInfo(handle)
            let r = (try? await CFAPI.ratingHistory(handle)) ?? []
            let s = try await CFAPI.allSubmissions(handle: handle)
            let c = ProfileCache(user: u, history: r, subs: s)
            apply(c, handle: handle)
            if let d = try? JSONEncoder().encode(c) { try? d.write(to: cacheURL(handle)) }
            error = ""
        } catch {
            if user == nil || loadedHandle != handle { self.error = error.localizedDescription }
        }
    }

    private func apply(_ c: ProfileCache, handle: String) {
        user = c.user
        history = c.history
        stats = StatsEngine.compute(c.subs)
        loadedHandle = handle
    }
}

// MARK: - Profile tab

struct ProfileTab: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @StateObject private var store = ProfileStore()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if settings.handle.isEmpty {
                        emptyState
                    } else {
                        if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(.red) }
                        header
                        streakCards
                        ratingCard
                        heatmapCard
                        NavigationLink { AnalyticsView(stats: store.stats) } label: {
                            HStack {
                                Label("Statistics", systemImage: "chart.bar.xaxis")
                                Spacer()
                                Text("by rating, tag, verdict…").font(.footnote).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .padding(14).card()
                        }.buttonStyle(.plain)
                        recentContests
                    }
                }
                .padding(16)
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable { await store.load(handle: settings.handle) }
            .overlay { if store.loading && store.user == nil && !settings.handle.isEmpty { ProgressView() } }
            .sheet(isPresented: $showSettings) { SettingsTab() }
        }
        .task(id: settings.handle) { await store.load(handle: settings.handle) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 54)).foregroundStyle(.secondary)
            Text("Add your Codeforces handle").font(.headline)
            Text("Your rating, streaks and statistics show up here.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") { showSettings = true }.buttonStyle(.borderedProminent)
        }.padding(.top, 60)
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 14) {
            AsyncImage(url: store.user.flatMap { URL(string: ($0.titlePhoto ?? $0.avatar ?? "").replacingOccurrences(of: "http://", with: "https://")) }) { img in
                img.resizable().scaledToFill()
            } placeholder: { Color.secondary.opacity(0.2) }
            .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.user?.rank?.capitalized ?? "—").font(.caption.weight(.semibold)).foregroundColor(cfRankColor(store.user?.rating))
                Text(store.user?.handle ?? settings.handle).font(.title2.bold()).foregroundColor(cfRankColor(store.user?.rating))
                HStack(spacing: 8) {
                    Text("Rating \(store.user?.rating.map(String.init) ?? "—")").font(.subheadline.weight(.semibold))
                    if let m = store.user?.maxRating { Text("max \(m)").font(.footnote).foregroundStyle(.secondary) }
                }
                if let org = store.user?.organization, !org.isEmpty { Text(org).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(14).card()
    }

    private var streakCards: some View {
        let s = store.stats
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                stat("🔥 \(s.currentStreak)", "day streak", s.solvedToday ? "kept today ✓" : (s.currentStreak > 0 ? "solve one today!" : ""))
                stat("\(s.longestStreak)", "best streak", "days")
            }
            HStack(spacing: 10) {
                stat("\(s.solved)", "problems solved", "\(s.solvedLast30) in 30 days")
                stat("\(s.activeDays)", "active days", String(format: "%.0f%% accepted", s.acceptance * 100))
            }
        }
    }

    private func stat(_ big: String, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.title2.bold())
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(sub).font(.caption2).foregroundStyle(.tertiary).frame(height: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).card()
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating").font(.headline)
            if store.history.count < 2 {
                Text("The graph appears after your second rated contest.").font(.footnote).foregroundStyle(.secondary)
            } else {
                let lo = (store.history.map(\.newRating).min() ?? 0) - 100
                let hi = (store.history.map(\.newRating).max() ?? 0) + 100
                Chart(store.history) { c in
                    LineMark(x: .value("Date", c.date), y: .value("Rating", c.newRating)).foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Date", c.date), y: .value("Rating", c.newRating))
                        .foregroundStyle(cfRankColor(c.newRating)).symbolSize(26)
                }
                .chartYScale(domain: lo...hi)
                .frame(height: 170)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Text("\(store.stats.accepted) accepted").font(.footnote).foregroundStyle(.secondary)
            }
            Heatmap(counts: store.stats.acByDay)
        }
        .padding(14).card()
    }

    @ViewBuilder private var recentContests: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent contests").font(.headline).padding(14)
                ForEach(store.history.suffix(8).reversed()) { c in
                    Divider().padding(.leading, 14)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.contestName).font(.subheadline).lineLimit(1)
                            Text("Rank \(c.rank) · \(c.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(c.delta >= 0 ? "+\(c.delta)" : "\(c.delta)")
                            .font(.subheadline.weight(.semibold)).foregroundColor(c.delta >= 0 ? .green : .red)
                        Text("\(c.newRating)").font(.subheadline).foregroundColor(cfRankColor(c.newRating)).frame(width: 48, alignment: .trailing)
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                }
            }.card()
        }
    }
}

extension View {
    /// Rounded "grouped" card used across the Profile screens.
    func card() -> some View {
        self.background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Heatmap (last ~year, GitHub style)

struct Heatmap: View {
    let counts: [Date: Int]

    private var weeks: [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = cal.date(byAdding: .weekOfYear, value: -52, to: thisWeek) else { return [] }
        var out: [[Date?]] = []
        for w in 0..<53 {
            var week: [Date?] = []
            for d in 0..<7 {
                let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)
                week.append((day ?? today) <= today ? day : nil)
            }
            out.append(week)
        }
        return out
    }

    private func color(_ n: Int) -> Color {
        switch n {
        case 0: return Color.secondary.opacity(0.18)
        case 1: return Color.green.opacity(0.4)
        case 2: return Color.green.opacity(0.6)
        case 3...4: return Color.green.opacity(0.8)
        default: return Color.green
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { pair in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { d in
                                if let day = pair.element[d] {
                                    RoundedRectangle(cornerRadius: 2.5).fill(color(counts[day] ?? 0)).frame(width: 11, height: 11)
                                } else {
                                    Color.clear.frame(width: 11, height: 11)
                                }
                            }
                        }.id(pair.offset)
                    }
                }
            }
            .onAppear { proxy.scrollTo(52, anchor: .trailing) }
        }
    }
}

// MARK: - Statistics screen (like the CF Analytics extension)

struct AnalyticsView: View {
    let stats: UserStats
    @EnvironmentObject var app: AppState
    @State private var importTarget: UnsolvedProblem?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                Text("Charts and the unsolved list count rated problems only and are computed from your submissions the same way as the CF Analytics browser extension, so the numbers match.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if !stats.byRating.isEmpty {
                    chartCard("Solved by problem rating") {
                        Chart(stats.byRating) { b in
                            BarMark(x: .value("Rating", b.label), y: .value("Solved", b.count)).foregroundStyle(cfRankColor(b.rating))
                        }.frame(height: 190)
                    }
                }
                if !stats.byTag.isEmpty {
                    chartCard("Solved by tag (\(stats.byTag.count) tags)") {
                        Chart(stats.byTag) { b in
                            BarMark(x: .value("Solved", b.count), y: .value("Tag", b.label)).foregroundStyle(Color.accentColor)
                                .annotation(position: .trailing) { Text("\(b.count)").font(.caption2).foregroundStyle(.secondary) }
                        }.frame(height: CGFloat(stats.byTag.count) * 26 + 20)
                    }
                }
                if !stats.byLetter.isEmpty {
                    chartCard("Solved by problem letter") {
                        Chart(stats.byLetter) { b in
                            BarMark(x: .value("Letter", b.label), y: .value("Solved", b.count)).foregroundStyle(Color.teal)
                        }.frame(height: 150)
                    }
                }
                if !stats.verdicts.isEmpty { listCard("Verdicts", stats.verdicts, total: stats.totalSubmissions) }
                if !stats.languages.isEmpty { listCard("Languages", stats.languages, total: stats.totalSubmissions) }
                unsolvedCard
            }
            .padding(16)
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $importTarget) { p in ImportProblemSheet(contestId: p.contestId, index: p.index) }
    }

    private var summary: some View {
        let items: [(String, String)] = [
            ("Submissions", "\(stats.totalSubmissions)"),
            ("Solved", "\(stats.solved)"),
            ("Rated solved", "\(stats.ratedSolved)"),
            ("Accepted rate", String(format: "%.0f%%", stats.acceptance * 100)),
            ("Avg tries / solve", stats.avgAttempts > 0 ? String(format: "%.1f", stats.avgAttempts) : "—"),
            ("Hardest solved", stats.hardest.map(String.init) ?? "—"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { it in
                VStack(spacing: 2) {
                    Text(it.1).font(.title3.bold())
                    Text(it.0).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 12).card()
            }
        }
    }

    private func chartCard<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func listCard(_ title: String, _ items: [Bucket], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(items.prefix(8)) { b in
                HStack {
                    Text(b.label).font(.subheadline)
                    Spacer()
                    Text("\(b.count)").font(.subheadline.weight(.semibold))
                    Text(total > 0 ? String(format: "%.0f%%", Double(b.count) / Double(total) * 100) : "")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    @ViewBuilder private var unsolvedCard: some View {
        if !stats.unsolved.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tried but not solved (\(stats.unsolved.count))").font(.headline).padding(14)
                ForEach(stats.unsolved.prefix(60)) { p in
                    Divider().padding(.leading, 14)
                    Button { importTarget = p } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(p.id) · \(p.name)").font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Text("\(p.attempts) submission\(p.attempts == 1 ? "" : "s") · \(p.last.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
            }.card()
        }
    }
}
