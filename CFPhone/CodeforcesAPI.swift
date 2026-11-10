import Foundation

struct APIError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

enum CFAPI {
    /// Codeforces allows about one API call per 2 seconds; when it says so, wait and try again (twice).
    static func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        var lastError: Error = APIError("Codeforces API error")
        for attempt in 0..<3 {
            do { return try await getOnce(path, query) }
            catch let e as APIError where e.message.lowercased().contains("limit exceeded") {
                lastError = e
                try? await Task.sleep(nanoseconds: UInt64(2_300_000_000 * Double(attempt + 1)))
            }
        }
        throw lastError
    }

    private static func getOnce<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var c = URLComponents(string: "https://codeforces.com/api/\(path)")!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        let r: CFResponse<T>
        do { r = try JSONDecoder().decode(CFResponse<T>.self, from: data) }
        catch { throw APIError("Codeforces returned an unexpected response (it may be busy or showing a check). Try again.") }
        guard r.status == "OK", let res = r.result else { throw APIError(r.comment ?? "Codeforces API error") }
        return res
    }

    /// Running + upcoming contests, soonest first.
    static func contests() async throws -> [CFContest] {
        let all: [CFContest] = try await get("contest.list", ["gym": "false"])
        let relevant = all.filter { $0.phase == "BEFORE" || $0.phase == "CODING" }
        return relevant.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    static func submissions(handle: String, count: Int = 40) async throws -> [CFSubmission] {
        try await get("user.status", ["handle": handle, "from": "1", "count": String(count)])
    }

    static func contestProblems(_ contestId: Int) async throws -> [CFProblem] {
        let s: CFStandings = try await get("contest.standings", ["contestId": String(contestId), "from": "1", "count": "1"])
        return s.problems
    }

    static func userInfo(_ handle: String) async throws -> CFUser {
        let list: [CFUser] = try await get("user.info", ["handles": handle])
        guard let u = list.first else { throw APIError("No such user: \(handle)") }
        return u
    }

    static func ratingHistory(_ handle: String) async throws -> [CFRatingChange] {
        try await get("user.rating", ["handle": handle])
    }

    /// Every submission the user ever made (the API returns them newest first).
    static func allSubmissions(handle: String) async throws -> [CFSubmission] {
        try await get("user.status", ["handle": handle])
    }

    static func problemURL(contestId: Int, index: String) -> URL {
        URL(string: "https://codeforces.com/contest/\(contestId)/problem/\(index)")!
    }

    /// Accepts the usual URL shapes and returns (contestId, index).
    static func parseProblemURL(_ text: String) -> (Int, String)? {
        let patterns = [
            #"codeforces\.(?:com|es)/(?:contest|gym)/(\d+)/problem/([A-Za-z0-9]+)"#,
            #"codeforces\.(?:com|es)/problemset/problem/(\d+)/([A-Za-z0-9]+)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text),
               let cid = Int(text[r1]) {
                return (cid, String(text[r2]).uppercased())
            }
        }
        return nil
    }

    static func verdictText(_ v: String?) -> String {
        switch v {
        case nil, "TESTING": return "Running"
        case "OK": return "Accepted"
        case "WRONG_ANSWER": return "Wrong answer"
        case "TIME_LIMIT_EXCEEDED": return "Time limit"
        case "MEMORY_LIMIT_EXCEEDED": return "Memory limit"
        case "RUNTIME_ERROR": return "Runtime error"
        case "COMPILATION_ERROR": return "Compile error"
        case "IDLENESS_LIMIT_EXCEEDED": return "Idleness limit"
        case "PRESENTATION_ERROR": return "Presentation error"
        case "SKIPPED": return "Skipped"
        case "CHALLENGED": return "Hacked"
        case "REJECTED": return "Rejected"
        default: return v?.replacingOccurrences(of: "_", with: " ").capitalized ?? "—"
        }
    }
}
