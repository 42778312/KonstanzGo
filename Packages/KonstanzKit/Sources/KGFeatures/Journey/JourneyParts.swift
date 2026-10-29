import KGCore
import KGDesign
import SwiftUI

extension Journey {
    /// The journey as map lines: rides coral along the road, walks dotted (plan M7).
    var mapLines: [MapLine] {
        legs.map { leg in
            switch leg {
            case let .walk(walk):
                MapLine(kind: .walk, points: walk.path.count > 1 ? walk.path : [])
            case let .ride(ride):
                MapLine(kind: .bus, points: ride.path.count > 1 ? ride.path : ride.stops.map(\.platform.coordinate))
            }
        }
        .filter { $0.points.count > 1 }
    }

    var allPoints: [Coordinate] { mapLines.flatMap(\.points) }
}

/// Words for a walking step: "Rechts in die Bahnhofstraße", "Konzilstraße überqueren" (screen 22).
enum WalkWords {
    static func instruction(_ step: WalkStep) -> String {
        let street = step.street
        switch step.maneuver {
        case .depart:
            return street.map { String(localized: "Los über \($0)", bundle: .module) }
                ?? String(localized: "Los geht's", bundle: .module)
        case .straight:
            return street.map { String(localized: "Geradeaus über \($0)", bundle: .module) }
                ?? String(localized: "Geradeaus", bundle: .module)
        case .slightLeft, .left, .sharpLeft:
            let turn = step.maneuver == .left ? String(localized: "Links", bundle: .module)
                : step.maneuver == .slightLeft ? String(localized: "Leicht links", bundle: .module)
                : String(localized: "Scharf links", bundle: .module)
            return street.map { String(localized: "\(turn) in die \($0)", bundle: .module) } ?? turn
        case .slightRight, .right, .sharpRight:
            let turn = step.maneuver == .right ? String(localized: "Rechts", bundle: .module)
                : step.maneuver == .slightRight ? String(localized: "Leicht rechts", bundle: .module)
                : String(localized: "Scharf rechts", bundle: .module)
            return street.map { String(localized: "\(turn) in die \($0)", bundle: .module) } ?? turn
        case .uTurn:
            return String(localized: "Umdrehen", bundle: .module)
        case .stairs:
            return String(localized: "Die Treppe nehmen", bundle: .module)
        case .cross:
            return street.map { String(localized: "\($0) überqueren", bundle: .module) }
                ?? String(localized: "Straße überqueren", bundle: .module)
        case .arrive:
            return String(localized: "Ankommen", bundle: .module)
        }
    }

    static func icon(_ maneuver: Maneuver) -> KGIcon {
        switch maneuver {
        case .straight, .depart, .uTurn, .stairs: .straight
        case .left, .slightLeft, .sharpLeft, .right, .slightRight, .sharpRight: .turnRight
        case .cross: .crossing
        case .arrive: .arrive
        }
    }

    /// Left turns use the right-turn arrow mirrored.
    static func mirrored(_ maneuver: Maneuver) -> Bool {
        [.left, .slightLeft, .sharpLeft].contains(maneuver)
    }

    static func distance(_ metres: Int) -> String {
        Measurement(value: Double(metres), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// The white header bar over a map: back, "Mein Standort → Universität", a line under it (21, 23).
struct RouteHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: KGSpace.xs) {
            Button(action: onBack) {
                KGIconView(.back, size: 22).foregroundStyle(KGColor.ink)
                    .frame(width: KGSize.touch, height: KGSize.touch)
            }
            .buttonStyle(KGPressStyle())
            .accessibilityLabel(Text("Zurück", bundle: .module))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title).kgFont(.body.weighted(KGFont.extraBold)).lineLimit(1)
                Text(verbatim: subtitle).kgFont(.caption.weighted(KGFont.regular)).foregroundStyle(KGColor.ink2)
            }
            .foregroundStyle(KGColor.ink)
            Spacer()
        }
        .padding(.leading, KGSpace.xxs)
        .padding(.trailing, KGSpace.mediumLarge)
        .frame(minHeight: 64)
        .background(KGColor.surface, in: .kgRounded(KGRadius.search))
        .kgShadow(.search, in: .kgRounded(KGRadius.search))
        .padding(.horizontal, KGSpace.screen)
        .padding(.top, 11)
    }
}

/// A map filling the screen with the journey drawn on it, the user, and the buses of its rides moving.
struct JourneyMap: View {
    let services: AppServices
    let journey: Journey
    let bottomInset: CGFloat
    var focus: [Coordinate]?
    /// A tap on the map away from any stop.
    var onTap: (() -> Void)?
    @State private var model = MapModel()
    @State private var buses: [VehiclePosition] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: model)
            #else
            KGColor.mapLand
            #endif
            if let point = model.userPoint {
                KGUserDot(heading: services.location.heading.map { .degrees($0) }).position(point)
            }
            ForEach(buses) { bus in
                if let point = model.pinPoints["bus-\(bus.tripID)"] {
                    KGBusMarker(line: bus.line.name, heading: .degrees(bus.heading)).position(point)
                }
            }
            if let point = model.pinPoints["start"] {
                Circle().fill(KGColor.white).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(KGColor.location, lineWidth: 5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(point)
            }
            if let point = model.pinPoints["end"] {
                RoundedRectangle(cornerRadius: 4).fill(KGColor.ink)
                    .frame(width: 16, height: 16).rotationEffect(.degrees(45))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(KGColor.white, lineWidth: 3)
                        .rotationEffect(.degrees(45)))
                    .position(point)
            }
        }
        .allowsHitTesting(true)
        .ignoresSafeArea()
        .onAppear {
            model.lines = journey.mapLines
            model.insets = MapInsets(top: 110, bottom: bottomInset)
            model.onTapMap = onTap
            model.userLocation = services.location.coordinate
            var ends: [MapPin] = []
            if let first = journey.allPoints.first { ends.append(MapPin(id: "start", coordinate: first)) }
            if let last = journey.legs.last { ends.append(MapPin(id: "end", coordinate: endPoint(last))) }
            model.pins = ends
            model.move(.fitting(focus ?? journey.allPoints, animated: false))
        }
        .onChange(of: services.location.coordinate) { _, point in model.userLocation = point }
        .onChange(of: bottomInset) { _, inset in model.insets.bottom = inset }
        .task { await followBuses() }
    }

    private func endPoint(_ leg: Leg) -> Coordinate {
        switch leg {
        case let .walk(walk): walk.path.last ?? MapRegion.center
        case let .ride(ride): ride.alighting.platform.coordinate
        }
    }

    /// The estimated positions of the journey's buses, once a second (plan M5, S12.1).
    private func followBuses() async {
        while !Task.isCancelled {
            let now = Date.now
            buses = journey.rides.compactMap { ride in
                for day in [ServiceDay(ride.start), ServiceDay(ride.start).adding(days: -1)] {
                    if let position = try? services.transit.tracker.position(ofTrip: ride.tripID, on: day, at: now) {
                        return position
                    }
                }
                return nil
            }
            var pins = model.pins.filter { !$0.id.hasPrefix("bus-") }
            pins += buses.map { MapPin(id: "bus-\($0.tripID)", coordinate: $0.coordinate) }
            model.pins = pins
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
