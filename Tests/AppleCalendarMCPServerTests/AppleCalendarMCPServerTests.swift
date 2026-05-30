import Foundation
import SQLite3
import Testing
@testable import AppleCalendarMCPServer

struct StubCalendarService: CalendarServing {
    var calendars: [CalendarSummary] = [
        CalendarSummary(id: "cal-1", title: "Primary", sourceTitle: "iCloud", allowsContentModifications: true),
    ]
    var events: [CalendarEvent] = [
        CalendarEvent(
            id: "evt-1",
            calendarID: "cal-1",
            calendarTitle: "Primary",
            title: "Planning",
            start: DateCodec.parse("2026-04-26T09:00:00.000+08:00")!,
            end: DateCodec.parse("2026-04-26T10:00:00.000+08:00")!,
            isAllDay: false,
            location: "Room A",
            notes: "Prep",
            url: "https://example.com"
        ),
    ]

    func listCalendars() async throws -> [CalendarSummary] { calendars }
    func searchEvents(_ request: EventSearchRequest) async throws -> [CalendarEvent] { events }
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent { events[0] }
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent { events[0] }
    func deleteEvent(_ request: DeleteEventRequest) async throws {}
}

@Test func searchArgumentsRejectOversizedRange() throws {
    let arguments: [String: JSONValue] = [
        "start": .string("2026-01-01T00:00:00.000Z"),
        "end": .string("2027-02-01T00:00:00.000Z"),
    ]

    #expect(throws: ServerError.self) {
        try ToolArguments.parseSearch(arguments)
    }
}

@Test func updateArgumentsRequireMutableField() throws {
    let arguments: [String: JSONValue] = [
        "eventId": .string("evt-1"),
    ]

    #expect(throws: ServerError.self) {
        try ToolArguments.parseUpdate(arguments)
    }
}

@Test func configurationParsesReadOnlyAndAllowlist() throws {
    let configuration = try ServerConfiguration.fromEnvironment([
        "APPLE_CALENDAR_MCP_READ_ONLY": "true",
        "APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS": "cal-1, cal-2",
    ])

    #expect(configuration.readOnly)
    #expect(configuration.writableCalendarIDs == Set(["cal-1", "cal-2"]))
    #expect(configuration.effectiveAllowsContentModifications(for: "cal-1", systemAllows: true) == false)
}

@Test func configurationRejectsBadBoolean() {
    #expect(throws: ServerError.self) {
        try ServerConfiguration.fromEnvironment([
            "APPLE_CALENDAR_MCP_READ_ONLY": "maybe",
        ])
    }
}

@Test func startupOptionsRecognizeCalendarAccessPromptMode() {
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer"]) == .mcpServer)
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--request-calendar-access"]) == .requestCalendarAccess)
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--other"]) == .mcpServer)
}

@Test func eventKitAccessModeSeparatesReadAndCreateCapabilities() {
    #expect(CalendarAccessMode.full.canReadEvents)
    #expect(CalendarAccessMode.full.canCreateEvents)
    #expect(!CalendarAccessMode.writeOnly.canReadEvents)
    #expect(CalendarAccessMode.writeOnly.canCreateEvents)
    #expect(!CalendarAccessMode.none.canReadEvents)
    #expect(!CalendarAccessMode.none.canCreateEvents)

    if #available(macOS 14.0, *) {
        #expect(EventKitAccess.mode(for: .fullAccess) == .full)
        #expect(EventKitAccess.mode(for: .writeOnly) == .writeOnly)
    }
    #expect(EventKitAccess.mode(for: .denied) == .none)
    #expect(EventKitAccess.mode(for: .restricted) == .none)
}

@Test func toolsListReturnsCalendarTools() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let request = """
    {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
    """

    let response = try #require(await server.handleMessage(Data(request.utf8)))
    let unframed = try #require(unframe(response))
    let json = try JSONDecoder().decode(JSONRPCResponseEnvelope.self, from: unframed)
    let tools = try #require(json.result?["tools"]?.arrayValue)

    #expect(tools.contains { $0.objectValue?["name"]?.stringValue == "calendar_list" })
    #expect(tools.contains { $0.objectValue?["name"]?.stringValue == "calendar_event_create" })
}

@Test func toolsCallReturnsStructuredContent() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let request = """
    {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_events_search","arguments":{"start":"2026-04-26T00:00:00.000+08:00","end":"2026-04-27T00:00:00.000+08:00"}}}
    """

    let response = try #require(await server.handleMessage(Data(request.utf8)))
    let unframed = try #require(unframe(response))
    let json = try JSONDecoder().decode(JSONRPCResponseEnvelope.self, from: unframed)
    let structured = try #require(json.result?["structuredContent"]?.objectValue)
    let events = try #require(structured["events"]?.arrayValue)

    #expect(events.count == 1)
    #expect(events.first?.objectValue?["title"]?.stringValue == "Planning")
}

@Test func localCalendarDatabaseListsCalendarsReadOnly() throws {
    let databaseURL = try makeCalendarDatabase()
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let database = LocalCalendarDatabase(path: databaseURL.path)
    let calendars = try database.listCalendars(configuration: ServerConfiguration(readOnly: false, writableCalendarIDs: nil))

    #expect(calendars == [
        CalendarSummary(id: "cal-primary", title: "Primary", sourceTitle: "iCloud", allowsContentModifications: false),
    ])
}

@Test func localCalendarDatabaseSearchesDirectAndOccurrenceEvents() throws {
    let databaseURL = try makeCalendarDatabase()
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let database = LocalCalendarDatabase(path: databaseURL.path)
    let request = EventSearchRequest(
        start: DateCodec.parse("2026-05-07T00:00:00.000+08:00")!,
        end: DateCodec.parse("2026-05-08T00:00:00.000+08:00")!,
        calendarIDs: nil,
        query: "planning"
    )

    let events = try database.searchEvents(request)

    #expect(events.map(\.title) == ["Planning", "Weekly planning"])
    #expect(events.allSatisfy { $0.calendarID == "cal-primary" })
    #expect(events.allSatisfy { $0.id.hasPrefix("local-db:") })
}

private struct JSONRPCResponseEnvelope: Decodable {
    let result: [String: JSONValue]?
}

private func unframe(_ data: Data) -> Data? {
    var mutable = data
    return try? StdioFraming.extractMessage(from: &mutable)
}

private func makeCalendarDatabase() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppleCalendarMCPServerTests-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")

    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw ServerError.internalError("Failed to create test database")
    }
    defer { sqlite3_close(database) }

    let sql = """
    CREATE TABLE Store (ROWID INTEGER PRIMARY KEY, name TEXT, disabled INTEGER);
    CREATE TABLE Calendar (ROWID INTEGER PRIMARY KEY, store_id INTEGER, title TEXT, UUID TEXT);
    CREATE TABLE CalendarItem (
      ROWID INTEGER PRIMARY KEY,
      summary TEXT,
      description TEXT,
      start_date REAL,
      end_date REAL,
      all_day INTEGER,
      calendar_id INTEGER,
      url TEXT,
      hidden INTEGER,
      has_recurrences INTEGER,
      location_id INTEGER
    );
    CREATE TABLE OccurrenceCache (
      event_id INTEGER,
      calendar_id INTEGER,
      occurrence_start_date REAL,
      occurrence_end_date REAL
    );
    CREATE TABLE Location (ROWID INTEGER PRIMARY KEY, title TEXT, address TEXT);

    INSERT INTO Store (ROWID, name, disabled) VALUES (1, 'iCloud', 0);
    INSERT INTO Calendar (ROWID, store_id, title, UUID) VALUES (10, 1, 'Primary', 'cal-primary');
    INSERT INTO Location (ROWID, title, address) VALUES (100, 'Room A', '1 Example Road');

    INSERT INTO CalendarItem (
      ROWID, summary, description, start_date, end_date, all_day, calendar_id, url, hidden, has_recurrences, location_id
    ) VALUES (
      20,
      'Planning',
      'Agenda',
      \(DateCodec.parse("2026-05-07T09:00:00.000+08:00")!.timeIntervalSinceReferenceDate),
      \(DateCodec.parse("2026-05-07T10:00:00.000+08:00")!.timeIntervalSinceReferenceDate),
      0,
      10,
      'https://example.com',
      0,
      0,
      100
    );

    INSERT INTO CalendarItem (
      ROWID, summary, description, start_date, end_date, all_day, calendar_id, url, hidden, has_recurrences, location_id
    ) VALUES (
      21,
      'Weekly planning',
      'Recurring agenda',
      \(DateCodec.parse("2026-05-01T09:00:00.000+08:00")!.timeIntervalSinceReferenceDate),
      \(DateCodec.parse("2026-05-01T10:00:00.000+08:00")!.timeIntervalSinceReferenceDate),
      0,
      10,
      NULL,
      0,
      1,
      NULL
    );

    INSERT INTO OccurrenceCache (
      event_id, calendar_id, occurrence_start_date, occurrence_end_date
    ) VALUES (
      21,
      10,
      \(DateCodec.parse("2026-05-07T11:00:00.000+08:00")!.timeIntervalSinceReferenceDate),
      \(DateCodec.parse("2026-05-07T12:00:00.000+08:00")!.timeIntervalSinceReferenceDate)
    );
    """

    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        throw ServerError.internalError("Failed to seed test database: \(message)")
    }

    return url
}
