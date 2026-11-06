import Foundation
import GRDB

/// What the user keeps on this phone: favourites, recent searches, finished trips and departure alarms.
/// A small SQLite database in the App Group folder, so the widgets can read it too. Nothing leaves the phone.
public final class UserStore: Sendable {
    public static let appGroup = "group.de.konstanzgo.app"
    /// Recent searches kept (oldest dropped first).
    public static let recentLimit = 50

    private let database: DatabaseQueue

    /// The shared database in the App Group folder, or Application Support when there is no group
    /// (unit tests, previews).
    public static func shared() throws -> UserStore {
        try UserStore(url: sharedURL())
    }

    private static func sharedURL() throws -> URL {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "user.sqlite")
    }

    /// For the app, not the widgets: the shared database, or a new one when the old file is damaged. The damaged
    /// file is kept beside it, never deleted. Any other failure (a busy file, a full disk) throws, because the
    /// saved things may still be fine.
    public static func sharedRecovering() throws -> (store: UserStore, recovered: Bool) {
        try openRecovering(url: sharedURL())
    }

    static func openRecovering(url: URL, now: Date = .now) throws -> (store: UserStore, recovered: Bool) {
        do {
            return (try UserStore(url: url), false)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
            let stamp = Int(now.timeIntervalSince1970)
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(filePath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                try FileManager.default.moveItem(at: file, to: URL(filePath: url.path + ".damaged-\(stamp)" + suffix))
            }
            return (try UserStore(url: url), true)
        }
    }

    /// iOS kills an app that keeps a shared file locked while suspended (`0xDEAD10CC`), so the database stops
    /// taking new work when the app goes to the background, and starts again when it returns.
    public static func suspend() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    public static func resume() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }

    /// A store at `url`, or in memory when nil (tests, previews).
    public init(url: URL? = nil) throws {
        var configuration = Configuration()
        configuration.observesSuspensionNotifications = true
        database = try url.map { try DatabaseQueue(path: $0.path, configuration: configuration) }
            ?? DatabaseQueue(configuration: configuration)
        try Self.migrator.migrate(database)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "favorite") { table in
                table.primaryKey("id", .blob)
                table.column("slot", .text).unique()
                table.column("customName", .text)
                table.column("target", .text).notNull()
                table.column("order", .integer).notNull()
            }
            try db.create(table: "recent") { table in
                table.primaryKey("id", .blob)
                table.column("target", .text).notNull()
                table.column("date", .datetime).notNull().indexed()
            }
            try db.create(table: "finishedTrip") { table in
                table.primaryKey("id", .blob)
                table.column("date", .datetime).notNull().indexed()
                table.column("lineName", .text).notNull()
                table.column("from", .text).notNull()
                table.column("to", .text).notNull()
            }
            try db.create(table: "alarm") { table in
                table.primaryKey("id", .blob)
                table.column("stationID", .integer).notNull()
                table.column("stationName", .text).notNull()
                table.column("tripID", .integer).notNull()
                table.column("lineName", .text).notNull()
                table.column("headsign", .text).notNull()
                table.column("platformCode", .text)
                table.column("departure", .datetime).notNull().indexed()
                table.column("minutesBefore", .integer).notNull()
            }
        }
        return migrator
    }

    // MARK: Favourites

    /// Favourites in the user's order; the three slots (Zuhause, Arbeit, Uni) included when set.
    public func favorites() throws -> [Favorite] {
        try database.read { try Favorite.order(Column("order")).fetchAll($0) }
    }

    /// Sets (or replaces) Zuhause, Arbeit or Uni.
    public func setSlot(_ slot: Favorite.Slot, to target: SavedTarget) throws {
        try database.write { db in
            if var existing = try Favorite.filter(Column("slot") == slot.rawValue).fetchOne(db) {
                existing.target = target
                try existing.update(db)
            } else {
                try Favorite(slot: slot, target: target, order: try Self.nextOrder(db)).insert(db)
            }
        }
    }

    public func slot(_ slot: Favorite.Slot) throws -> Favorite? {
        try database.read { try Favorite.filter(Column("slot") == slot.rawValue).fetchOne($0) }
    }

    /// Saves a stop or place at the end of the list; saving it again changes nothing.
    @discardableResult
    public func addFavorite(_ target: SavedTarget) throws -> Favorite {
        try database.write { db in
            let saved = try Favorite.filter(Column("slot") == nil).fetchAll(db)
            if let existing = saved.first(where: { $0.target == target }) { return existing }
            let favorite = Favorite(target: target, order: try Self.nextOrder(db))
            try favorite.insert(db)
            return favorite
        }
    }

    public func isFavorite(_ target: SavedTarget) throws -> Bool {
        try favorites().contains { $0.target == target }
    }

    public func removeFavorite(id: UUID) throws {
        try database.write { db in
            _ = try Favorite.deleteOne(db, key: id)
            try Self.renumber(db)
        }
    }

    public func renameFavorite(id: UUID, to name: String?) throws {
        try database.write { db in
            guard var favorite = try Favorite.fetchOne(db, key: id) else { return }
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            favorite.customName = trimmed?.isEmpty == false ? trimmed : nil
            try favorite.update(db)
        }
    }

    /// Moves favourites like SwiftUI's `onMove`: the items at `source` go before index `destination`.
    public func moveFavorites(from source: IndexSet, to destination: Int) throws {
        try database.write { db in
            var list = try Favorite.order(Column("order")).fetchAll(db)
            let moving = source.map { list[$0] }
            let before = source.filter { $0 < destination }.count
            for index in source.sorted(by: >) { list.remove(at: index) }
            list.insert(contentsOf: moving, at: min(destination - before, list.count))
            for (index, var favorite) in list.enumerated() where favorite.order != index {
                favorite.order = index
                try favorite.update(db)
            }
        }
    }

    private static func nextOrder(_ db: Database) throws -> Int {
        (try Int.fetchOne(db, sql: "SELECT MAX(\"order\") FROM favorite") ?? -1) + 1
    }

    private static func renumber(_ db: Database) throws {
        for (index, var favorite) in try Favorite.order(Column("order")).fetchAll(db).enumerated()
        where favorite.order != index {
            favorite.order = index
            try favorite.update(db)
        }
    }

    // MARK: Recent searches

    /// Newest first.
    public func recent() throws -> [RecentItem] {
        try database.read { try RecentItem.order(Column("date").desc).fetchAll($0) }
    }

    /// Records a search; the same target again moves to the top instead of appearing twice.
    public func addRecent(_ target: SavedTarget, at date: Date = .now) throws {
        try database.write { db in
            for item in try RecentItem.fetchAll(db) where item.target == target { try item.delete(db) }
            try RecentItem(target: target, date: date).insert(db)
            let extra = try RecentItem.order(Column("date").desc).limit(-1, offset: Self.recentLimit).fetchAll(db)
            for item in extra { try item.delete(db) }
        }
    }

    public func removeRecent(id: UUID) throws {
        try database.write { _ = try RecentItem.deleteOne($0, key: id) }
    }

    // MARK: Finished trips

    public func addFinishedTrip(_ trip: FinishedTrip) throws {
        try database.write { try trip.insert($0) }
    }

    /// Trips since Monday 00:00 (German weeks start on Monday), for "5 Fahrten diese Woche".
    public func tripsThisWeek(now: Date = .now, calendar: Calendar = .konstanz) throws -> Int {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return try database.read { try FinishedTrip.filter(Column("date") >= monday).fetchCount($0) }
    }

    // MARK: Alarms

    public func addAlarm(_ alarm: Alarm) throws {
        try database.write { db in
            // One alarm per departure: setting it again replaces the minutes.
            try Alarm.filter(Column("tripID") == alarm.tripID && Column("stationID") == alarm.stationID
                             && Column("departure") == alarm.departure).deleteAll(db)
            try alarm.insert(db)
        }
    }

    public func removeAlarm(id: UUID) throws {
        try database.write { _ = try Alarm.deleteOne($0, key: id) }
    }

    /// Alarms that have not gone off yet, soonest first.
    public func upcomingAlarms(after date: Date = .now) throws -> [Alarm] {
        try database.read { db in
            try Alarm.order(Column("departure")).fetchAll(db).filter { $0.fireDate > date }
        }
    }

    /// Drops alarms for departures that are gone.
    public func removePastAlarms(before date: Date = .now) throws {
        try database.write { _ = try Alarm.filter(Column("departure") < date).deleteAll($0) }
    }

    // MARK: Privacy

    /// "Verlauf löschen" (screen 25): recent searches and the trip counter. Favourites and alarms stay.
    public func clearHistory() throws {
        try database.write { db in
            _ = try RecentItem.deleteAll(db)
            _ = try FinishedTrip.deleteAll(db)
        }
    }
}

// MARK: Records

extension Favorite: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "favorite"
}

extension RecentItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recent"
}

extension FinishedTrip: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "finishedTrip"
}

extension Alarm: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "alarm"
}
