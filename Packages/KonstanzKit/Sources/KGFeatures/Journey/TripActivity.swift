import Foundation
import KGCore
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Starts, updates and ends the ride's Live Activity (plan X2). The minutes and progress count down on
/// their own on the lock screen (timer texts), so updates are only needed when the stop changes.
@MainActor
enum TripActivity {
    /// Starts it for the journey's current or next ride; false when Live Activities are off.
    @discardableResult
    static func start(journey: Journey, now: Date) -> Bool {
        #if canImport(ActivityKit) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let ride = journey.rides.first(where: { $0.end > now }) ?? journey.rides.last else { return false }
        end()
        let attributes = TripActivityAttributes(line: ride.line.name, target: ride.alighting.station.shortName,
                                                boarding: ride.boarding.station.shortName)
        let content = ActivityContent(state: state(ride: ride, now: now),
                                      staleDate: ride.end.addingTimeInterval(2 * 3600))
        return (try? Activity.request(attributes: attributes, content: content)) != nil
        #else
        return false
        #endif
    }

    static func update(journey: Journey, now: Date) {
        #if canImport(ActivityKit) && os(iOS)
        guard let ride = journey.rides.first(where: { $0.end > now }) ?? journey.rides.last else { return }
        let new = state(ride: ride, now: now)
        let content = ActivityContent(state: new, staleDate: ride.end.addingTimeInterval(2 * 3600))
        Task {
            // Looked up inside the task, so no activity crosses into it.
            for activity in Activity<TripActivityAttributes>.activities where activity.content.state != new {
                await activity.update(content)
            }
        }
        #endif
    }

    /// Ends it at arrival or "Fahrt beenden" (X2.6).
    static func end() {
        #if canImport(ActivityKit) && os(iOS)
        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func state(ride: RideLeg, now: Date) -> TripActivityAttributes.ContentState {
        let progress = TripProgress(ride: ride, at: now)
        return TripActivityAttributes.ContentState(currentStop: ride.stops[progress.currentStop].station.shortName,
                                                   stopsLeft: progress.stopsLeft, arrival: ride.end, start: ride.start)
    }
    #endif
}
