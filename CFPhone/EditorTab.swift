import SwiftUI

struct EditorTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var showProblems = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let rd = app.reader {
                    ReaderWebView(host: rd)
                        .opacity(app.codeSegment == 0 ? 1 : 0)
                        .allowsHitTesting(app.codeSegment == 0)
                }
                if let ed = app.editor {
                    EditorWebView(host: ed)
                        .ignoresSafeArea(.keyboard)
                        .opacity(app.codeSegment == 1 ? 1 : 0)
                        .allowsHitTesting(app.codeSegment == 1)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showProblems = true } label: { Image(systemName: "list.bullet") }
                }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $app.codeSegment) {
                        Text("Problem").tag(0)
                        Text("Code").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if app.codeSegment == 0 {
                        // reading aids for the statement
                        Menu {
                            Toggle("Bold key words", isOn: $settings.readerHighlight)
                            Toggle("One sentence per line", isOn: $settings.readerSentences)
                            Toggle("Limits summary", isOn: $settings.readerConstraints)
                            Toggle("Serif font", isOn: $settings.readerSerif)
                            Divider()
                            Button { settings.readerFontSize = min(26, settings.readerFontSize + 1) } label: { Label("Larger text", systemImage: "plus.magnifyingglass") }
                            Button { settings.readerFontSize = max(13, settings.readerFontSize - 1) } label: { Label("Smaller text", systemImage: "minus.magnifyingglass") }
                        } label: { Image(systemName: "textformat.size") }
                    } else {
                        if app.compiling {
                            ProgressView()
                        } else {
                            Button { Task { await app.compile() } } label: { Label("Check", systemImage: "hammer") }
                        }
                        Button {
                            app.selectedTab = 1
                            Task { await app.runAll() }
                        } label: { Image(systemName: "play.fill") }
                    }
                }
            }
            .onChange(of: app.codeSegment) { seg in
                if seg == 0 { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
            .sheet(isPresented: $showProblems) { ProblemsSheet() }
        }
    }
}

struct ProblemsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var importTarget: ImportTarget?
    @State private var error = ""

    struct ImportTarget: Identifiable { let contestId: Int; let index: String; var id: String { "\(contestId)\(index)" } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProblemsetView(onPicked: { dismiss() })
                    } label: {
                        Label("Browse problemset", systemImage: "square.grid.2x2")
                    }
                }
                Section("Import from Codeforces") {
                    TextField("Paste problem URL", text: $urlText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Import problem") {
                        if let (c, i) = CFAPI.parseProblemURL(urlText) { error = ""; importTarget = ImportTarget(contestId: c, index: i) }
                        else { error = "That doesn't look like a Codeforces problem link." }
                    }.disabled(urlText.isEmpty)
                    if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                Section("Problems") {
                    ForEach(app.problems) { p in
                        Button {
                            app.openProblem(p.id); dismiss()
                        } label: {
                            HStack {
                                Text(p.title).foregroundStyle(.primary)
                                Spacer()
                                if p.id == app.currentID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .swipeActions { if p.id != "scratch" { Button("Delete", role: .destructive) { app.deleteProblem(p.id) } } }
                    }
                }
            }
            .navigationTitle("Problems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $importTarget, onDismiss: { if app.currentID != "scratch" { dismiss() } }) { t in
                ImportProblemSheet(contestId: t.contestId, index: t.index)
            }
        }
    }
}
