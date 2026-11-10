import Foundation

/// Many Codeforces samples pack several test cases into one input ("t" on the first line).
/// This turns them into one test per case so each can be run and debugged on its own.
enum SampleSplitter {
    private static func lines(_ s: String) -> [String] {
        var l = s.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        while let last = l.last, last.trimmingCharacters(in: .whitespaces).isEmpty { l.removeLast() }
        return l
    }

    private static func ints(_ line: String) -> [Int] {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
    }

    /// Returns one (input, expected) pair per case, or nil when the sample isn't multi-case / can't be split safely.
    /// `sizes` lets the user force how many lines each case uses (a single number repeats).
    static func split(input: String, expected: String, sizes: [Int]? = nil) -> [(input: String, expected: String)]? {
        let ls = lines(input)
        guard let first = ls.first, let t = Int(first.trimmingCharacters(in: .whitespaces)), t >= 2, t <= 500 else { return nil }
        let body = Array(ls.dropFirst())
        guard !body.isEmpty else { return nil }

        guard let groups = groupLines(body, t: t, sizes: sizes) else { return nil }

        // expected output: one line per case, or equal-sized blocks
        let outLines = lines(expected)
        var outs = [String](repeating: "", count: t)
        if outLines.count == t {
            outs = outLines
        } else if !outLines.isEmpty, outLines.count % t == 0 {
            let n = outLines.count / t
            for i in 0..<t { outs[i] = outLines[(i * n)..<((i + 1) * n)].joined(separator: "\n") }
        } // otherwise leave expected empty: the case still runs, just without a verdict

        return (0..<t).map { i -> (input: String, expected: String) in
            ("1\n" + groups[i].joined(separator: "\n") + "\n", outs[i].isEmpty ? "" : outs[i] + "\n")
        }
    }

    private static func groupLines(_ body: [String], t: Int, sizes: [Int]?) -> [[String]]? {
        // 1. user-forced sizes
        if let sizes = sizes, !sizes.isEmpty {
            let full = sizes.count == 1 ? [Int](repeating: sizes[0], count: t) : sizes
            guard full.count == t, full.allSatisfy({ $0 > 0 }), full.reduce(0, +) == body.count else { return nil }
            var out: [[String]] = []; var at = 0
            for n in full { out.append(Array(body[at..<(at + n)])); at += n }
            return out
        }
        // 2. every case has the same number of lines, with matching header shapes
        if body.count % t == 0 {
            let n = body.count / t
            let groups = (0..<t).map { Array(body[($0 * n)..<(($0 + 1) * n)]) }
            let shape = Set(groups.map { ints($0[0]).count })
            if shape.count == 1 { return groups }
        }
        // 3. header "n m": the next m (or n) lines belong to this case ("n then n lines" style)
        for tokenIndex in 0..<3 {
            for extra in [0, 1] {            // extra: lines after the header that are not counted
                var out: [[String]] = []; var at = 0; var ok = true
                for _ in 0..<t {
                    guard at < body.count else { ok = false; break }
                    let h = ints(body[at])
                    guard h.count > tokenIndex, h[tokenIndex] >= 0, h[tokenIndex] <= body.count else { ok = false; break }
                    let size = 1 + h[tokenIndex] + extra
                    guard at + size <= body.count else { ok = false; break }
                    out.append(Array(body[at..<(at + size)])); at += size
                }
                if ok && at == body.count { return out }
            }
        }
        return nil
    }
}
