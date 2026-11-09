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
    var inputs: [String]?
    var outputs: [String]?
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
