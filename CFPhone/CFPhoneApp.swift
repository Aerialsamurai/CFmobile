import SwiftUI

@main
struct CFPhoneApp: App {
    @StateObject private var settings: Settings
    @StateObject private var app: AppState

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _app = StateObject(wrappedValue: AppState(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(settings)
                .preferredColorScheme(settings.isDark ? .dark : .light)
                .task { await app.boot() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let err = app.bootError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(err).multilineTextAlignment(.center)
                }.padding()
            } else if app.editor == nil {
                ProgressView("Starting…")
            } else {
                TabView(selection: $app.selectedTab) {
                    EditorTab().tabItem { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }.tag(0)
                    TestsTab().tabItem { Label("Tests", systemImage: "checklist") }.tag(1)
                    SubmissionsTab().tabItem { Label("Submissions", systemImage: "paperplane") }.tag(2)
                    ContestsTab().tabItem { Label("Contests", systemImage: "trophy") }.tag(3)
                    ProfileTab().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
                }
                // The compiler lives in this invisible 1×1 web view so it keeps running on every tab.
                .overlay(alignment: .topLeading) {
                    if let e = app.engine {
                        EngineWebView(host: e).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
                    }
                }
            }
        }
        .onChange(of: settings.theme) { _ in app.applyAppearance() }
        .onChange(of: settings.fontSize) { _ in app.applyAppearance() }
        .onChange(of: settings.readerFontSize) { _ in app.applyAppearance() }
        .onChange(of: settings.readerHighlight) { _ in app.applyAppearance() }
        .onChange(of: settings.readerSentences) { _ in app.applyAppearance() }
        .onChange(of: settings.readerConstraints) { _ in app.applyAppearance() }
        .onChange(of: settings.readerSerif) { _ in app.applyAppearance() }
        .onChange(of: scenePhase) { phase in
            // came back from the browser after submitting: refresh and jump to the verdict
            if phase == .active && app.pendingSubmit {
                app.pendingSubmit = false
                app.submissionsNeedRefresh += 1
                app.selectedTab = 2
            }
        }
        .onChange(of: settings.hideTags) { _ in app.renderReader() }
        .onChange(of: settings.hideRating) { _ in app.renderReader() }
        .onChange(of: settings.revealWhenSolved) { _ in app.renderReader() }
        .onChange(of: settings.indentSize) { _ in app.applyAppearance() }
        .onChange(of: settings.autoClose) { _ in app.applyAppearance() }
        .onChange(of: settings.snippetRow) { _ in app.applyAppearance() }
        .onChange(of: settings.haptics) { _ in app.applyAppearance() }
    }
}
