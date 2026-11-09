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

    init() {
        theme = d.string(forKey: "theme") ?? "Dark Modern"
        fontSize = d.object(forKey: "fontSize") as? Double ?? 14
        std = d.string(forKey: "std") ?? "c++23"
        checks = d.object(forKey: "checks") as? Bool ?? true
        handle = d.string(forKey: "handle") ?? ""
        notifyDay = d.object(forKey: "notifyDay") as? Bool ?? true
        notifyQuarter = d.object(forKey: "notifyQuarter") as? Bool ?? true
        muted = d.array(forKey: "muted") as? [Int] ?? []
    }

    var isDark: Bool { Self.themes.first { $0.name == theme }?.dark ?? true }
}
