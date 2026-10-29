import Foundation
import KGCore

/// What the widgets read: the timetable from the app's bundle (an extension may read its containing app),
/// favourites and finished trips from the App Group (plan X3.6). Opened once per extension process.
enum WidgetData {
    static let timetable: TimetableStore? = {
        guard let data = BundledData.forCurrentProcess() else { return nil }
        return try? TimetableStore(url: data.timetable)
    }()

    static let user: UserStore? = try? UserStore.shared()

    /// The stop a widget shows when none is chosen: the first saved stop, else Bahnhof.
    static var defaultStation: Station? {
        guard let timetable else { return nil }
        if let favorite = (try? user?.favorites())?.first(where: {
            if case .station = $0.target { return true } else { return false }
        }), case let .station(id, _, _) = favorite.target, let station = timetable.station(id: id) {
            return station
        }
        return timetable.stations.first { $0.shortName == "Bahnhof" } ?? timetable.stations.first
    }
}
