import KGCore
import KGDesign
import SwiftUI

/// One connection as a route card: door to door, the legs as walking and line chips, a tag
/// ("Schnellste"), and a note on when it leaves or where to change. Used by screen 10 and the map's place sheet.
struct JourneyCard: View {
    let journey: Journey
    let tag: JourneyTag?
    let when: PlanQuery.When
    /// The first card says when to leave in green.
    let isFirst: Bool
    let isSelected: Bool
    let now: Date
    /// How late the first bus is known to be, in minutes.
    var delay = 0
    let action: () -> Void

    var body: some View {
        // From leaving home to arriving, so every card compares fairly (Design/README).
        let times = journey.doorToDoor(firstBusDelayMinutes: delay)
        KGRouteCard(departure: times.start, arrival: times.end, tag: tagLabel, legs: legs, note: note,
                    noteIsLive: isFirst && journey.firstRide != nil, isSelected: isSelected, action: action)
            .accessibilityIdentifier("routeCard")
    }

    private var tagLabel: (title: Text, tone: KGTag.Tone)? {
        switch tag {
        case .fastest: (Text("Schnellste", bundle: .module), .line)
        case .leastWalking: (Text("Wenig laufen", bundle: .module), .live)
        case .fewestTransfers: (Text("Wenig umsteigen", bundle: .module), .neutral)
        case nil: nil
        }
    }

    private var legs: [KGLeg] {
        journey.legs.map { leg in
            switch leg {
            case let .walk(walk): .walk(minutes: max(1, Leg.walk(walk).minutes))
            case let .ride(ride): .bus(line: ride.line.name)
            }
        }
    }

    /// When to leave and which bus to reach. The main times count from the door, so this says what the bus does.
    private var note: Text {
        guard let first = journey.firstRide else {
            return Text("Zu Fuß · \(journey.walkingMinutes) Min.", bundle: .module)
        }
        let leave = journey.doorToDoor(firstBusDelayMinutes: delay).start
        let bus = KGStrings.clock(first.start.addingTimeInterval(TimeInterval(delay * 60)))
        let stop = first.boarding.station.shortName
        let walksFirst = journey.start < first.start
        var text: Text
        if case .now = when, leave.timeIntervalSince(now) < 3600 {
            let minutes = max(0, Int(leave.timeIntervalSince(now) / 60))
            if journey.transfers > 0 {
                let at = journey.rides[1].boarding.station.shortName
                text = minutes == 0 ? Text("Jetzt los · \(journey.transfers)× Umsteigen · ab \(at)", bundle: .module)
                    : Text("Los in \(minutes) Min. · \(journey.transfers)× Umsteigen · ab \(at)", bundle: .module)
            } else if !walksFirst {
                text = Text("Fährt in \(minutes) Min. ab \(stop)", bundle: .module)
            } else {
                text = minutes == 0 ? Text("Jetzt los · Bus \(bus) ab \(stop)", bundle: .module)
                    : Text("Los in \(minutes) Min. · Bus \(bus) ab \(stop)", bundle: .module)
            }
        } else if journey.transfers > 0 {
            text = Text("\(journey.transfers)× Umsteigen · ab \(journey.rides[1].boarding.station.shortName)", bundle: .module)
        } else {
            text = Text("Bus \(bus) ab \(stop)", bundle: .module)
        }
        if delay > 0 {
            text = text + Text(verbatim: " · ") + Text("+\(delay) Min.", bundle: .module)
        } else if delay < 0 {
            text = text + Text(verbatim: " · ") + Text("\(-delay) Min. früher", bundle: .module)
        }
        return text
    }
}
