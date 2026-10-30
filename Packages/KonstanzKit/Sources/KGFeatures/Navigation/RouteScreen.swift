import KGCore
import KGDesign
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
            RecentScreen(services: services) { services.router.back() }
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

/// The bar that holds a screen's main button under its scrolling content: the screen's background with a
/// hairline on top, so the list ends above it instead of running under it.
struct BottomBar<Content: View>: View {
    let background: Color
    let content: Content

    init(background: Color = KGColor.card, @ViewBuilder content: () -> Content) {
        self.background = background
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, KGSpace.large)
            .padding(.top, KGSpace.medium)
            .padding(.bottom, KGSpace.compact)
            .frame(maxWidth: .infinity)
            .background(background.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(KGColor.line).frame(height: 1) }
    }
}
