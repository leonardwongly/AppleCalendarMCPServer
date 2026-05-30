import Foundation
import SQLite3

protocol LocalCalendarFallbackReading: Sendable {
    func listCalendars(configuration: ServerConfiguration) throws -> [CalendarSummary]
    func searchEvents(_ request: EventSearchRequest) throws -> [CalendarEvent]
}

final class LocalCalendarDatabase: LocalCalendarFallbackReading, @unchecked Sendable {
    private static let appleCalendarDatabasePath = "Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"

    private let path: String

    init(path: String) {
        self.path = path
    }

    static func defaultIfReadable(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> LocalCalendarDatabase? {
        let path = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(appleCalendarDatabasePath)
            .path

        guard fileManager.isReadableFile(atPath: path) else {
            return nil
        }

        return LocalCalendarDatabase(path: path)
    }

    func listCalendars(configuration: ServerConfiguration) throws -> [CalendarSummary] {
        try withDatabase { database in
            let rows = try database.query(
                """
                SELECT
                  COALESCE(c.UUID, CAST(c.ROWID AS TEXT)) AS calendar_id,
                  c.title AS calendar_title,
                  COALESCE(s.name, 'Local') AS source_title
                FROM Calendar c
                LEFT JOIN Store s ON s.ROWID = c.store_id
                WHERE IFNULL(s.disabled, 0) = 0
                ORDER BY lower(source_title), lower(calendar_title)
                """
            )

            return rows.map {
                CalendarSummary(
                    id: $0.string("calendar_id") ?? "",
                    title: $0.string("calendar_title") ?? "Untitled",
                    sourceTitle: $0.string("source_title") ?? "Local",
                    allowsContentModifications: false
                )
            }
            .filter { !$0.id.isEmpty }
        }
    }

    func searchEvents(_ request: EventSearchRequest) throws -> [CalendarEvent] {
        try withDatabase { database in
            let start = request.start.timeIntervalSinceReferenceDate
            let end = request.end.timeIntervalSinceReferenceDate
            let rows = try database.query(
                """
                SELECT
                  'occurrence' AS row_source,
                  oc.event_id AS item_id,
                  oc.occurrence_start_date AS start_date,
                  oc.occurrence_end_date AS end_date,
                  ci.summary AS summary,
                  ci.description AS notes,
                  ci.url AS url,
                  ci.all_day AS all_day,
                  COALESCE(c.UUID, CAST(c.ROWID AS TEXT)) AS calendar_id,
                  c.title AS calendar_title,
                  COALESCE(loc.title, loc.address) AS location
                FROM OccurrenceCache oc
                JOIN CalendarItem ci ON ci.ROWID = oc.event_id
                LEFT JOIN Calendar c ON c.ROWID = oc.calendar_id
                LEFT JOIN Store s ON s.ROWID = c.store_id
                LEFT JOIN Location loc ON loc.ROWID = ci.location_id
                WHERE oc.occurrence_start_date < ?
                  AND oc.occurrence_end_date > ?
                  AND IFNULL(ci.hidden, 0) = 0
                  AND IFNULL(s.disabled, 0) = 0

                UNION ALL

                SELECT
                  'item' AS row_source,
                  ci.ROWID AS item_id,
                  ci.start_date AS start_date,
                  ci.end_date AS end_date,
                  ci.summary AS summary,
                  ci.description AS notes,
                  ci.url AS url,
                  ci.all_day AS all_day,
                  COALESCE(c.UUID, CAST(c.ROWID AS TEXT)) AS calendar_id,
                  c.title AS calendar_title,
                  COALESCE(loc.title, loc.address) AS location
                FROM CalendarItem ci
                LEFT JOIN Calendar c ON c.ROWID = ci.calendar_id
                LEFT JOIN Store s ON s.ROWID = c.store_id
                LEFT JOIN Location loc ON loc.ROWID = ci.location_id
                WHERE ci.start_date < ?
                  AND ci.end_date > ?
                  AND IFNULL(ci.has_recurrences, 0) = 0
                  AND IFNULL(ci.hidden, 0) = 0
                  AND IFNULL(s.disabled, 0) = 0
                ORDER BY start_date, end_date, summary
                """,
                bindings: [.double(end), .double(start), .double(end), .double(start)]
            )

            var seen = Set<String>()
            let allowedCalendarIDs = request.calendarIDs.map(Set.init)
            let normalizedQuery = request.query?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            var events: [CalendarEvent] = []

            for row in rows {
                guard
                    let itemID = row.int64("item_id"),
                    let startDate = row.double("start_date"),
                    let endDate = row.double("end_date"),
                    let calendarID = row.string("calendar_id")
                else {
                    continue
                }

                if let allowedCalendarIDs, !allowedCalendarIDs.contains(calendarID) {
                    continue
                }

                let title = row.string("summary") ?? ""
                let location = row.string("location")
                let notes = row.string("notes")
                let url = row.string("url")

                if let normalizedQuery {
                    let haystack = [title, location, notes, url]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    guard haystack.contains(normalizedQuery) else {
                        continue
                    }
                }

                let identity = "\(itemID):\(startDate):\(endDate)"
                guard seen.insert(identity).inserted else {
                    continue
                }

                events.append(
                    CalendarEvent(
                        id: "local-db:\(itemID):\(Int64(startDate))",
                        calendarID: calendarID,
                        calendarTitle: row.string("calendar_title") ?? "Untitled",
                        title: title,
                        start: Date(timeIntervalSinceReferenceDate: startDate),
                        end: Date(timeIntervalSinceReferenceDate: endDate),
                        isAllDay: (row.int64("all_day") ?? 0) != 0,
                        location: location,
                        notes: notes,
                        url: url
                    )
                )
            }

            return events
        }
    }

    private func withDatabase<T>(_ operation: (SQLiteDatabase) throws -> T) throws -> T {
        let database = try SQLiteDatabase(path: path)
        defer { database.close() }
        return try operation(database)
    }
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let handle {
                sqlite3_close(handle)
            }
            throw ServerError.internalError("Failed to open local Apple Calendar database read-only: \(message)")
        }
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        guard let handle else {
            throw ServerError.internalError("SQLite database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ServerError.internalError("Failed to prepare local Apple Calendar query: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            try bind(binding, to: Int32(index + 1), statement: statement, database: handle)
        }

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                rows.append(SQLiteRow(statement: statement))
            case SQLITE_DONE:
                return rows
            default:
                throw ServerError.internalError("Failed to read local Apple Calendar database: \(String(cString: sqlite3_errmsg(handle)))")
            }
        }
    }

    private func bind(_ binding: SQLiteBinding, to index: Int32, statement: OpaquePointer?, database: OpaquePointer) throws {
        let result: Int32
        switch binding {
        case let .double(value):
            result = sqlite3_bind_double(statement, index, value)
        }

        guard result == SQLITE_OK else {
            throw ServerError.internalError("Failed to bind local Apple Calendar query: \(String(cString: sqlite3_errmsg(database)))")
        }
    }
}

private enum SQLiteBinding {
    case double(Double)
}

private struct SQLiteRow {
    private let values: [String: SQLiteValue]

    init(statement: OpaquePointer?) {
        var values: [String: SQLiteValue] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                values[name] = .double(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(statement, index) {
                    values[name] = .text(String(cString: text))
                } else {
                    values[name] = .null
                }
            case SQLITE_NULL:
                values[name] = .null
            default:
                values[name] = .text("")
            }
        }
        self.values = values
    }

    func string(_ column: String) -> String? {
        switch values[column] {
        case let .text(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case .null, nil:
            return nil
        }
    }

    func double(_ column: String) -> Double? {
        switch values[column] {
        case let .double(value):
            return value
        case let .integer(value):
            return Double(value)
        case let .text(value):
            return Double(value)
        case .null, nil:
            return nil
        }
    }

    func int64(_ column: String) -> Int64? {
        switch values[column] {
        case let .integer(value):
            return value
        case let .double(value):
            return Int64(value)
        case let .text(value):
            return Int64(value)
        case .null, nil:
            return nil
        }
    }
}

private enum SQLiteValue {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null
}
