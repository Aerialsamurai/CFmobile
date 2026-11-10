import Foundation

// MARK: - Editor / engine models (shapes match the JS side)

struct Diagnostic: Codable, Hashable, Identifiable {
    var line: Int
    var col: Int?
    var severity: String   // "error" | "warning"
    var message: String
    var id: String { "\(line)-\(severity)-\(message)" }
}

struct TestCase: Codable, Identifiable, Hashable {
    var id = UUID()
    var input: String
    var expected: String
    var isSample: Bool
    var label: String? = nil        // e.g. "Sample 1 · case 2"
    var isCombined: Bool? = nil     // the original multi-case sample, kept for a final check
    var group: Int? = nil           // which sample (1-based) this came from
}

struct Problem: Codable, Identifiable, Hashable {
    var id: String            // "1900A" or "scratch"
    var title: String
    var url: String
    var timeLimitMs: Int
    var tests: [TestCase]
    var contestId: Int?
    var index: String?
    var updated: Date
    var statementHTML: String? = nil
    var memoryLimit: String? = nil
    var ioMode: String? = nil
    var tags: [String]? = nil
    var rating: Int? = nil
}

enum Verdict: String {
    case idle, running, ac = "AC", wa = "WA", tle = "TLE", re = "RE", ran = "RAN", nc = "NC"
}

struct TestResult {
    var verdict: Verdict
    var output: String = ""
    var ms: Int = 0
    var message: String = ""
}

struct CompileResult: Codable {
    var ok: Bool
    var ms: Int
    var diagnostics: [Diagnostic]
    var raw: String
}

struct RunResult: Codable {
    struct Fault: Codable {
        var kind: String
        var line: Int?
        var message: String
    }
    var verdict: String
    var stdout: String?
    var ms: Int?
    var fault: Fault?
    var message: String?
}

struct ImportedProblem: Codable {
    var ok: Bool
    var reason: String?
    var title: String?
    var timeLimitMs: Int?
    var timeLimit: String?
    var memoryLimit: String?
    var input: String?
    var output: String?
    var inputs: [String]?
    var outputs: [String]?
    var statement: String?
}

/// What Codeforces tells us about a failed test of one of your submissions.
struct SubmissionDetail: Codable {
    var ok: Bool
    var reason: String?
    var testCount: Int?
    var verdict: String?
    var input: String?
    var output: String?
    var answer: String?
    var checker: String?
}

// MARK: - Codeforces API models

struct CFResponse<T: Decodable>: Decodable {
    let status: String
    let comment: String?
    let result: T?
}

struct CFProblem: Codable, Hashable {
    let contestId: Int?
    let index: String
    let name: String
    let rating: Int?
    let tags: [String]?
}

struct CFProblemStat: Codable {
    let contestId: Int?
    let index: String
    let solvedCount: Int
}

struct CFProblemset: Decodable {
    let problems: [CFProblem]
    let problemStatistics: [CFProblemStat]
}

/// One row of the problemset browser.
struct PSProblem: Codable, Identifiable, Hashable {
    let contestId: Int
    let index: String
    let name: String
    let rating: Int?
    let tags: [String]
    let solved: Int
    var id: String { "\(contestId)\(index)" }
}

struct CFContest: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let phase: String
    let durationSeconds: Int
    let startTimeSeconds: Int?
    var start: Date? { startTimeSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var end: Date? { start.map { $0.addingTimeInterval(TimeInterval(durationSeconds)) } }
}

struct CFSubmission: Codable, Identifiable, Hashable {
    let id: Int
    let contestId: Int?
    let creationTimeSeconds: Int
    let problem: CFProblem
    let programmingLanguage: String
    let verdict: String?
    let passedTestCount: Int
    let timeConsumedMillis: Int
    let memoryConsumedBytes: Int
    var date: Date { Date(timeIntervalSince1970: TimeInterval(creationTimeSeconds)) }
    var isPending: Bool { verdict == nil || verdict == "TESTING" }
}

struct CFStandings: Decodable {
    let problems: [CFProblem]
}

// MARK: - Profile

struct CFUser: Codable, Hashable {
    let handle: String
    let rating: Int?
    let maxRating: Int?
    let rank: String?
    let maxRank: String?
    let avatar: String?
    let titlePhoto: String?
    let friendOfCount: Int?
    let contribution: Int?
    let country: String?
    let organization: String?
    let registrationTimeSeconds: Int?
}

struct CFRatingChange: Codable, Identifiable, Hashable {
    let contestId: Int
    let contestName: String
    let rank: Int
    let ratingUpdateTimeSeconds: Int
    let oldRating: Int
    let newRating: Int
    var id: Int { contestId }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ratingUpdateTimeSeconds)) }
    var delta: Int { newRating - oldRating }
}
