import KGCore
import KGDesign
import SwiftUI

/// Home: the map and the screens opened from it. There is no tab bar (changed after testing on a phone):
/// Favoriten and Mehr open from Seeri in the map's search bar.
public struct HomeView: View {

    let loader: TransitLoader
    let onReplayOnboarding: () -> Void
    @State private var services: AppServices?
    @State private var notifications: AlarmNotificationRouter?
    @State private var location = LocationModel()
    /// A link that arrived before the offline data was open (the app was started by it).
    @State private var pendingURL: URL?

    /// How far the map's search bar sits above the screen's bottom edge.
    static let searchBottom: CGFloat = 26

    public init(loader: TransitLoader, onReplayOnboarding: @escaping () -> Void) {
        self.loader = loader
        self.onReplayOnboarding = onReplayOnboarding
    }

    public var body: some View {
        mapTab
        .onOpenURL { open($0) }
        .onReceive(NotificationCenter.default.publisher(for: .kgDeepLink)) { note in
            if let url = note.object as? URL { open(url) }
        }
        .onChange(of: loader.transit != nil, initial: true) { _, ready in
            if ready, services == nil, let transit = loader.transit, let data = loader.data {
                let new = AppServices(data: data, transit: transit, location: location)
                // Screens in the menu that open something on the map close the menu first.
                new.selectTab = { _ in new.showsMenu = false }
                services = new
                notifications = AlarmNotificationRouter(services: new)
                if let url = pendingURL {
                    pendingURL = nil
                    new.open(url: url)
                }
                Task { await AlarmScheduler.refresh(store: new.user) }
            }
        }
    }

    private func open(_ url: URL) {
        if let services { services.open(url: url) } else { pendingURL = url }
    }

    @ViewBuilder private var mapTab: some View {
        if let services {
            MapTab(services: services, router: services.router, onReplayOnboarding: onReplayOnboarding)
        } else if loader.failed {
            KGEmptyState(.sleepy, title: Text("Offline-Daten fehlen", bundle: .module),
                         message: Text("Bitte installiere die App neu.", bundle: .module))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KGColor.surface)
        } else {
            KGColor.mapLand.ignoresSafeArea()
                .overlay { ProgressView() }
        }
    }
}

extension Notification.Name {
    /// Posted by Siri and Shortcuts intents in the app with a konstanzgo:// link.
    public static let kgDeepLink = Notification.Name("kgDeepLink")
}

/// The map tab: the map, and the screens opened from it on a stack (plan M3).
private struct MapTab: View {
    let services: AppServices
    @Bindable var router: Router
    let onReplayOnboarding: () -> Void

    var body: some View {
        NavigationStack(path: $router.path) {
            MapScreen(services: services, bottomBar: HomeView.searchBottom, onReplayOnboarding: onReplayOnboarding)
                .kgHideNavigationBar()
                .navigationDestination(for: Route.self) { route in
                    RouteScreen(route: route, services: services)
                        .kgHideNavigationBar()
                }
        }
    }
}
