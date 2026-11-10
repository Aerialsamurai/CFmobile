import Foundation
import SwiftUI

let defaultTemplate = """
#include <bits/stdc++.h>
using namespace std;

#define int long long

void solve() {
    
}

signed main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t = 1;
    cin >> t;
    while (t--) solve();
    return 0;
}

"""

@MainActor
final class AppState: ObservableObject {
    let settings: Settings

    // boot
    @Published var bootError: String?
    @Published var editor: EditorHost?
    @Published var engine: EngineHost?
    @Published var reader: ReaderHost?
    @Published var codeSegment = 1   // 0 = problem statement, 1 = code

    // problems
    @Published var problems: [Problem] = []
    @Published var currentID: String = "scratch"

    // compile / run
    @Published var compiling = false
    @Published var diagnostics: [Diagnostic] = []
    @Published var results: [UUID: TestResult] = [:]
    @Published var runningAll = false
    @Published var lastCompileMs: Int?

    // cross-tab requests
    @Published var selectedTab = 0
    @Published var submissionsNeedRefresh = 0
    /// Problems the user has solved (from their submissions); used to reveal hidden tags/ratings.
    @Published var solvedIDs: Set<String> = [] { didSet { renderReader() } }
    @Published var registeredContests: Set<Int> = []
    @Published var pendingRegistration: CFContest?   // opened in the browser; asks "did you register?" on return
    @Published var pendingSubmit = false             // opened the submit page in the browser
    @Published var liveContestActive = false   // set by the Contests tab; used to keep prompts out of contests

    private var server: LocalServer?
    private var code = ""
    private var compiledCode: String?
    private var saveTask: Task<Void, Never>?

    init(settings: Settings) {
        self.settings = settings
        registeredContests = Set(settings.registeredLocal)
        loadProblems()
    }

    // MARK: - Paths

    private var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("cfphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var codeDir: URL {
        let u = supportDir.appendingPathComponent("code", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var problemsFile: URL { supportDir.appendingPathComponent("problems.json") }
    /// Lives in the app's Documents folder, which shows up in the Files app (On My iPhone ▸ CF Phone).
    var templateURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("template.cpp") }

    // MARK: - Boot

    func boot() async {
        guard editor == nil else { return }
        guard let web = Bundle.main.url(forResource: "web", withExtension: nil) else {
            bootError = "App is missing its web files (build problem)."; return
        }
        if !FileManager.default.fileExists(atPath: templateURL.path) { saveTemplate(defaultTemplate) }
        do {
            let s = LocalServer(root: web)
            let port = try await s.start()
            server = s
            let base = URL(string: "http://127.0.0.1:\(port)/")!
            let ed = EditorHost(base: base)
            ed.onCode = { [weak self] c in Task { @MainActor in self?.codeChanged(c) } }
            editor = ed
            engine = EngineHost(base: base)
            let rd = ReaderHost(base: base)
            reader = rd
            applyAppearance()
            openProblem(currentID)
            Task { await refreshSolved() }
        } catch {
            bootError = "Could not start local server: \(error.localizedDescription)"
        }
    }

    // MARK: - Template

    func loadTemplate() -> String {
        if let t = try? String(contentsOf: templateURL, encoding: .utf8), !t.isEmpty { return t }
        return defaultTemplate
    }

    func saveTemplate(_ text: String) { try? text.write(to: templateURL, atomically: true, encoding: .utf8) }

    func importTemplate(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return false }
        saveTemplate(t)
        return true
    }

    // MARK: - Problems

    var current: Problem {
        problems.first { $0.id == currentID } ?? problems[0]
    }

    private func loadProblems() {
        if let d = try? Data(contentsOf: problemsFile), let p = try? JSONDecoder().decode([Problem].self, from: d), !p.isEmpty {
            problems = p
        }
        if !problems.contains(where: { $0.id == "scratch" }) {
            problems.insert(Problem(id: "scratch", title: "Scratch pad", url: "", timeLimitMs: 4000, tests: [], contestId: nil, index: nil, updated: Date()), at: 0)
        }
    }

    private func persistProblems() {
        if let d = try? JSONEncoder().encode(problems) { try? d.write(to: problemsFile) }
    }

    private func codeFile(_ id: String) -> URL { codeDir.appendingPathComponent("\(id).cpp") }

    func openProblem(_ id: String) {
        guard problems.contains(where: { $0.id == id }) else { return }
        flushSave()
        currentID = id
        let text = (try? String(contentsOf: codeFile(id), encoding: .utf8)) ?? loadTemplate()
        code = text
        compiledCode = nil
        results = [:]
        diagnostics = []
        editor?.setCode(text)
        renderReader()
        if !FileManager.default.fileExists(atPath: codeFile(id).path) { try? text.write(to: codeFile(id), atomically: true, encoding: .utf8) }
    }

    func codeChanged(_ c: String) {
        code = c
        saveTask?.cancel()
        saveTask = Task { [id = currentID] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            try? c.write(to: self.codeFile(id), atomically: true, encoding: .utf8)
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        if !code.isEmpty { try? code.write(to: codeFile(currentID), atomically: true, encoding: .utf8) }
    }

    func addImported(_ ip: ImportedProblem, contestId: Int, index: String, url: String, tags: [String]? = nil, rating: Int? = nil) {
        let id = "\(contestId)\(index)"
        let tests = buildSampleTests(inputs: ip.inputs ?? [], outputs: ip.outputs ?? [])
        let title = "\(contestId)\(index) · \(ip.title ?? "Problem")"
        let ioMode = ip.input
        if let i = problems.firstIndex(where: { $0.id == id }) {
            // keep the user's custom tests, refresh samples + statement
            let custom = problems[i].tests.filter { !$0.isSample }
            problems[i].tests = tests + custom
            problems[i].title = title
            problems[i].timeLimitMs = ip.timeLimitMs ?? 2000
            problems[i].statementHTML = ip.statement
            problems[i].memoryLimit = ip.memoryLimit
            problems[i].ioMode = ioMode
            if let tags = tags { problems[i].tags = tags }
            if let rating = rating { problems[i].rating = rating }
            problems[i].updated = Date()
        } else {
            var p = Problem(id: id, title: title, url: url, timeLimitMs: ip.timeLimitMs ?? 2000, tests: tests,
                            contestId: contestId, index: index, updated: Date())
            p.statementHTML = ip.statement
            p.memoryLimit = ip.memoryLimit
            p.ioMode = ioMode
            p.tags = tags
            p.rating = rating
            problems.insert(p, at: 1)
        }
        persistProblems()
        openProblem(id)
        codeSegment = 0          // show the statement first
        selectedTab = 0
    }

    /// Turns raw samples into tests, splitting multi-case samples into one test per case.
    private func buildSampleTests(inputs: [String], outputs: [String]) -> [TestCase] {
        var tests: [TestCase] = []
        for i in 0..<min(inputs.count, outputs.count) {
            tests += sampleTests(number: i + 1, input: inputs[i], expected: outputs[i], sizes: nil, split: settings.autoSplit)
        }
        return tests
    }

    private func sampleTests(number n: Int, input: String, expected: String, sizes: [Int]?, split: Bool) -> [TestCase] {
        if split, let parts = SampleSplitter.split(input: input, expected: expected, sizes: sizes) {
            var out: [TestCase] = []
            for (k, part) in parts.enumerated() {
                out.append(TestCase(input: part.input, expected: part.expected, isSample: true, label: "Sample \(n) · case \(k + 1)", group: n))
            }
            out.append(TestCase(input: input, expected: expected, isSample: true, label: "Sample \(n) · all cases together", isCombined: true, group: n))
            return out
        }
        return [TestCase(input: input, expected: expected, isSample: true, group: n)]
    }

    /// Re-splits one sample. `sizes` = lines per case (one number, or one per case); nil = automatic.
    /// Returns false when the sample can't be split that way.
    @discardableResult
    func resplit(group: Int, sizes: [Int]?) -> Bool {
        guard let i = problems.firstIndex(where: { $0.id == currentID }) else { return false }
        guard let original = problems[i].tests.first(where: { $0.isSample && $0.group == group && ($0.isCombined == true || $0.label == nil) }) else { return false }
        guard SampleSplitter.split(input: original.input, expected: original.expected, sizes: sizes) != nil else { return false }
        let fresh = sampleTests(number: group, input: original.input, expected: original.expected, sizes: sizes, split: true)
        guard let at = problems[i].tests.firstIndex(where: { $0.isSample && $0.group == group }) else { return false }
        problems[i].tests.removeAll { $0.isSample && $0.group == group }
        problems[i].tests.insert(contentsOf: fresh, at: min(at, problems[i].tests.count))
        results = [:]
        persistProblems()
        return true
    }

    /// Undo splitting for one sample (back to a single combined test).
    func unsplit(group: Int) {
        guard let i = problems.firstIndex(where: { $0.id == currentID }),
              let original = problems[i].tests.first(where: { $0.isSample && $0.group == group && $0.isCombined == true }),
              let at = problems[i].tests.firstIndex(where: { $0.isSample && $0.group == group }) else { return }
        problems[i].tests.removeAll { $0.isSample && $0.group == group }
        problems[i].tests.insert(TestCase(input: original.input, expected: original.expected, isSample: true, group: group), at: min(at, problems[i].tests.count))
        results = [:]
        persistProblems()
    }

    func deleteProblem(_ id: String) {
        guard id != "scratch" else { return }
        problems.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: codeFile(id))
        persistProblems()
        if currentID == id { openProblem("scratch") }
    }

    func updateCurrent(_ change: (inout Problem) -> Void) {
        guard let i = problems.firstIndex(where: { $0.id == currentID }) else { return }
        change(&problems[i])
        persistProblems()
    }

    func addCustomTest(input: String, expected: String) {
        updateCurrent { $0.tests.append(TestCase(input: input, expected: expected, isSample: false)) }
    }

    /// From the submission detail screen: save the test your solution failed on.
    func addFailingTest(problemID: String, input: String, expected: String) {
        guard let i = problems.firstIndex(where: { $0.id == problemID }) else { return }
        let inp = input.hasSuffix("\n") ? input : input + "\n"
        problems[i].tests.append(TestCase(input: inp, expected: expected.isEmpty ? "" : (expected.hasSuffix("\n") ? expected : expected + "\n"),
                                          isSample: false, label: "Failed on Codeforces"))
        persistProblems()
    }

    func deleteTest(_ id: UUID) {
        updateCurrent { $0.tests.removeAll { $0.id == id } }
        results[id] = nil
    }

    // MARK: - Theme / font push

    /// Shows the current problem in the reader, hiding tags / rating if the user asked to (unless already solved).
    func renderReader() {
        guard let reader = reader else { return }
        let p = problems.first { $0.id == currentID }
        let solved = settings.revealWhenSolved && solvedIDs.contains(currentID)
        reader.render(p, hideTags: settings.hideTags && !solved, hideRating: settings.hideRating && !solved)
    }

    func noteSolved(_ ids: Set<String>) {
        if !ids.isSubset(of: solvedIDs) { solvedIDs.formUnion(ids) }
    }

    /// One quiet request at launch so tags/ratings of problems you already solved are not hidden.
    func refreshSolved() async {
        guard !settings.handle.isEmpty,
              let subs = try? await CFAPI.allSubmissions(handle: settings.handle) else { return }
        noteSolved(Set(subs.filter { $0.verdict == "OK" }.map { "\($0.problem.contestId ?? 0)\($0.problem.index)" }))
    }

    func markRegistered(_ id: Int, _ on: Bool = true) {
        if on { registeredContests.insert(id) } else { registeredContests.remove(id) }
        settings.registeredLocal = Array(registeredContests)
    }

    func applyAppearance() {
        editor?.setTheme(settings.theme)
        editor?.setFontSize(settings.fontSize)
        editor?.setOptions(indent: settings.indentSize, autoClose: settings.autoClose, chips: settings.snippetRow, haptics: settings.haptics)
        reader?.setTheme(settings.theme)
        reader?.setFontSize(settings.readerFontSize)
        reader?.setPrefs(highlight: settings.readerHighlight, sentences: settings.readerSentences, serif: settings.readerSerif)
        renderReader()
    }

    // MARK: - Compile / run

    func sourceNow() async -> String {
        if let c = await editor?.currentCode() { code = c; return c }
        return code
    }

    @discardableResult
    func compile() async -> Bool {
        guard let engine = engine else { return false }
        let src = await sourceNow()
        if compiledCode == src { return true }
        compiling = true
        defer { compiling = false }
        do {
            let r = try await engine.compile(src, std: settings.std, checks: settings.checks)
            lastCompileMs = r.ms
            diagnostics = r.diagnostics
            if r.ok { compiledCode = src } else { compiledCode = nil }
            if r.diagnostics.isEmpty { editor?.clearDiagnostics() } else { editor?.setDiagnostics(r.diagnostics) }
            if !r.ok && r.diagnostics.isEmpty {
                diagnostics = [Diagnostic(line: 1, col: nil, severity: "error", message: "Compilation failed. Raw output: " + String(r.raw.prefix(160)))]
                editor?.setDiagnostics(diagnostics)
            }
            return r.ok
        } catch {
            diagnostics = [Diagnostic(line: 1, col: nil, severity: "error", message: "Compiler problem: \(error.localizedDescription)")]
            return false
        }
    }

    func runTest(_ t: TestCase) async {
        guard let engine = engine else { return }
        results[t.id] = TestResult(verdict: .running)
        do {
            let r = try await engine.runOne(input: t.input, expected: t.expected.isEmpty ? nil : t.expected, timeLimitMs: max(current.timeLimitMs * 2, 4000))
            let v = Verdict(rawValue: r.verdict) ?? .re
            var res = TestResult(verdict: v, output: r.stdout ?? "", ms: r.ms ?? 0, message: r.fault?.message ?? "")
            if v == .tle { res.message = "Time limit exceeded (phone limit)" }
            results[t.id] = res
            if let f = r.fault, f.kind == "ub", let line = f.line {
                let d = Diagnostic(line: line, col: nil, severity: "error", message: f.message)
                diagnostics = [d]
                editor?.setDiagnostics([d])
            }
        } catch {
            results[t.id] = TestResult(verdict: .re, message: error.localizedDescription)
        }
    }

    func runAll() async {
        runningAll = true
        defer { runningAll = false }
        results = [:]
        guard await compile() else { return }
        for t in current.tests { await runTest(t) }
    }

    func runSingle(_ t: TestCase) async {
        guard await compile() else { return }
        await runTest(t)
    }

    var allPassed: Bool {
        let tests = current.tests
        return !tests.isEmpty && tests.allSatisfy { results[$0.id]?.verdict == .ac }
    }
}
