import Foundation

/// What a place is. Raw values are the words used in the data files (`place.kind` in timetable.db,
/// the group column in places.tsvz).
public enum PlaceKind: String, Sendable, Hashable, Codable, CaseIterable {
    // timetable.db `place.kind`
    case venue = "Venue", station = "Station", harbour = "Harbour", library = "Library", square = "Square"
    case university = "University", street = "Street", district = "District", town = "Town"
    // only in places.tsvz
    case address = "Address", shop = "Shop", culture = "Culture", service = "Service", food = "Food"
    case health = "Health", leisure = "Leisure", park = "Park", hotel = "Hotel", education = "Education"
    case cafe = "Cafe", transport = "Transport"
}

/// Somewhere you can go that is not a bus stop: "Konzil", "Universitätsstraße", "Seestraße 21".
public struct Place: Sendable, Hashable, Identifiable, Codable {
    public var id: Int
    public var name: String
    public var kind: PlaceKind
    /// What it is in words ("Veranstaltungsort", "Restaurant"); empty when the kind says enough.
    public var category: String
    /// District and town, "Altstadt, Konstanz".
    public var area: String
    /// Street address when known, "Hafenstraße 2".
    public var address: String?
    public var coordinate: Coordinate

    public init(id: Int, name: String, kind: PlaceKind, category: String, area: String,
                address: String? = nil, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.area = area
        self.address = address
        self.coordinate = coordinate
    }
}

/// One search answer.
public struct SearchResult: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        case station(Station, lines: [Line])
        case place(Place)
    }

    public var target: Target
    /// The part of `name` that matched what was typed, as a range of characters (for the bold highlight).
    public var match: Range<Int>?
    /// Higher is better; results are sorted by it.
    public var score: Double

    public init(target: Target, match: Range<Int>?, score: Double) {
        self.target = target
        self.match = match
        self.score = score
    }

    public var name: String {
        switch target {
        case let .station(station, _): station.name
        case let .place(place): place.name
        }
    }

    public var coordinate: Coordinate {
        switch target {
        case let .station(station, _): station.coordinate
        case let .place(place): place.coordinate
        }
    }

    public var id: String {
        switch target {
        case let .station(station, _): "s\(station.id)"
        case let .place(place): "p\(place.id)"
        }
    }
}
