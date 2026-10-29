import Foundation
import KGCore
import Observation

/// Everything the screens share once the offline data is open: the timetable and planner, the user's
/// saved things, their position, and where they are in the app.
@MainActor
@Observable
public final class AppServices {
    public let data: BundledData
    public let transit: OfflineTransit
    /// Favourites, recent searches, alarms. Nil if the store could not be opened (then nothing is saved).
    public let user: UserStore?
    public let location: LocationModel
    public let router = Router()
    /// Switches home's tab (set by HomeView), so Favoriten and links can open screens on the map's stack.
    public var selectTab: ((HomeTab) -> Void)?
    /// Set to open the map's search sheet (links and Favoriten); the map clears it.
    public var wantsSearch = false
    /// Bumped whenever the user store changes, so lists re-read it.
    public private(set) var userVersion = 0

    public init(data: BundledData, transit: OfflineTransit, location: LocationModel) {
        self.data = data
        self.transit = transit
        self.location = location
        user = try? UserStore.shared()
    }

    /// Opens a saved or searched thing on the map tab: stop → 09, place → 15, point → 16.
    public func openOnMap(_ target: SavedTarget) {
        selectTab?(.map)
        switch target {
        case let .station(id, _, _): router.open(.stop(id))
        case let .place(id, name, kind, coordinate):
            if kind == .street || kind == .address {
                router.open(.pin(coordinate))
            } else {
                router.open(.place(transit.placeSearch.place(id: id)
                    ?? Place(id: id, name: name, kind: kind, category: "", area: "", coordinate: coordinate)))
            }
        case let .point(_, coordinate): router.open(.pin(coordinate))
        }
    }

    /// Links from widgets, notifications and Siri: konstanzgo://stop/<id>, konstanzgo://route/home|work|uni,
    /// konstanzgo://journey (plan X3.8).
    public func open(url: URL) {
        guard url.scheme == "konstanzgo" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        selectTab?(.map)
        switch url.host {
        case "stop":
            if let id = parts.first.flatMap(Int.init) { router.home(); router.open(.stop(id)) }
        case "route":
            let slot = parts.first.flatMap(Favorite.Slot.init(rawValue:)) ?? .home
            guard let favorite = try? user?.slot(slot) else { router.home(); wantsSearch = true; return }
            let start = here ?? Endpoint(name: String(localized: "Altstadt", bundle: .module), coordinate: MapRegion.center)
            router.home()
            router.open(.routes(PlanQuery(from: start, to: Endpoint(name: favorite.displayName,
                                                                    coordinate: favorite.target.coordinate))))
        default:
            break
        }
    }

    /// "Mein Standort" for planning, or nil without a usable position.
    public var here: Endpoint? {
        guard let point = location.coordinate, MapRegion.contains(point) else { return nil }
        return Endpoint(name: String(localized: "Mein Standort", bundle: .module), coordinate: point)
    }

    /// Where distances and "nearby" are measured from: the user, or the old town.
    public var anchor: Coordinate {
        here?.coordinate ?? MapRegion.center
    }

    /// Runs a change on the user store and tells the lists.
    public func updateUser(_ change: (UserStore) throws -> Void) {
        guard let user else { return }
        try? change(user)
        userVersion += 1
    }

    public func isFavorite(_ target: SavedTarget) -> Bool {
        _ = userVersion
        return (try? user?.isFavorite(target)) ?? false
    }

    /// Adds or removes a favourite; returns whether it is a favourite now.
    @discardableResult
    public func toggleFavorite(_ target: SavedTarget) -> Bool {
        if let existing = (try? user?.favorites())?.first(where: { $0.target == target }) {
            updateUser { try $0.removeFavorite(id: existing.id) }
            return false
        }
        updateUser { _ = try $0.addFavorite(target) }
        return true
    }
}

/// Home's tabs.
public enum HomeTab: Hashable, Sendable { case map, saved, more }

/// The screens of the map tab's stack (plan M3). The tab bar hides while one is open.
public enum Route: Hashable {
    case search
    case recent
    case stop(Int)
    case place(Place)
    case pin(Coordinate)
    /// Screen 17: a departure's trip, seen from the stop it was picked at.
    case trip(tripID: Int, day: ServiceDay, fromStation: Int)
    case routes(PlanQuery)
    case routeMap(Journey, PlanQuery)
    case walk(Journey)
    case journey(Journey)
}

/// What to plan: from, to, when, how (screens 10, 19).
public struct PlanQuery: Hashable, Sendable {
    public enum When: Hashable, Sendable {
        case now
        case departAt(Date)
        case arriveBy(Date)
    }

    public var from: Endpoint
    public var to: Endpoint
    public var when: When = .now
    public var preference: RoutePreference = .fastest

    public init(from: Endpoint, to: Endpoint, when: When = .now, preference: RoutePreference = .fastest) {
        self.from = from
        self.to = to
        self.when = when
        self.preference = preference
    }

    public func request(now: Date = .now) -> PlanRequest {
        switch when {
        case .now: PlanRequest(from: from, to: to, time: now, preference: preference)
        case let .departAt(date): PlanRequest(from: from, to: to, time: date, preference: preference)
        case let .arriveBy(date): PlanRequest(from: from, to: to, time: date, arriveBy: true, preference: preference)
        }
    }

    public var swapped: PlanQuery {
        var copy = self
        copy.from = to
        copy.to = from
        return copy
    }
}

@MainActor
@Observable
public final class Router {
    public var path: [Route] = []

    public func open(_ route: Route) {
        path.append(route)
    }

    public func back() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Bumped by `home()`, so the map closes its stop or place sheet too (ending a trip, links).
    public private(set) var homeCount = 0

    public func home() {
        path.removeAll()
        homeCount += 1
    }
}
