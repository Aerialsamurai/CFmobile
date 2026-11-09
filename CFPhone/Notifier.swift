import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Re-creates all contest reminders. Called every time the contest list refreshes.
    static func schedule(contests: [CFContest], settings: Settings) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("contest-") })

        let now = Date()
        var count = 0
        for c in contests where c.phase == "BEFORE" && !settings.muted.contains(c.id) {
            guard let start = c.start, start > now else { continue }
            var slots: [(String, TimeInterval, String)] = []
            if settings.notifyDay { slots.append(("24h", 24 * 3600, "starts in 24 hours")) }
            if settings.notifyQuarter { slots.append(("15m", 15 * 60, "starts in 15 minutes")) }
            for (tag, before, text) in slots {
                let fire = start.addingTimeInterval(-before)
                guard fire > now, count < 40 else { continue }
                let content = UNMutableNotificationContent()
                content.title = c.name
                content.body = "Contest \(text)."
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "contest-\(c.id)-\(tag)", content: content, trigger: trigger))
                count += 1
            }
        }
    }
}
