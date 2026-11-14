import CSQLite
import Foundation

/// A tiny read-only SQLite reader: enough to load `timetable.db` into memory once at boot.
struct SQLiteReader: ~Copyable {
    enum Failure: Error, CustomStringConvertible {
        case open(String), query(String)

        var description: String {
            switch self {
            case let .open(message): "cannot open timetable: \(message)"
            case let .query(message): "timetable query failed: \(message)"
            }
        }
    }

    private let db: OpaquePointer

    /// Opens the file immutable, so SQLite writes nothing next to it (the container's file system is read-only).
    init(path: String) throws {
        var handle: OpaquePointer?
        let uri = "file:\(path)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(handle)
            throw Failure.open("\(path): \(message)")
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    /// Runs a query and hands each row to `row`.
    func each(_ sql: String, _ row: (Row) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure.query("\(sql): \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else { throw Failure.query("\(sql): \(String(cString: sqlite3_errmsg(db)))") }
            try row(Row(statement: statement))
        }
    }

    struct Row {
        let statement: OpaquePointer

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }

        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func string(_ column: Int32) -> String? {
            guard let text = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: text)
        }
    }
}
