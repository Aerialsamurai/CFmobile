import SwiftUI

struct TestsTab: View {
    @EnvironmentObject var app: AppState
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
                Button("Submit to Codeforces") {
                    Task { submitCode = await app.sourceNow(); showSubmit = true }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct TestRow: View {
    @EnvironmentObject var app: AppState
    let index: Int
    let test: TestCase
    @State private var open = false

    var result: TestResult? { app.results[test.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                badge
                Text(test.isSample ? "Sample \(index)" : "Custom \(index)").font(.headline)
                Spacer()
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
