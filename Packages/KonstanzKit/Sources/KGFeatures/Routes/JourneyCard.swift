import KGCore
import KGDesign
import SwiftUI

/// One connection as a route card: first bus to last, the legs as walking and line chips, a tag
/// ("Schnellste"), and a note on when it leaves or where to change. Used by screen 10 and the map's place sheet.
struct JourneyCard: View {
    let journey: Journey
    let tag: JourneyTag?
    let when: PlanQuery.When
    /// The first card says "Fährt in 4 Min." in green.
    let isFirst: Bool
    let isSelected: Bool
    let now: Date
    let action: () -> Void

    var body: some View {
        // Cards count from the first bus (Design/README); walking is shown as legs only.
        let start = journey.firstRide?.start ?? journey.start
        let end = journey.rides.last?.end ?? journey.end
        KGRouteCard(departure: start, arrival: end, tag: tagLabel, legs: legs, note: note,
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

    private var note: Text {
        guard let first = journey.firstRide else {
            return Text("Zu Fuß · \(journey.walkingMinutes) Min.", bundle: .module)
        }
        if journey.transfers > 0 {
            let at = journey.rides[1].boarding.station.shortName
            return Text("\(journey.transfers)× Umsteigen · ab \(at)", bundle: .module)
        }
        let minutes = max(0, Int(first.start.timeIntervalSince(now) / 60))
        if case .now = when, minutes < 60 {
            return Text("Fährt in \(minutes) Min. ab \(first.boarding.station.shortName)", bundle: .module)
        }
        return Text("Ab \(first.boarding.station.shortName)", bundle: .module)
    }
}
