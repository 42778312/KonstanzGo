import KGCore
import KGDesign
import SwiftUI

/// Home: the three tabs under the floating tab bar (plan B18). Karte is screen 07; Favoriten (12) and
/// Mehr (13) come in Milestone 5 and say so for now.
public struct HomeView: View {
    typealias Tab = HomeTab

    let loader: TransitLoader
    let onReplayOnboarding: () -> Void
    @State private var tab = Tab.map
    @State private var services: AppServices?
    @State private var notifications: AlarmNotificationRouter?
    @State private var location = LocationModel()
    /// A link that arrived before the offline data was open (the app was started by it).
    @State private var pendingURL: URL?

    /// The tab bar sits this far from the screen's bottom edge, down by the home indicator.
    static let barBottom: CGFloat = 14
    /// The tab bar's height above the safe area, for content to keep clear of.
    static let barSpace: CGFloat = KGSize.tabItem.height + 2 * KGSize.tabBarPadding

    public init(loader: TransitLoader, onReplayOnboarding: @escaping () -> Void) {
        self.loader = loader
        self.onReplayOnboarding = onReplayOnboarding
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                mapTab.opacity(tab == .map ? 1 : 0).allowsHitTesting(tab == .map)
                if tab == .saved, let services {
                    SavedScreen(services: services)
                }
                if tab == .more, let services {
                    MoreScreen(services: services, onReplayOnboarding: onReplayOnboarding)
                }
            }
            if services?.router.path.isEmpty ?? true {
                tabBar.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(KGMotion.slide, value: services?.router.path.isEmpty ?? true)
        .onOpenURL { open($0) }
        .onReceive(NotificationCenter.default.publisher(for: .kgDeepLink)) { note in
            if let url = note.object as? URL { open(url) }
        }
        .onChange(of: loader.transit != nil, initial: true) { _, ready in
            if ready, services == nil, let transit = loader.transit, let data = loader.data {
                let new = AppServices(data: data, transit: transit, location: location)
                new.selectTab = { tab = $0 }
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

    private var tabBar: some View {
            KGFloatingTabBar(selection: $tab, tabs: [
                KGTab(id: .map, title: Text("Karte", bundle: .module), icon: .map),
                KGTab(id: .saved, title: Text("Favoriten", bundle: .module), icon: .star),
                KGTab(id: .more, title: Text("Mehr", bundle: .module), icon: .more),
            ])
            .padding(.bottom, Self.barBottom)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder private var mapTab: some View {
        if let services {
            MapTab(services: services, router: services.router)
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

/// A tab that is not built yet, with Seeri saying so (honest data, plan rule 7).
private struct ComingSoon<Actions: View>: View {
    let title: Text
    let message: Text
    let actions: Actions

    init(title: Text, message: Text, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.kgFont(.display.sized(34)).foregroundStyle(KGColor.ink)
                .padding(.horizontal, KGSpace.large)
                .padding(.top, KGSpace.small)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            KGEmptyState(.curious, title: Text("Kommt bald", bundle: .module), message: message) { actions }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KGColor.card.ignoresSafeArea())
    }
}

/// The map tab: the map, and the screens opened from it on a stack (plan M3).
private struct MapTab: View {
    let services: AppServices
    @Bindable var router: Router

    var body: some View {
        NavigationStack(path: $router.path) {
            MapScreen(services: services, bottomBar: HomeView.barSpace + HomeView.barBottom)
                .kgHideNavigationBar()
                .navigationDestination(for: Route.self) { route in
                    RouteScreen(route: route, services: services)
                        .kgHideNavigationBar()
                }
        }
    }
}
