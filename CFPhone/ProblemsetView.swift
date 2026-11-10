import SwiftUI

// MARK: - Data

@MainActor
final class ProblemsetStore: ObservableObject {
    @Published var all: [PSProblem] = []
    @Published var loading = false
    @Published var error = ""
    @Published var solved: Set<String> = []
    @Published var attempted: Set<String> = []

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("cfphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("problemset.json")
    }

    func load(handle: String, force: Bool = false) async {
        loading = true
        error = ""
        defer { loading = false }

        // cached copy first (instant), refreshed if older than 12 hours
        var fresh = false
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([PSProblem].self, from: data), !cached.isEmpty {
            all = cached
            fresh = Date().timeIntervalSince(modified) < 12 * 3600
        }
        if force || !fresh {
            do {
                let ps: CFProblemset = try await CFAPI.get("problemset.problems")
                var stats: [String: Int] = [:]
                for s in ps.problemStatistics { if let c = s.contestId { stats["\(c)\(s.index)"] = s.solvedCount } }
                let list: [PSProblem] = ps.problems.compactMap { p in
                    guard let c = p.contestId else { return nil }
                    return PSProblem(contestId: c, index: p.index, name: p.name, rating: p.rating,
                                     tags: p.tags ?? [], solved: stats["\(c)\(p.index)"] ?? 0)
                }
                all = list
                if let d = try? JSONEncoder().encode(list) { try? d.write(to: cacheURL) }
            } catch {
                if all.isEmpty { self.error = error.localizedDescription }
            }
        }

        // which ones you have solved / tried
        if !handle.isEmpty, let subs: [CFSubmission] = try? await CFAPI.get("user.status", ["handle": handle]) {
            var ok = Set<String>(), tried = Set<String>()
            for s in subs {
                guard let c = s.problem.contestId else { continue }
                let id = "\(c)\(s.problem.index)"
                if s.verdict == "OK" { ok.insert(id) } else { tried.insert(id) }
            }
            solved = ok
            attempted = tried.subtracting(ok)
        }
    }
}

// MARK: - Filters

enum PSStatus: String, CaseIterable, Identifiable {
    case all = "All", unsolved = "Unsolved", solved = "Solved", attempted = "Tried, not solved"
    var id: String { rawValue }
}

enum PSSort: String, CaseIterable, Identifiable {
    case newest = "Newest", ratingUp = "Rating ↑", ratingDown = "Rating ↓", mostSolved = "Most solved"
    var id: String { rawValue }
}

struct PSFilters: Equatable {
    var minRating: Int? = nil
    var maxRating: Int? = nil
    var tags: Set<String> = []
    var matchAll = true
    var status: PSStatus = .all
    var sort: PSSort = .newest

    var isActive: Bool { minRating != nil || maxRating != nil || !tags.isEmpty || status != .all }
}

// MARK: - Browser

struct ProblemsetView: View {
    var onPicked: () -> Void
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @StateObject private var store = ProblemsetStore()
    @State private var query = ""
    @State private var filters = PSFilters()
    @State private var showFilters = false
    @State private var target: PSProblem?
    @State private var pickedID = ""

    private var allTags: [String] { Array(Set(store.all.flatMap { $0.tags })).sorted() }

    private var results: [PSProblem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = store.all.filter { p in
            if let lo = filters.minRating, (p.rating ?? 0) < lo { return false }
            if let hi = filters.maxRating, (p.rating ?? Int.max) > hi { return false }
            if !filters.tags.isEmpty {
                let have = Set(p.tags)
                if filters.matchAll ? !filters.tags.isSubset(of: have) : filters.tags.isDisjoint(with: have) { return false }
            }
            switch filters.status {
            case .all: break
            case .unsolved: if store.solved.contains(p.id) { return false }
            case .solved: if !store.solved.contains(p.id) { return false }
            case .attempted: if !store.attempted.contains(p.id) { return false }
            }
            if !q.isEmpty && !(p.name.lowercased().contains(q) || p.id.lowercased().contains(q)) { return false }
            return true
        }
        switch filters.sort {
        case .newest: list.sort { ($0.contestId, $0.index) > ($1.contestId, $1.index) }
        case .ratingUp: list.sort { ($0.rating ?? 9999, $0.contestId) < ($1.rating ?? 9999, $1.contestId) }
        case .ratingDown: list.sort { ($0.rating ?? 0, $0.contestId) > ($1.rating ?? 0, $1.contestId) }
        case .mostSolved: list.sort { $0.solved > $1.solved }
        }
        return list
    }

    var body: some View {
        let shown = results
        List {
            if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(.red) }
            Section {
                ForEach(shown.prefix(800)) { p in
                    Button { pickedID = p.id; target = p } label: { row(p) }
                }
            } header: {
                Text("\(shown.count) problems" + (shown.count > 800 ? " (showing first 800 — narrow the filters)" : ""))
            }
        }
        .listStyle(.plain)
        .navigationTitle("Problemset")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Name or id (e.g. 1900A)")
        .refreshable { await store.load(handle: settings.handle, force: true) }
        .overlay { if store.loading && store.all.isEmpty { ProgressView("Loading problems…") } }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) { PSFilterSheet(filters: $filters, tags: allTags) }
        .sheet(item: $target, onDismiss: { if app.currentID == pickedID { onPicked() } }) { p in
            ImportProblemSheet(contestId: p.contestId, index: p.index, tags: p.tags, rating: p.rating)
        }
        .task { await store.load(handle: settings.handle) }
    }

    private func row(_ p: PSProblem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(p).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(p.id) · \(p.name)").font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Spacer(minLength: 4)
                    if let r = p.rating { Text("\(r)").font(.subheadline.weight(.semibold)).foregroundColor(ratingColor(r)) }
                }
                if !p.tags.isEmpty {
                    Text(p.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("\(p.solved) solved").font(.caption2).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 2)
    }

    @ViewBuilder private func statusIcon(_ p: PSProblem) -> some View {
        if store.solved.contains(p.id) { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
        else if store.attempted.contains(p.id) { Image(systemName: "circle.lefthalf.filled").foregroundColor(.orange) }
        else { Image(systemName: "circle").foregroundColor(Color.secondary.opacity(0.4)) }
    }

    /// Codeforces rank colours.
    private func ratingColor(_ r: Int) -> Color {
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
}

struct PSFilterSheet: View {
    @Binding var filters: PSFilters
    let tags: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var tagSearch = ""

    private let ratings: [Int] = Array(stride(from: 800, through: 3500, by: 100))

    private var visibleTags: [String] {
        let q = tagSearch.lowercased()
        return q.isEmpty ? tags : tags.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    Picker("From", selection: $filters.minRating) {
                        Text("Any").tag(Int?.none)
                        ForEach(ratings, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    Picker("To", selection: $filters.maxRating) {
                        Text("Any").tag(Int?.none)
                        ForEach(ratings, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                }
                Section("Status") {
                    Picker("Show", selection: $filters.status) {
                        ForEach(PSStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Sort by", selection: $filters.sort) {
                        ForEach(PSSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    Picker("Match", selection: $filters.matchAll) {
                        Text("All selected tags").tag(true)
                        Text("Any selected tag").tag(false)
                    }.pickerStyle(.segmented)
                    TextField("Search tags", text: $tagSearch).textInputAutocapitalization(.never).autocorrectionDisabled()
                    ForEach(visibleTags, id: \.self) { t in
                        Button {
                            if filters.tags.contains(t) { filters.tags.remove(t) } else { filters.tags.insert(t) }
                        } label: {
                            HStack {
                                Text(t).foregroundStyle(.primary)
                                Spacer()
                                if filters.tags.contains(t) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } header: { Text("Tags" + (filters.tags.isEmpty ? "" : " (\(filters.tags.count))")) }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { filters = PSFilters() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
