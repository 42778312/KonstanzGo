import CoreLocation
import KGCore
import Observation

/// The user's position for the map and "In deiner Nähe" (plan M6). Updates run only while a screen asks for
/// them (`start` / `stop`), so nothing tracks in the background (plan T10).
@MainActor
@Observable
public final class LocationModel: NSObject, CLLocationManagerDelegate {
    public enum Access: Sendable { case unknown, allowed, denied }

    public private(set) var coordinate: Coordinate?
    public private(set) var heading: Double?
    public private(set) var access: Access = .unknown

    private let manager = CLLocationManager()

    override public init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
        access = Self.access(manager.authorizationStatus)
    }

    public func start() {
        guard access == .allowed else { return }
        manager.startUpdatingLocation()
        #if os(iOS)
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        #endif
    }

    public func stop() {
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }

    /// "Standort erlauben": the system prompt when it can still be shown.
    public func requestAccess() {
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        #endif
    }

    private static func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .unknown
        case .denied, .restricted: return .denied
        default: return .allowed
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.access = Self.access(status)
            if self.access == .allowed { self.start() }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let point = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in self.coordinate = point }
    }

    #if os(iOS)
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }
    #endif

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
