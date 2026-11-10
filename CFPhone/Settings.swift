import Foundation
import SwiftUI

final class Settings: ObservableObject {
    static let themes: [(name: String, dark: Bool)] = [
        ("Dark Modern", true), ("Dark+", true), ("Light Modern", false), ("One Dark", true),
        ("Dracula", true), ("Monokai", true), ("GitHub Dark", true),
    ]
    static let standards = ["c++23", "c++20", "c++17", "c++14"]

    private let d = UserDefaults.standard

    @Published var theme: String { didSet { d.set(theme, forKey: "theme") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var std: String { didSet { d.set(std, forKey: "std") } }
    @Published var checks: Bool { didSet { d.set(checks, forKey: "checks") } }
    @Published var handle: String { didSet { d.set(handle, forKey: "handle") } }
    @Published var notifyDay: Bool { didSet { d.set(notifyDay, forKey: "notifyDay") } }
    @Published var notifyQuarter: Bool { didSet { d.set(notifyQuarter, forKey: "notifyQuarter") } }
    @Published var muted: [Int] { didSet { d.set(muted, forKey: "muted") } }
    @Published var indentSize: Int { didSet { d.set(indentSize, forKey: "indentSize") } }
    @Published var autoClose: Bool { didSet { d.set(autoClose, forKey: "autoClose") } }
    @Published var snippetRow: Bool { didSet { d.set(snippetRow, forKey: "snippetRow") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var readerFontSize: Double { didSet { d.set(readerFontSize, forKey: "readerFontSize") } }
    @Published var autoSplit: Bool { didSet { d.set(autoSplit, forKey: "autoSplit") } }
    @Published var supportPromptDone: Bool { didSet { d.set(supportPromptDone, forKey: "supportPromptDone") } }
    // problem reader aids
    @Published var readerHighlight: Bool { didSet { d.set(readerHighlight, forKey: "readerHighlight") } }
    @Published var readerSentences: Bool { didSet { d.set(readerSentences, forKey: "readerSentences") } }
    @Published var readerConstraints: Bool { didSet { d.set(readerConstraints, forKey: "readerConstraints") } }
    @Published var readerSerif: Bool { didSet { d.set(readerSerif, forKey: "readerSerif") } }
    // spoilers
    @Published var hideTags: Bool { didSet { d.set(hideTags, forKey: "hideTags") } }
    @Published var hideRating: Bool { didSet { d.set(hideRating, forKey: "hideRating") } }
    @Published var revealWhenSolved: Bool { didSet { d.set(revealWhenSolved, forKey: "revealWhenSolved") } }
    // where Codeforces pages open: true = your default browser (Safari, Brave…), false = the in-app browser
    @Published var useDefaultBrowser: Bool { didSet { d.set(useDefaultBrowser, forKey: "useDefaultBrowser") } }
    @Published var registeredLocal: [Int] { didSet { d.set(registeredLocal, forKey: "registeredLocal") } }

    init() {
        theme = d.string(forKey: "theme") ?? "Dark Modern"
        fontSize = d.object(forKey: "fontSize") as? Double ?? 14
        std = d.string(forKey: "std") ?? "c++23"
        checks = d.object(forKey: "checks") as? Bool ?? true
        handle = d.string(forKey: "handle") ?? ""
        notifyDay = d.object(forKey: "notifyDay") as? Bool ?? true
        notifyQuarter = d.object(forKey: "notifyQuarter") as? Bool ?? true
        muted = d.array(forKey: "muted") as? [Int] ?? []
        indentSize = d.object(forKey: "indentSize") as? Int ?? 4
        autoClose = d.object(forKey: "autoClose") as? Bool ?? true
        snippetRow = d.object(forKey: "snippetRow") as? Bool ?? true
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        readerFontSize = d.object(forKey: "readerFontSize") as? Double ?? 17
        autoSplit = d.object(forKey: "autoSplit") as? Bool ?? true
        supportPromptDone = d.object(forKey: "supportPromptDone") as? Bool ?? false
        readerHighlight = d.object(forKey: "readerHighlight") as? Bool ?? true
        readerSentences = d.object(forKey: "readerSentences") as? Bool ?? true
        readerConstraints = d.object(forKey: "readerConstraints") as? Bool ?? true
        readerSerif = d.object(forKey: "readerSerif") as? Bool ?? false
        hideTags = d.object(forKey: "hideTags") as? Bool ?? false
        hideRating = d.object(forKey: "hideRating") as? Bool ?? false
        revealWhenSolved = d.object(forKey: "revealWhenSolved") as? Bool ?? true
        useDefaultBrowser = d.object(forKey: "useDefaultBrowser") as? Bool ?? true
        registeredLocal = d.array(forKey: "registeredLocal") as? [Int] ?? []
    }

    var isDark: Bool { Self.themes.first { $0.name == theme }?.dark ?? true }
}
