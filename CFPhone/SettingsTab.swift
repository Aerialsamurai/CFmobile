import SwiftUI
import UniformTypeIdentifiers

struct SettingsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var showLogin = false
    @State private var importing = false
    @State private var editTemplate = false
    @State private var importMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Codeforces") {
                    HStack {
                        Text("Handle")
                        TextField("your_handle", text: $settings.handle)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button("Log in to Codeforces") { showLogin = true }
                    Text("Needed for submitting and registering. Your password is typed on codeforces.com itself and never stored by this app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Editor") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(Settings.themes, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    Stepper("Code font size: \(Int(settings.fontSize))", value: $settings.fontSize, in: 10...24)
                    Stepper("Problem text size: \(Int(settings.readerFontSize))", value: $settings.readerFontSize, in: 13...26)
                }

                Section {
                    Picker("Indent", selection: $settings.indentSize) {
                        Text("2 spaces").tag(2)
                        Text("4 spaces").tag(4)
                    }
                    Toggle("Auto-close brackets & quotes", isOn: $settings.autoClose)
                    Toggle("Snippet chips (cin>>, for, vector<…)", isOn: $settings.snippetRow)
                    Toggle("Haptic tap on key row", isOn: $settings.haptics)
                } header: { Text("Typing on a phone") } footer: {
                    Text("The row above the keyboard also has // (comment line), duplicate line, delete line, select line and move line up/down. Tip: hold the space bar and slide to move the cursor precisely.")
                }

                Section("Problems") {
                    Toggle("Split multi-case samples", isOn: $settings.autoSplit)
                }

                Section("Compiler") {
                    Picker("C++ standard", selection: $settings.std) {
                        ForEach(Settings.standards, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                    Toggle("Catch overflow & out-of-bounds", isOn: $settings.checks)
                    Text("Adds runtime checks while testing on your phone so the exact faulty line is marked red. Turn off for faster runs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Template") {
                    Text("Used for every new problem. Edit it here, import a .cpp/.txt file, or edit template.cpp directly in the Files app (On My iPhone ▸ CF Phone).")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Edit template") { editTemplate = true }
                    Button("Import template from file…") { importing = true }
                    if !importMessage.isEmpty { Text(importMessage).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("Contest reminders") {
                    Toggle("24 hours before", isOn: $settings.notifyDay)
                    Toggle("15 minutes before", isOn: $settings.notifyQuarter)
                }

                Section("About") {
                    if let ms = app.lastCompileMs { LabeledContent("Last compile", value: "\(ms) ms") }
                    Text("Compiles on-device with Clang (WebAssembly). Exceptions (try/catch) aren't supported. Programs run slower than on Codeforces, so confirm time limits there.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showLogin) { LoginSheet() }
            .sheet(isPresented: $editTemplate) { TemplateEditor() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .sourceCode, .cPlusPlusSource, .data]) { result in
                if case .success(let url) = result {
                    importMessage = app.importTemplate(from: url) ? "Template imported ✓" : "Couldn't read that file as text."
                }
            }
        }
    }
}

struct TemplateEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(8)
                .navigationTitle("Template")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { app.saveTemplate(text); dismiss() } }
                }
        }
        .onAppear { text = app.loadTemplate() }
    }
}
