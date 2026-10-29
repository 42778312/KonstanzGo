#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The Live Activity of a bus ride (plan X2, screen 14): which line goes where, and the ride's stops. The
/// app and the widget extension both use this type.
public struct TripActivityAttributes: ActivityAttributes {
    /// What changes during the ride.
    public struct ContentState: Codable, Hashable, Sendable {
        /// The stop the bus is at or has just passed.
        public var currentStop: String
        public var stopsLeft: Int
        public var arrival: Date
        /// When the ride started; with `arrival` this drives the progress bar on its own (X2.4).
        public var start: Date

        public init(currentStop: String, stopsLeft: Int, arrival: Date, start: Date) {
            self.currentStop = currentStop
            self.stopsLeft = stopsLeft
            self.arrival = arrival
            self.start = start
        }
    }

    public var line: String
    /// Where the user gets off ("Universität").
    public var target: String
    /// Where they got on ("Sternenplatz").
    public var boarding: String

    public init(line: String, target: String, boarding: String) {
        self.line = line
        self.target = target
        self.boarding = boarding
    }
}
#endif
