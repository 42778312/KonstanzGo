import CoreLocation
import UserNotifications

#if os(iOS)
/// The real permission prompts: CoreLocation (when in use) and UserNotifications.
@MainActor
public final class SystemPermissions: NSObject, PermissionAsking, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<Bool, Never>?

    override public init() {
        super.init()
        manager.delegate = self
    }

    public func requestLocation() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .denied, .restricted: return false
        case .notDetermined: break
        @unknown default: return false
        }
        return await withCheckedContinuation { continuation in
            waiting = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    public func requestNotifications() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined, let waiting else { return }
            self.waiting = nil
            waiting.resume(returning: status == .authorizedWhenInUse || status == .authorizedAlways)
        }
    }
}

#endif

/// Answers without asking: previews, snapshots, and UI tests (`-KGPermissions allow|deny`).
@MainActor
public final class FixedPermissions: PermissionAsking {
    let allow: Bool

    public init(allow: Bool) {
        self.allow = allow
    }

    public func requestLocation() async -> Bool { allow }
    public func requestNotifications() async -> Bool { allow }
}
