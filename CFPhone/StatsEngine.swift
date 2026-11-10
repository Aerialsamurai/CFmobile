import Foundation

struct Bucket: Identifiable, Hashable {
    let label: String
    let count: Int
    var rating: Int? = nil
    var id: String { label }
}

struct UnsolvedProblem: Identifiable, Hashable {
    let contestId: Int
    let index: String
    let name: String
    let attempts: Int
    let last: Date
    var id: String { "\(contestId)\(index)" }
}

struct UserStats {
    var totalSubmissions = 0
    var accepted = 0
    var solved = 0
    var ratedSolved = 0
    var solvedIDs: Set<String> = []
    var acceptance: Double = 0
    var avgAttempts: Double = 0
    var hardest: Int? = nil
    var solvedLast30 = 0
    var activeDays = 0
    var currentStreak = 0
    var longestStreak = 0
    var solvedToday = false
    var acByDay: [Date: Int] = [:]
    var byRating: [Bucket] = []
    var byTag: [Bucket] = []
    var byLetter: [Bucket] = []
    var verdicts: [Bucket] = []
    var languages: [Bucket] = []
    var unsolved: [UnsolvedProblem] = []
}

/// Everything on the Profile tab is computed from the user's own submissions (no extra API calls).
enum StatsEngine {
    static func normalizeLanguage(_ l: String) -> String {
        let s = l.lowercased()
        if s.contains("c++") { return "C++" }
        if s.contains("pypy") { return "PyPy" }
        if s.contains("python") { return "Python" }
        if s.contains("kotlin") { return "Kotlin" }
        if s.contains("javascript") || s.contains("node") { return "JavaScript" }
        if s.contains("java") { return "Java" }
        if s.contains("rust") { return "Rust" }
        if s.contains("go ") || s == "go" { return "Go" }
        if s.contains("c#") || s.contains("mono") { return "C#" }
        if s.hasPrefix("gnu c") { return "C" }
        return String(l.prefix(14))
    }

    static func letter(_ index: String) -> String {
        guard let c = index.uppercased().first else { return "?" }
        return c > "G" ? "H+" : String(c)
    }

    static func compute(_ subs: [CFSubmission], now: Date = Date(), calendar: Calendar = .current) -> UserStats {
        var s = UserStats()
        s.totalSubmissions = subs.count
        let sorted = subs.sorted { $0.creationTimeSeconds < $1.creationTimeSeconds }

        var solvedProblem: [String: CFProblem] = [:]
        var firstAC: [String: Date] = [:]
        var failedBefore: [String: Int] = [:]      // failed attempts before the first AC
        var lastAttempt: [String: Date] = [:]
        var refs: [String: CFProblem] = [:]
        var verdictCounts: [String: Int] = [:]
        var langCounts: [String: Int] = [:]
        var acDays: [Date: Int] = [:]
        var failures: [String: Int] = [:]
        var submissionCount: [String: Int] = [:]   // every submission on the problem, any verdict

        for sub in sorted {
            let key = "\(sub.problem.contestId ?? 0)\(sub.problem.index)"
            refs[key] = sub.problem
            lastAttempt[key] = sub.date
            submissionCount[key, default: 0] += 1
            let v = sub.verdict ?? "TESTING"
            verdictCounts[v, default: 0] += 1
            langCounts[normalizeLanguage(sub.programmingLanguage), default: 0] += 1

            if v == "OK" {
                s.accepted += 1
                acDays[calendar.startOfDay(for: sub.date), default: 0] += 1
                if solvedProblem[key] == nil {
                    solvedProblem[key] = sub.problem
                    firstAC[key] = sub.date
                    failedBefore[key] = failures[key, default: 0]
                }
            } else if v != "TESTING" && v != "COMPILATION_ERROR" && solvedProblem[key] == nil {
                failures[key, default: 0] += 1
            }
        }

        s.solved = solvedProblem.count
        s.solvedIDs = Set(solvedProblem.keys)
        s.acceptance = subs.isEmpty ? 0 : Double(s.accepted) / Double(subs.count)
        if !failedBefore.isEmpty {
            s.avgAttempts = Double(failedBefore.values.reduce(0, +)) / Double(failedBefore.count) + 1
        }
        s.hardest = solvedProblem.values.compactMap { $0.rating }.max()
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        s.solvedLast30 = firstAC.values.filter { $0 >= cutoff }.count
        s.acByDay = acDays
        s.activeDays = acDays.count

        // streaks (a day counts when it has at least one Accepted submission, in the phone's time zone)
        let today = calendar.startOfDay(for: now)
        var longest = 0, run = 0
        var prev: Date?
        for d in acDays.keys.sorted() {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = d
        }
        s.longestStreak = longest
        s.solvedToday = acDays[today] != nil
        var cursor = s.solvedToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var cur = 0
        while acDays[cursor] != nil {
            cur += 1
            guard let back = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = back
        }
        s.currentStreak = cur

        // CF Analytics rule: only RATED problems are counted in the charts and the unsolved list.
        func isRated(_ p: CFProblem) -> Bool { (p.rating ?? 0) > 0 }
        let ratedSolved = solvedProblem.values.filter(isRated)
        s.ratedSolved = ratedSolved.count

        var ratingCounts: [Int: Int] = [:]
        for p in ratedSolved { if let r = p.rating { ratingCounts[r, default: 0] += 1 } }
        s.byRating = ratingCounts.keys.sorted().map { Bucket(label: "\($0)", count: ratingCounts[$0] ?? 0, rating: $0) }

        var tagCounts: [String: Int] = [:]
        for p in ratedSolved { for t in p.tags ?? [] { tagCounts[t, default: 0] += 1 } }
        s.byTag = tagCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { Bucket(label: $0.key, count: $0.value) }

        var letterCounts: [String: Int] = [:]
        for p in ratedSolved { letterCounts[letter(p.index), default: 0] += 1 }
        s.byLetter = letterCounts.keys.sorted().map { Bucket(label: $0, count: letterCounts[$0] ?? 0) }

        s.verdicts = verdictCounts.sorted { $0.value > $1.value }
            .map { Bucket(label: CFAPI.verdictText($0.key == "TESTING" ? nil : $0.key), count: $0.value) }
        s.languages = langCounts.sorted { $0.value > $1.value }.prefix(6).map { Bucket(label: $0.key, count: $0.value) }

        // tried but never solved: rated problems with at least one submission and no Accepted one
        s.unsolved = submissionCount.compactMap { key, n -> UnsolvedProblem? in
            guard solvedProblem[key] == nil, let p = refs[key], isRated(p), let cid = p.contestId, let last = lastAttempt[key] else { return nil }
            return UnsolvedProblem(contestId: cid, index: p.index, name: p.name, attempts: n, last: last)
        }.sorted { $0.last > $1.last }
        return s
    }
}
