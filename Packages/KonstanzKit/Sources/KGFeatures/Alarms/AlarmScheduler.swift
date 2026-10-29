import Foundation
import KGCore
import UserNotifications

/// Departure alarms as local notifications (plan X1): "Dein Bus 9A kommt in 2 Min." at departure minus the
/// chosen minutes, time-sensitive, with "Route" and "Erledigt" actions. Past alarms are removed when the app
/// opens, and only the next ones are scheduled (iOS keeps at most 64).
enum AlarmScheduler {
    static let category = "departure-alarm"
    static let routeAction = "route"
    static let doneAction = "done"
    /// iOS's limit is 64; leave room for other notifications.
    static let maxScheduled = 60

    static func registerCategory() {
        let route = UNNotificationAction(identifier: routeAction,
                                         title: String(localized: "Route", bundle: .module), options: [.foreground])
        let done = UNNotificationAction(identifier: doneAction,
                                        title: String(localized: "Erledigt", bundle: .module), options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [route, done], intentIdentifiers: []),
        ])
    }

    /// The notification's words, also used by tests.
    static func content(for alarm: Alarm) -> (title: String, body: String) {
        let title = String(localized: "Dein Bus \(alarm.lineName) kommt in \(alarm.minutesBefore) Min.", bundle: .module)
        var body = alarm.stationName
        if let platform = alarm.platformCode { body += ", " + String(localized: "Steig \(platform)", bundle: .module) }
        body += " · " + String(localized: "nach \(alarm.headsign)", bundle: .module)
        return (title, body)
    }

    /// Asks for permission if needed, then schedules; false when notifications are off or the time has passed.
    static func schedule(_ alarm: Alarm, now: Date = .now) async -> Bool {
        let fire = alarm.departure.addingTimeInterval(TimeInterval(-alarm.minutesBefore * 60))
        guard fire > now else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let words = content(for: alarm)
        let content = UNMutableNotificationContent()
        content.title = words.title
        content.body = words.body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["stationID": alarm.stationID, "tripID": alarm.tripID]
        #if os(iOS)
        content.interruptionLevel = .timeSensitive
        #endif
        var parts = Calendar.konstanz.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        parts.timeZone = Calendar.konstanz.timeZone
        let request = UNNotificationRequest(identifier: alarm.id.uuidString, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        return (try? await center.add(request)) != nil
    }

    static func cancel(_ alarm: Alarm) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [alarm.id.uuidString])
    }

    /// On launch: drop past alarms and keep the next ones scheduled (X1.3, X1.4).
    static func refresh(store: UserStore?, now: Date = .now) async {
        guard let store else { return }
        try? store.removePastAlarms(before: now)
        let upcoming = ((try? store.upcomingAlarms(after: now)) ?? []).prefix(maxScheduled)
        let pending = Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
        for alarm in upcoming where !pending.contains(alarm.id.uuidString) {
            _ = await schedule(alarm, now: now)
        }
    }
}

/// Opens the stop when an alarm or its "Route" action is tapped; "Erledigt" just closes it (X1.2).
@MainActor
final class AlarmNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    weak var services: AppServices?

    init(services: AppServices) {
        self.services = services
        super.init()
        AlarmScheduler.registerCategory()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let stationID = response.notification.request.content.userInfo["stationID"] as? Int
        guard action != AlarmScheduler.doneAction, let stationID,
              let url = URL(string: "konstanzgo://stop/\(stationID)") else { return }
        await MainActor.run { services?.open(url: url) }
    }

    /// Alarms also show while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
