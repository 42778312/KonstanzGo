import Foundation

/// Something the user saved or searched for. Stored with its name and position, so it still shows
/// correctly if a new timetable renames or drops it.
public enum SavedTarget: Sendable, Hashable, Codable {
    case station(id: Int, name: String, coordinate: Coordinate)
    case place(id: Int, name: String, kind: PlaceKind, coordinate: Coordinate)
    /// A dropped pin or an address without an id.
    case point(name: String, coordinate: Coordinate)

    public var name: String {
        switch self {
        case let .station(_, name, _), let .place(_, name, _, _), let .point(name, _): name
        }
    }

    public var coordinate: Coordinate {
        switch self {
        case let .station(_, _, coordinate), let .place(_, _, _, coordinate), let .point(_, coordinate): coordinate
        }
    }
}

/// A favourite: one of the three fixed slots ("Zuhause", "Arbeit", "Uni") or a saved stop or place.
public struct Favorite: Sendable, Hashable, Identifiable, Codable {
    public enum Slot: String, Sendable, Hashable, Codable, CaseIterable {
        case home, work, uni
    }

    public var id: UUID
    /// nil for an ordinary favourite.
    public var slot: Slot?
    /// Name the user gave it; nil = the target's name.
    public var customName: String?
    public var target: SavedTarget
    /// Position in the list, from 0.
    public var order: Int

    public init(id: UUID = UUID(), slot: Slot? = nil, customName: String? = nil, target: SavedTarget, order: Int) {
        self.id = id
        self.slot = slot
        self.customName = customName
        self.target = target
        self.order = order
    }

    public var displayName: String { customName ?? target.name }
}

/// A past search (screen 18 "Zuletzt").
public struct RecentItem: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID
    public var target: SavedTarget
    public var date: Date

    public init(id: UUID = UUID(), target: SavedTarget, date: Date) {
        self.id = id
        self.target = target
        self.date = date
    }
}

/// A finished journey, counted for the "5 Fahrten diese Woche" widget.
public struct FinishedTrip: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID
    public var date: Date
    public var lineName: String
    public var from: String
    public var to: String

    public init(id: UUID = UUID(), date: Date, lineName: String, from: String, to: String) {
        self.id = id
        self.date = date
        self.lineName = lineName
        self.from = from
        self.to = to
    }
}

/// "Alarm 2 Min. vorher" for one departure.
public struct Alarm: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID
    public var stationID: Int
    public var stationName: String
    public var tripID: Int
    public var lineName: String
    public var headsign: String
    public var platformCode: String?
    public var departure: Date
    public var minutesBefore: Int

    public init(id: UUID = UUID(), stationID: Int, stationName: String, tripID: Int, lineName: String,
                headsign: String, platformCode: String?, departure: Date, minutesBefore: Int) {
        self.id = id
        self.stationID = stationID
        self.stationName = stationName
        self.tripID = tripID
        self.lineName = lineName
        self.headsign = headsign
        self.platformCode = platformCode
        self.departure = departure
        self.minutesBefore = minutesBefore
    }

    /// When the notification goes off.
    public var fireDate: Date { departure.addingTimeInterval(TimeInterval(-minutesBefore * 60)) }
}
