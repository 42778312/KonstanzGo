import Foundation
import KGCore
import UserNotifications

/// "Noch 2 Halte" and "Nächster Halt: aussteigen" as local notifications, so they come with the phone locked. They
/// go by the delays known when last updated; the app updates them while it's open. They never ask for permission:
/// that happens in onboarding and when setting an alarm.
enum GetOffAlerts {
    private static let prefix = "get-off-"
    static let enabledKey = "alerts.getOff"

    static func update(journey: Journey, live: LiveState, now: Date = .now) async {
        await clear()
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        for (index, moment) in journey.getOffMoments(live: live, now: now).enumerated() {
            let content = UNMutableNotificationContent()
            switch moment.kind {
            case .twoStopsLeft:
                content.title = String(localized: "Noch 2 Halte bis \(moment.stop)", bundle: .module)
            case .nextStop:
                content.title = String(localized: "Nächster Halt: \(moment.stop)", bundle: .module)
                content.body = String(localized: "Jetzt aussteigen vorbereiten", bundle: .module)
                content.sound = .default
            }
            #if os(iOS)
            content.interruptionLevel = .timeSensitive
            #endif
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, moment.date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + String(index), content: content, trigger: trigger))
        }
    }

    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
