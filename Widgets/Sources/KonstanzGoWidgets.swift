import SwiftUI
import WidgetKit

/// The widget extension: home and lock screen widgets (plan X3) and the ride's Live Activity (X2).
@main
struct KonstanzGoWidgets: WidgetBundle {
    var body: some Widget {
        StopWidget()
        HomeWidget()
        TripsWidget()
        TripLiveActivity()
    }
}
