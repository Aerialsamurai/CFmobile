import SwiftUI

struct TestsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var showAdd = false
    @State private var showSubmit = false
    @State private var confirmSubmit = false
    @State private var submitCode = ""

    var body: some View {
        NavigationStack {
            List {
                if !app.diagnostics.isEmpty {
                    Section {
                        ForEach(app.diagnostics.prefix(3)) { d in
                            HStack(alignment: .top, spacing: 10) {
                                Text("Line \(d.line)").bold().foregroundColor(d.severity == "error" ? Color.red : Color.orange)
                                Text(d.message)
                            }.font(.subheadline)
                        }
                    } header: { Text(app.diagnostics.contains { $0.severity == "error" } ? "Fix this first" : "Heads up") }
                }
                Section {
                    if app.current.tests.isEmpty {
                        Text("No tests yet. Import a problem from the Code tab, or add your own.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(app.current.tests.enumerated()), id: \.element.id) { pair in
                        TestRow(index: pair.offset + 1, test: pair.element)
                            .swipeActions { if !pair.element.isSample { Button("Delete", role: .destructive) { app.deleteTest(pair.element.id) } } }
                    }
                } header: {
                    HStack {
                        Text(app.current.title)
                        Spacer()
                        if let ms = app.lastCompileMs { Text("compiled in \(ms) ms").font(.caption2) }
                    }
                }
            }
            .navigationTitle("Tests")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if app.runningAll || app.compiling { ProgressView() }
                    else { Button { Task { await app.runAll() } } label: { Label("Run all", systemImage: "play.fill") } }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") { confirmSubmit = true }
                        .disabled(app.current.contestId == nil)
                }
            }
            .sheet(isPresented: $showAdd) { AddTestSheet() }
            .sheet(isPresented: $showSubmit) { SubmitSheet(problem: app.current, code: submitCode) }
            .confirmationDialog(app.allPassed ? "Submit \(app.current.id)?" : "Not all tests pass yet. Submit \(app.current.id) anyway?",
                                isPresented: $confirmSubmit, titleVisibility: .visible) {
                if settings.useDefaultBrowser {
                    browserButton
                    inAppButton
                } else {
                    inAppButton
                    browserButton
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(settings.useDefaultBrowser
                     ? "Your code is copied to the clipboard and Codeforces opens in your browser, where your saved password works."
                     : "The app fills in and sends the form for you (needs the in-app Codeforces login).")
            }
        }
    }

    private var inAppButton: some View {
        Button("Submit in the app") {
            Task { submitCode = await app.sourceNow(); showSubmit = true }
        }
    }

    private var browserButton: some View {
        Button("Copy code & open in browser") {
            Task {
                let code = await app.sourceNow()
                UIPasteboard.general.string = code
                if let cid = app.current.contestId, let idx = app.current.index,
                   let url = URL(string: "https://codeforces.com/contest/\(cid)/submit/\(idx)") {
                    app.pendingSubmit = true
                    Browser.open(url)
                }
            }
        }
    }
}

struct TestRow: View {
    @EnvironmentObject var app: AppState
    let index: Int
    let test: TestCase
    @State private var open = false
    @State private var splitGroup: Int?
    @State private var splitFailed = false

    var result: TestResult? { app.results[test.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge
                Text(test.label ?? (test.isSample ? "Sample \(test.group ?? index)" : "Custom \(index)")).font(.headline).lineLimit(1)
                Spacer()
                if let g = test.group, test.isSample {
                    Menu {
                        Button("Auto-split into cases") { if !app.resplit(group: g, sizes: nil) { splitFailed = true } }
                        Button("Split by lines…") { splitGroup = g }
                        Button("Merge back into one", role: .destructive) { app.unsplit(group: g) }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .buttonStyle(.borderless)
                }
                if let r = result, r.ms > 0 { Text("\(r.ms) ms").font(.caption).foregroundStyle(.secondary) }
                Button { Task { await app.runSingle(test) } } label: { Image(systemName: "play.circle").font(.title3) }
                    .buttonStyle(.borderless)
            }
            if let r = result, !r.message.isEmpty {
                Text(r.message).font(.footnote).foregroundStyle(r.verdict == .ac ? Color.secondary : Color.red)
            }
            if open || result?.verdict == .wa {
                block("Input", test.input)
                if !test.expected.isEmpty { block("Expected", test.expected) }
                if let r = result, r.verdict != .idle, r.verdict != .running { block("Your output", r.output.isEmpty ? "(empty)" : r.output) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { open.toggle() } }
        .padding(.vertical, 2)
        .sheet(item: Binding(get: { splitGroup.map { GroupID(id: $0) } }, set: { splitGroup = $0?.id })) { g in SplitSheet(group: g.id) }
        .alert("Couldn't split this sample", isPresented: $splitFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("It doesn't look like a multi-case input, or the lines don't divide evenly. Try \"Split by lines…\".") }
    }

    @ViewBuilder var badge: some View {
        switch result?.verdict ?? .idle {
        case .running: ProgressView().scaleEffect(0.8)
        case .ac: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .wa: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .tle: Image(systemName: "clock.badge.exclamationmark.fill").foregroundStyle(.orange)
        case .re: Image(systemName: "bolt.circle.fill").foregroundStyle(.red)
        case .ran: Image(systemName: "checkmark.circle").foregroundStyle(.blue)
        default: Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text.count > 1500 ? String(text.prefix(1500)) + "…" : text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct AddTestSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var expected = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Input") { TextEditor(text: $input).font(.system(.body, design: .monospaced)).frame(minHeight: 120).autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section("Expected output (optional)") { TextEditor(text: $expected).font(.system(.body, design: .monospaced)).frame(minHeight: 80).autocorrectionDisabled().textInputAutocapitalization(.never) }
            }
            .navigationTitle("New test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        app.addCustomTest(input: input.hasSuffix("\n") ? input : input + "\n", expected: expected)
                        dismiss()
                    }.disabled(input.isEmpty)
                }
            }
        }
    }
}

struct GroupID: Identifiable { let id: Int }

/// Manual fallback: say how many lines each case uses ("2", or "2,3,2" for uneven cases).
struct SplitSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let group: Int
    @State private var text = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 2   or   2,3,2", text: $text).keyboardType(.numbersAndPunctuation)
                } header: { Text("Lines per test case") } footer: {
                    Text("Count the lines after the first line (the number of cases). One number applies to every case; a list gives each case its own size.")
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Split sample")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        let sizes = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }
                        if !sizes.isEmpty, app.resplit(group: group, sizes: sizes) { dismiss() }
                        else { error = "Those sizes don't add up to the lines in this sample." }
                    }.disabled(text.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
