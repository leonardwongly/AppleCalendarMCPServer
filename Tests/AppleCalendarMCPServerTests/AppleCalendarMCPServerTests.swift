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

struct FailingCalendarService: CalendarServing {
    let error: ServerError

    func listCalendars() async throws -> [CalendarSummary] { throw error }
    func searchEvents(_ request: EventSearchRequest) async throws -> [CalendarEvent] { throw error }
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent { throw error }
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent { throw error }
    func deleteEvent(_ request: DeleteEventRequest) async throws { throw error }
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

@Test func searchArgumentsValidateAndApplyResultLimit() throws {
    let request = try ToolArguments.parseSearch([
        "start": .string("2026-01-01T00:00:00.000Z"),
        "end": .string("2026-01-02T00:00:00.000Z"),
        "limit": .number(25),
    ])
    #expect(request.limit == 25)

    #expect(throws: ServerError.self) {
        try ToolArguments.parseSearch([
            "start": .string("2026-01-01T00:00:00.000Z"),
            "end": .string("2026-01-02T00:00:00.000Z"),
            "limit": .number(5_001),
        ])
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

@Test func updateArgumentsTreatNullOptionalFieldsAsClearOperations() throws {
    let request = try ToolArguments.parseUpdate([
        "eventId": .string("evt-1"),
        "location": .null,
        "notes": .null,
        "url": .null,
    ])

    #expect(request.location == nil)
    #expect(request.notes == nil)
    #expect(request.url == nil)
    #expect(request.clearLocation)
    #expect(request.clearNotes)
    #expect(request.clearURL)
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

@Test func configurationTreatsPresentEmptyAllowlistAsDenyAll() throws {
    let configuration = try ServerConfiguration.fromEnvironment([
        "APPLE_CALENDAR_MCP_READ_ONLY": "false",
        "APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS": "",
    ])

    #expect(configuration.writableCalendarIDs == [])
    #expect(!configuration.allowsWrite(to: "cal-1"))
    #expect(!configuration.effectiveAllowsContentModifications(for: "cal-1", systemAllows: true))
}

@Test func startupOptionsRecognizeCalendarAccessPromptMode() {
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer"], standardInputIsTerminal: false) == .mcpServer)
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer"], standardInputIsTerminal: true) == .help)
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--mcp-server"], standardInputIsTerminal: true) == .mcpServer)
    if case .invalid(let message) = StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--mcp-server", "list"]) {
        #expect(message.contains("cannot be combined"))
    } else {
        Issue.record("Expected combined MCP server flag usage to be rejected")
    }
    #expect(StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--request-calendar-access"]) == .requestCalendarAccess)
    if case .invalid(let message) = StartupOptions.mode(arguments: ["AppleCalendarMCPServer", "--other"]) {
        #expect(message.contains("Unknown command or option"))
    } else {
        Issue.record("Expected unknown option to be rejected")
    }
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

// MARK: - Transport framing conformance

@Test func stdioFramingRoundTripsNewlineDelimitedMessages() throws {
    let payload = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
    let framed = StdioFraming.frame(payload)

    #expect(framed.last == UInt8(ascii: "\n"))
    #expect(!framed.dropLast().contains(UInt8(ascii: "\n")))

    var buffer = framed
    let extracted = try #require(StdioFraming.extractMessage(from: &buffer))
    #expect(extracted == payload)
    #expect(buffer.isEmpty)
}

@Test func stdioFramingExtractsMultipleMessagesAndToleratesBlankLines() throws {
    var buffer = Data()
    buffer.append(StdioFraming.frame(Data(#"{"id":1}"#.utf8)))
    buffer.append(Data("\n".utf8)) // stray blank line between messages
    buffer.append(StdioFraming.frame(Data(#"{"id":2}"#.utf8)))

    let first = try #require(StdioFraming.extractMessage(from: &buffer))
    #expect(first == Data(#"{"id":1}"#.utf8))
    let second = try #require(StdioFraming.extractMessage(from: &buffer))
    #expect(second == Data(#"{"id":2}"#.utf8))
    #expect(StdioFraming.extractMessage(from: &buffer) == nil)
}

@Test func stdioFramingLeavesIncompleteMessageBuffered() throws {
    var buffer = Data(#"{"id":1}"#.utf8) // no trailing newline yet
    #expect(StdioFraming.extractMessage(from: &buffer) == nil)
    #expect(buffer == Data(#"{"id":1}"#.utf8))
}

@Test func stdioFramingRejectsOversizedMessages() {
    let oversized = Data(repeating: UInt8(ascii: "x"), count: StdioFraming.maximumMessageSize + 1)
    #expect(StdioFraming.exceedsMaximumMessageSize(oversized))
    #expect(!StdioFraming.exceedsMaximumMessageSize(Data(#"{"id":1}"#.utf8)))
}

@Test func serverResponseContainsNoEmbeddedNewlines() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_list","arguments":{}}}"#
    let response = try #require(await server.handleMessage(Data(request.utf8)))

    // Exactly one trailing newline; the framed envelope itself must be single-line.
    #expect(response.last == UInt8(ascii: "\n"))
    #expect(response.filter { $0 == UInt8(ascii: "\n") }.count == 1)
}

// MARK: - initialize negotiation

@Test func initializeEchoesSupportedProtocolVersion() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
    )
    #expect(envelope.result?["protocolVersion"]?.stringValue == "2025-03-26")
}

@Test func initializeFallsBackToLatestProtocolVersionForUnknownRequest() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#
    )
    #expect(envelope.result?["protocolVersion"]?.stringValue == MCPServer.latestProtocolVersion)
}

@Test func initializeDefaultsToLatestWhenVersionOmitted() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
    )
    #expect(envelope.result?["protocolVersion"]?.stringValue == MCPServer.latestProtocolVersion)
}

// MARK: - tools/call result + error semantics

@Test func toolsCallReturnsIsErrorFalseOnSuccess() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_list","arguments":{}}}"#
    )
    #expect(envelope.error == nil)
    #expect(envelope.result?["isError"]?.boolValue == false)
    #expect(envelope.result?["structuredContent"]?.objectValue?["calendars"]?.arrayValue?.count == 1)
}

@Test func toolsCallCreateReturnsStructuredEvent() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_event_create","arguments":{"calendarId":"cal-1","title":"Plan","start":"2026-04-26T09:00:00+08:00","end":"2026-04-26T10:00:00+08:00"}}}"#
    )
    let structured = try #require(envelope.result?["structuredContent"]?.objectValue)
    #expect(structured["event"]?.objectValue?["title"]?.stringValue == "Planning")
    #expect(envelope.result?["isError"]?.boolValue == false)
}

@Test func toolsCallDeleteReturnsDeletedTrue() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_event_delete","arguments":{"eventId":"evt-1"}}}"#
    )
    #expect(envelope.result?["structuredContent"]?.objectValue?["deleted"]?.boolValue == true)
}

@Test func toolsCallSurfacesExecutionErrorsAsIsErrorResult() async throws {
    let server = MCPServer(calendarService: FailingCalendarService(error: .permissionDenied))
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_list","arguments":{}}}"#
    )
    // Execution errors are reported in-band, not as JSON-RPC protocol errors.
    #expect(envelope.error == nil)
    #expect(envelope.result?["isError"]?.boolValue == true)
    let content = try #require(envelope.result?["content"]?.arrayValue)
    #expect(content.first?.objectValue?["text"]?.stringValue?.isEmpty == false)
}

@Test func toolsCallReturnsProtocolErrorForUnknownTool() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_unknown","arguments":{}}}"#
    )
    #expect(envelope.result == nil)
    #expect(envelope.error?.code == -32602)
}

@Test func toolsCallReturnsToolErrorForInvalidArguments() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_events_search","arguments":{"start":"not-a-date","end":"also-not-a-date"}}}"#
    )
    #expect(envelope.error == nil)
    #expect(envelope.result?["isError"]?.boolValue == true)
}

@Test func unsupportedMethodReturnsMethodNotFound() async throws {
    let server = MCPServer(calendarService: StubCalendarService())
    let envelope = try await sendRequest(
        server,
        #"{"jsonrpc":"2.0","id":1,"method":"does/notExist","params":{}}"#
    )
    #expect(envelope.error?.code == -32601)
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
    let id: JSONValue?
    let result: [String: JSONValue]?
    let error: JSONRPCErrorEnvelope?
}

private struct JSONRPCErrorEnvelope: Decodable, Equatable {
    let code: Int
    let message: String
}

private func unframe(_ data: Data) -> Data? {
    var mutable = data
    return StdioFraming.extractMessage(from: &mutable)
}

private func sendRequest(_ server: MCPServer, _ json: String) async throws -> JSONRPCResponseEnvelope {
    let response = try #require(await server.handleMessage(Data(json.utf8)))
    let unframed = try #require(unframe(response))
    return try JSONDecoder().decode(JSONRPCResponseEnvelope.self, from: unframed)
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

// MARK: - CLI Tests

@Test func cliCommandParsingHandlesListCalendars() {
    let result = CLICommand.parse(["program", "list", "calendars"])
    #expect(result != nil)
    if case .list(.calendars(let json)) = result?.0 {
        #expect(!json)
    } else {
        Issue.record("Expected list calendars command")
    }
}

@Test func cliCommandParsingHandlesListCalendarsWithJson() {
    let result = CLICommand.parse(["program", "list", "calendars", "--json"])
    #expect(result != nil)
    if case .list(.calendars(let json)) = result?.0 {
        #expect(json)
    } else {
        Issue.record("Expected list calendars with json flag")
    }
}

@Test func cliCommandParsingHandlesSearchEvents() {
    let result = CLICommand.parse([
        "program", "search", "events",
        "--calendar", "cal-1",
        "--from", "2026-06-01",
        "--to", "2026-06-30",
        "--query", "meeting"
    ])
    #expect(result != nil)
    if case .search(let cmd) = result?.0 {
        #expect(cmd.calendar == "cal-1")
        #expect(cmd.from == "2026-06-01")
        #expect(cmd.to == "2026-06-30")
        #expect(cmd.query == "meeting")
    } else {
        Issue.record("Expected search events command")
    }
}

@Test func cliCommandParsingHandlesCreateEvent() {
    let result = CLICommand.parse([
        "program", "create", "event",
        "--calendar", "cal-1",
        "--title", "Meeting",
        "--start", "2026-06-15 10:00",
        "--end", "2026-06-15 11:00",
        "--location", "Room 5",
        "--url", "https://example.com"
    ])
    #expect(result != nil)
    if case .create(let cmd) = result?.0 {
        #expect(cmd.calendar == "cal-1")
        #expect(cmd.title == "Meeting")
        #expect(cmd.start == "2026-06-15 10:00")
        #expect(cmd.location == "Room 5")
        #expect(cmd.url == "https://example.com")
    } else {
        Issue.record("Expected create event command")
    }
}

@Test func cliCommandParsingHandlesUpdateEvent() {
    let result = CLICommand.parse([
        "program", "update", "event", "evt-1",
        "--title", "Updated",
        "--span", "futureEvents"
    ])
    #expect(result != nil)
    if case .update(let cmd) = result?.0 {
        #expect(cmd.eventId == "evt-1")
        #expect(cmd.title == "Updated")
        #expect(cmd.span == "futureEvents")
    } else {
        Issue.record("Expected update event command")
    }
}

@Test func cliCommandParsingHandlesUpdateEventWithCalendarAndAllDay() {
    let result = CLICommand.parse([
        "program", "update", "event", "evt-1",
        "--calendar", "cal-2",
        "--all-day",
        "--title", "Updated"
    ])
    #expect(result != nil)
    if case .update(let cmd) = result?.0 {
        #expect(cmd.eventId == "evt-1")
        #expect(cmd.calendar == "cal-2")
        #expect(cmd.allDay == true)
        #expect(cmd.title == "Updated")
    } else {
        Issue.record("Expected update event command")
    }
}

@Test func cliCommandParsingHandlesExplicitClearFlags() {
    let result = CLICommand.parse([
        "program", "update", "event", "evt-1",
        "--clear-location", "--clear-notes", "--clear-url",
    ])
    if case .update(let cmd) = result?.0 {
        #expect(cmd.clearLocation)
        #expect(cmd.clearNotes)
        #expect(cmd.clearURL)
    } else {
        Issue.record("Expected update event command with clear flags")
    }
}

@Test func cliCommandParsingRejectsSetAndClearForSameField() {
    #expect(throws: ServerError.self) {
        try CLICommand.parseValidated([
            "program", "update", "event", "evt-1",
            "--location", "Room", "--clear-location",
        ])
    }
}

@Test func cliCommandParsingUpdateEventDefaultsCalendarAndAllDayToNil() {
    let result = CLICommand.parse(["program", "update", "event", "evt-1", "--title", "X"])
    if case .update(let cmd) = result?.0 {
        #expect(cmd.calendar == nil)
        #expect(cmd.allDay == nil)
    } else {
        Issue.record("Expected update event command")
    }
}

@Test func cliCommandParsingHandlesDeleteEvent() {
    let result = CLICommand.parse([
        "program", "delete", "event", "evt-1",
        "--span", "thisEvent"
    ])
    #expect(result != nil)
    if case .delete(let cmd) = result?.0 {
        #expect(cmd.eventId == "evt-1")
        #expect(cmd.span == "thisEvent")
    } else {
        Issue.record("Expected delete event command")
    }
}

@Test func startupOptionsDetectsCLIMode() {
    let cliMode = StartupOptions.mode(arguments: ["program", "list", "calendars"])
    if case .cli = cliMode {
        // success
    } else {
        Issue.record("Expected CLI mode detection")
    }
}

@Test func startupOptionsDetectsHelpFlag() {
    let helpMode = StartupOptions.mode(arguments: ["program", "--help"])
    #expect(helpMode == .help)
}

@Test func startupOptionsDetectsCommandSpecificHelp() {
    let helpMode = StartupOptions.mode(arguments: ["program", "create", "event", "--help"])
    #expect(helpMode == .commandHelp(.createEvent))
}

@Test func startupOptionsDetectsVersionFlag() {
    let versionMode = StartupOptions.mode(arguments: ["program", "--version"])
    #expect(versionMode == .version)
}

@Test func startupOptionsRejectsInvalidCLIUsage() {
    let mode = StartupOptions.mode(arguments: ["program", "list", "calendars", "--calendar", "cal-1"])
    if case .invalid(let message) = mode {
        #expect(message.contains("Unsupported option"))
    } else {
        Issue.record("Expected invalid CLI usage")
    }
}

@Test func cliCommandParsingRejectsMissingFlagValue() {
    #expect(throws: ServerError.self) {
        try CLICommand.parseValidated(["program", "search", "events", "--calendar"])
    }
}

@Test func cliCommandParsingRejectsUnknownFlag() {
    #expect(throws: ServerError.self) {
        try CLICommand.parseValidated(["program", "search", "events", "--bogus"])
    }
}

@Test func cliOutputFormatterParsesCalendarTable() {
    let calendars = [
        CalendarSummary(id: "cal-1", title: "Personal", sourceTitle: "iCloud", allowsContentModifications: true),
        CalendarSummary(id: "cal-2", title: "Work", sourceTitle: "Google", allowsContentModifications: false),
    ]
    let output = CLIOutputFormatter.formatCalendars(calendars, json: false)
    #expect(output.contains("Personal"))
    #expect(output.contains("Work"))
    #expect(output.contains("CALENDARS"))
}

@Test func cliOutputFormatterGeneratesValidJSON() throws {
    let calendars = [
        CalendarSummary(id: "cal-1", title: "Personal", sourceTitle: "iCloud", allowsContentModifications: true),
    ]
    let output = CLIOutputFormatter.formatCalendars(calendars, json: true)
    let data = output.data(using: .utf8)!
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json != nil)
    #expect((json?["calendars"] as? [[String: Any]])?.count == 1)
}

@Test func cliOutputFormatterGeneratesEventJSONWithNullFields() throws {
    let event = CalendarEvent(
        id: "evt-1",
        calendarID: "cal-1",
        calendarTitle: "Personal",
        title: "Planning",
        start: DateCodec.parse("2026-06-15T10:00:00.000+08:00")!,
        end: DateCodec.parse("2026-06-15T11:00:00.000+08:00")!,
        isAllDay: false,
        location: nil,
        notes: nil,
        url: nil
    )

    let output = CLIOutputFormatter.formatEvent(event, json: true)
    let data = output.data(using: .utf8)!
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["id"] as? String == "evt-1")
    #expect(json?["location"] is NSNull)
    #expect(json?["notes"] is NSNull)
    #expect(json?["url"] is NSNull)
}

@Test func cliOutputFormatterGeneratesDeleteJSON() throws {
    let output = CLIOutputFormatter.formatDelete(eventID: "evt-1", json: true)
    let data = output.data(using: .utf8)!
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(json?["deleted"] as? Bool == true)
    #expect(json?["eventId"] as? String == "evt-1")
}

@Test func dateCodecParsesISO8601WithAndWithoutFractionalSeconds() {
    #expect(DateCodec.parse("2026-06-15T10:00:00.000+08:00") != nil)
    #expect(DateCodec.parse("2026-06-15T10:00:00+08:00") != nil)
}

// MARK: - Management app (GUI) mode

@Test func startupOptionsAppFlagAlwaysWins() {
    // Explicit --app flag selects GUI mode regardless of stdin or env.
    #expect(
        StartupOptions.mode(
            arguments: ["AppleCalendarMCPServer", "--app"],
            standardInputIsTerminal: true,
            appModeEnvironmentEnabled: false
        ) == .app
    )
    #expect(
        StartupOptions.mode(
            arguments: ["AppleCalendarMCPServer", "--app"],
            standardInputIsTerminal: false,
            appModeEnvironmentEnabled: false
        ) == .app
    )
}

@Test func startupOptionsAppEnvOnlyHonoredWithoutOtherArguments() {
    // The bundled app sets APPLE_CALENDAR_APP_MODE via LSEnvironment and launches
    // with no arguments -> GUI mode.
    #expect(
        StartupOptions.mode(
            arguments: ["AppleCalendarMCPServer"],
            standardInputIsTerminal: false,
            appModeEnvironmentEnabled: true
        ) == .app
    )

    // A CLI invocation that merely inherits the env variable must NOT be hijacked.
    let cliMode = StartupOptions.mode(
        arguments: ["AppleCalendarMCPServer", "list", "calendars"],
        standardInputIsTerminal: true,
        appModeEnvironmentEnabled: true
    )
    #expect(cliMode == .cli(.list(.calendars(json: false))))
}

@Test func startupOptionsWithoutAppSignalsAreUnchanged() {
    #expect(
        StartupOptions.mode(
            arguments: ["AppleCalendarMCPServer"],
            standardInputIsTerminal: false,
            appModeEnvironmentEnabled: false
        ) == .mcpServer
    )
    #expect(
        StartupOptions.mode(
            arguments: ["AppleCalendarMCPServer"],
            standardInputIsTerminal: true,
            appModeEnvironmentEnabled: false
        ) == .help
    )
}

@Test func appModeEnvironmentParsingAcceptsTruthyValues() {
    for truthy in ["1", "true", "TRUE", "yes", "on", " on "] {
        #expect(StartupOptions.appModeEnvironmentEnabled([StartupOptions.appModeEnvironmentKey: truthy]))
    }
    for falsy in ["0", "false", "no", "off", "maybe", ""] {
        #expect(!StartupOptions.appModeEnvironmentEnabled([StartupOptions.appModeEnvironmentKey: falsy]))
    }
    #expect(!StartupOptions.appModeEnvironmentEnabled([:]))
}

@Test func mcpConfigBuilderEnvironmentReflectsPolicy() {
    let restricted = MCPConfigBuilder.environment(readOnly: true, writableCalendarIDs: ["cal-1", "cal-2"])
    #expect(restricted[MCPConfigBuilder.readOnlyEnvKey] == "true")
    #expect(restricted[MCPConfigBuilder.writableIDsEnvKey] == "cal-1,cal-2")

    // No allowlist -> the writable-IDs env var is omitted entirely.
    let open = MCPConfigBuilder.environment(readOnly: false, writableCalendarIDs: nil)
    #expect(open[MCPConfigBuilder.readOnlyEnvKey] == "false")
    #expect(open[MCPConfigBuilder.writableIDsEnvKey] == nil)

    // A present empty allowlist is explicit deny-all and must not fail open.
    let empty = MCPConfigBuilder.environment(readOnly: false, writableCalendarIDs: [])
    #expect(empty[MCPConfigBuilder.writableIDsEnvKey] == "")
}

@Test func mcpConfigBuilderJSONContainsCommandArgsAndName() {
    let json = MCPConfigBuilder.makeConfigJSON(
        serverName: "my-calendar",
        binaryPath: "/usr/local/bin/ical",
        readOnly: true,
        writableCalendarIDs: ["cal-1"]
    )
    #expect(json.contains("mcpServers"))
    #expect(json.contains("my-calendar"))
    #expect(json.contains("/usr/local/bin/ical"))
    #expect(json.contains(StartupOptions.mcpServerFlag))
    #expect(json.contains(MCPConfigBuilder.readOnlyEnvKey))
    #expect(json.contains("cal-1"))

    // A blank server name falls back to the default key.
    let fallback = MCPConfigBuilder.makeConfigJSON(
        serverName: "   ",
        binaryPath: "/bin/x",
        readOnly: false,
        writableCalendarIDs: nil
    )
    #expect(fallback.contains("apple-calendar"))
}

@MainActor
@Test func appSettingsStorePersistsAndPrunes() {
    let suiteName = "test-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = AppSettingsStore(defaults: defaults)
    #expect(store.readOnly)
    store.readOnly = true
    store.restrictWritableCalendars = true
    store.toggleWritable("cal-1", isOn: true)
    store.toggleWritable("cal-2", isOn: true)
    store.toggleWritable("cal-2", isOn: false)
    store.serverName = "custom"

    // Reload from the same backing store to confirm persistence.
    let reloaded = AppSettingsStore(defaults: defaults)
    #expect(reloaded.readOnly)
    #expect(reloaded.restrictWritableCalendars)
    #expect(reloaded.writableCalendarIDs == ["cal-1"])
    #expect(reloaded.serverName == "custom")

    // Pruning drops IDs that no longer map to a known calendar.
    reloaded.toggleWritable("stale-id", isOn: true)
    reloaded.pruneWritableCalendarIDs(knownIDs: ["cal-1"])
    #expect(reloaded.writableCalendarIDs == ["cal-1"])
}
