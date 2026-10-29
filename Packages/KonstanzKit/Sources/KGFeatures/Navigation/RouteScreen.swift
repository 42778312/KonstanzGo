import KGCore
import SwiftUI

/// Builds the screen for a route of the map tab's stack.
struct RouteScreen: View {
    let route: Route
    let services: AppServices

    var body: some View {
        switch route {
        case .search:
            SearchScreen(services: services)
        case .recent:
            RecentScreen(services: services)
        case let .stop(id):
            StopScreen(services: services, stationID: id)
        case let .place(place):
            PlaceScreen(services: services, place: place)
        case let .pin(point):
            PinScreen(services: services, point: point)
        case let .trip(tripID, day, fromStation):
            TripScreen(services: services, tripID: tripID, day: day, fromStation: fromStation)
        case let .routes(query):
            RoutesScreen(services: services, query: query)
        case let .routeMap(journey, query):
            RouteMapScreen(services: services, journey: journey, query: query)
        case let .walk(journey):
            WalkScreen(services: services, journey: journey)
        case let .journey(journey):
            JourneyScreen(services: services, journey: journey)
        }
    }
}

extension View {
    /// Our screens draw their own headers (the design has no system navigation bar).
    func kgHideNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
