import SwiftUI

struct EditorTab: View {
    @EnvironmentObject var app: AppState
    @State private var showProblems = false

    var body: some View {
        NavigationStack {
            Group {
                if let ed = app.editor {
                    EditorWebView(host: ed).ignoresSafeArea(.keyboard)
                }
            }
            .navigationTitle(app.current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showProblems = true } label: { Image(systemName: "list.bullet") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if app.compiling {
                        ProgressView()
                    } else {
                        Button {
                            Task { await app.compile() }
                        } label: { Label("Check", systemImage: "hammer") }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        app.selectedTab = 1
                        Task { await app.runAll() }
                    } label: { Image(systemName: "play.fill") }
                }
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
