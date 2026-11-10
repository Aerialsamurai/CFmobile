import Foundation

/// Turns Codeforces' checker comment + test data into one short, human sentence.
enum FailureExplainer {
    struct Explanation {
        var headline: String        // "Test 2 · your 3rd number was 5, expected 4"
        var detail: String?         // "That's on line 2 of the output."
    }

    private static func ordinal(_ n: Int) -> String {
        let m100 = n % 100
        if (11...13).contains(m100) { return "\(n)th" }
        switch n % 10 { case 1: return "\(n)st"; case 2: return "\(n)nd"; case 3: return "\(n)rd"; default: return "\(n)th" }
    }

    private static func match(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Which output line holds the n-th whitespace-separated token (1-based)?
    private static func lineOfToken(_ n: Int, in text: String) -> Int? {
        var seen = 0
        for (i, line) in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").enumerated() {
            seen += line.split(whereSeparator: { $0 == " " || $0 == "\t" }).count
            if seen >= n { return i + 1 }
        }
        return nil
    }

    static func explain(verdict: String?, passed: Int, detail d: SubmissionDetail?) -> Explanation {
        let testNo = (d?.testCount).flatMap { $0 > 0 ? $0 : nil } ?? (passed + 1)
        let testWord = "Test \(testNo)"
        let checker = (d?.checker ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch verdict {
        case "TIME_LIMIT_EXCEEDED": return Explanation(headline: "\(testWord) · too slow", detail: "Your program didn't finish within the time limit on this test.")
        case "MEMORY_LIMIT_EXCEEDED": return Explanation(headline: "\(testWord) · used too much memory", detail: nil)
        case "RUNTIME_ERROR": return Explanation(headline: "\(testWord) · your program crashed", detail: "Usually an out-of-range index, division by zero, or infinite recursion.")
        case "IDLENESS_LIMIT_EXCEEDED": return Explanation(headline: "\(testWord) · program waited for input that never came", detail: nil)
        case "COMPILATION_ERROR": return Explanation(headline: "Didn't compile on Codeforces", detail: "Check the language and compiler flags; your code compiled here.")
        default: break
        }

        // "wrong answer 3rd numbers differ - expected: '4', found: '5'"
        if let g = match(#"(\d+)(?:st|nd|rd|th) (number|word|line|token|integer|double|float)s? differ.*?expected: '(.*?)', found: '(.*?)'"#, in: checker),
           let k = Int(g[1]) {
            let kind = g[2] == "line" ? "line" : (g[2] == "word" || g[2] == "token" ? "word" : "number")
            var extra: String?
            if kind != "line", let out = d?.output, let line = lineOfToken(k, in: out) { extra = "That's on line \(line) of your output." }
            if kind == "line" { extra = nil }
            return Explanation(headline: "\(testWord) · your \(ordinal(k)) \(kind) was \(g[4]), expected \(g[3])", detail: extra)
        }
        // "wrong answer expected 'YES', found 'NO' [2nd token]"  or  "wrong answer expected YES, found NO"
        if let g = match(#"expected:? '?(.*?)'?,? found:? '?(.*?)'?(?: \[(\d+)(?:st|nd|rd|th) (?:token|word|number)\])?$"#, in: checker) {
            var head = "\(testWord) · you printed \(g[2]), expected \(g[1])"
            var extra: String?
            if g.count > 3, let k = Int(g[3]) {
                head = "\(testWord) · your \(ordinal(k)) value was \(g[2]), expected \(g[1])"
                if let out = d?.output, let line = lineOfToken(k, in: out) { extra = "That's on line \(line) of your output." }
            }
            return Explanation(headline: head, detail: extra)
        }
        if checker.lowercased().contains("extra") || checker.lowercased().contains("unexpected end") || checker.lowercased().contains("premature") {
            return Explanation(headline: "\(testWord) · wrong amount of output", detail: checker)
        }
        if !checker.isEmpty { return Explanation(headline: "\(testWord) · \(checker.replacingOccurrences(of: "wrong answer ", with: ""))", detail: nil) }
        return Explanation(headline: "\(testWord) · wrong answer", detail: nil)
    }
}
