import Foundation

struct JSONRPCRequest: Decodable, Sendable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONRPCError?
}

struct JSONRPCError: Encodable, Sendable {
    let code: Int
    let message: String
}

struct ToolDefinition: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
}

actor MCPServer {
    private let calendarService: CalendarServing
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let tools: [ToolDefinition]

    /// Protocol versions this server can speak, newest first.
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let latestProtocolVersion = "2025-06-18"

    init(calendarService: CalendarServing) {
        self.calendarService = calendarService
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        self.tools = ToolCatalog.all
    }

    func handleMessage(_ data: Data) async -> Data? {
        let request: JSONRPCRequest

        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            return encode(JSONRPCResponse(id: nil, result: nil, error: JSONRPCError(code: -32700, message: "Parse error")))
        }

        guard request.jsonrpc == "2.0" else {
            return encode(JSONRPCResponse(id: request.id, result: nil, error: JSONRPCError(code: -32600, message: "Invalid Request")))
        }

        do {
            let result = try await handleRequest(request)
            guard request.id != nil else {
                return nil
            }
            return encode(JSONRPCResponse(id: request.id, result: result, error: nil))
        } catch let error as ServerError {
            guard request.id != nil else { return nil }
            return encode(JSONRPCResponse(id: request.id, result: nil, error: map(error)))
        } catch {
            guard request.id != nil else { return nil }
            return encode(JSONRPCResponse(id: request.id, result: nil, error: JSONRPCError(code: -32603, message: error.localizedDescription)))
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async throws -> JSONValue? {
        switch request.method {
        case "initialize":
            return initializeResult(params: request.params)
        case "notifications/initialized":
            return nil
        case "ping":
            return .object([:])
        case "tools/list":
            return .object([
                "tools": .array(tools.map(ToolCatalog.encode)),
            ])
        case "tools/call":
            return try await callTool(request.params)
        default:
            throw ServerError.unsupported("Unsupported method: \(request.method)")
        }
    }

    private func initializeResult(params: JSONValue?) -> JSONValue {
        let requested = params?.objectValue?["protocolVersion"]?.stringValue
        let negotiated: String
        if let requested, Self.supportedProtocolVersions.contains(requested) {
            negotiated = requested
        } else {
            negotiated = Self.latestProtocolVersion
        }

        return .object([
            "protocolVersion": .string(negotiated),
            "capabilities": .object([
                "tools": .object([
                    "listChanged": .bool(false),
                ]),
            ]),
            "serverInfo": .object([
                "name": .string("apple-calendar-mcp"),
                "version": .string("0.1.0"),
            ]),
        ])
    }

    private func callTool(_ params: JSONValue?) async throws -> JSONValue {
        guard let object = params?.objectValue else {
            throw ServerError.invalidParams("tools/call requires an object payload")
        }

        guard let toolName = object["name"]?.stringValue else {
            throw ServerError.invalidParams("tools/call requires a tool name")
        }

        let arguments = object["arguments"]?.objectValue ?? [:]

        do {
            let structured = try await executeTool(named: toolName, arguments: arguments)
            return try successResult(structured: structured)
        } catch let error as ServerError {
            switch error {
            case .invalidParams, .unsupported:
                // Malformed request / unknown tool: surface as a JSON-RPC protocol error.
                throw error
            case .permissionDenied, .readOnlyMode, .calendarNotFound,
                 .calendarNotWritable, .eventNotFound, .internalError:
                // Tool execution failures: surface inside the result with isError per MCP spec.
                return errorResult(message: error.localizedDescription)
            }
        }
    }

    private func executeTool(named toolName: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        switch toolName {
        case "calendar_list":
            return try await .object([
                "calendars": .array(calendarService.listCalendars().map { ToolCatalog.encode(calendar: $0) }),
            ])
        case "calendar_events_search":
            let request = try ToolArguments.parseSearch(arguments)
            return try await .object([
                "events": .array(calendarService.searchEvents(request).map { ToolCatalog.encode(event: $0) }),
            ])
        case "calendar_event_create":
            let request = try ToolArguments.parseCreate(arguments)
            let event = try await calendarService.createEvent(request)
            return .object([
                "event": ToolCatalog.encode(event: event),
            ])
        case "calendar_event_update":
            let request = try ToolArguments.parseUpdate(arguments)
            let event = try await calendarService.updateEvent(request)
            return .object([
                "event": ToolCatalog.encode(event: event),
            ])
        case "calendar_event_delete":
            let request = try ToolArguments.parseDelete(arguments)
            try await calendarService.deleteEvent(request)
            return .object([
                "deleted": .bool(true),
                "eventId": .string(request.eventID),
            ])
        default:
            throw ServerError.invalidParams("Unknown tool: \(toolName)")
        }
    }

    private func successResult(structured: JSONValue) throws -> JSONValue {
        let text = try prettyJSONString(from: structured)
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "structuredContent": structured,
            "isError": .bool(false),
        ])
    }

    private func errorResult(message: String) -> JSONValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message),
                ]),
            ]),
            "isError": .bool(true),
        ])
    }

    private func encode(_ response: JSONRPCResponse) -> Data {
        let payload = (try? encoder.encode(response)) ?? Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Encoding failure\"}}".utf8)
        return StdioFraming.frame(payload)
    }

    private func map(_ error: ServerError) -> JSONRPCError {
        switch error {
        case let .invalidParams(message):
            return JSONRPCError(code: -32602, message: message)
        case .unsupported:
            return JSONRPCError(code: -32601, message: error.localizedDescription)
        case .permissionDenied, .readOnlyMode, .calendarNotFound,
             .calendarNotWritable, .eventNotFound, .internalError:
            return JSONRPCError(code: -32603, message: error.localizedDescription)
        }
    }
}

enum StdioFraming {
    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    /// MCP stdio transport: each JSON-RPC message is a single line terminated by a newline.
    /// Messages must not contain embedded newlines (the compact JSON-RPC envelope never does).
    static func frame(_ payload: Data) -> Data {
        var result = payload
        result.append(newline)
        return result
    }

    /// Extracts the next newline-delimited message from the buffer, skipping blank lines.
    /// Returns nil when no complete line is buffered yet. Tolerates optional trailing `\r`.
    static func extractMessage(from buffer: inout Data) -> Data? {
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let line = Data(buffer[buffer.startIndex..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            let trimmed = line.last == carriageReturn ? Data(line.dropLast()) : line
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

private func prettyJSONString(from value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw ServerError.internalError("Failed to encode JSON output")
    }
    return string
}

enum ToolCatalog {
    static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "calendar_list",
            description: "List visible Apple Calendar calendars.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ])
        ),
        ToolDefinition(
            name: "calendar_events_search",
            description: "List events in a date range, optionally filtered by calendar IDs or a text query.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "start": .object(["type": .string("string"), "format": .string("date-time")]),
                    "end": .object(["type": .string("string"), "format": .string("date-time")]),
                    "calendarIds": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "query": .object(["type": .string("string"), "maxLength": .number(200)]),
                ]),
                "required": .array([.string("start"), .string("end")]),
                "additionalProperties": .bool(false),
            ])
        ),
        ToolDefinition(
            name: "calendar_event_create",
            description: "Create a calendar event in a specific calendar.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "calendarId": .object(["type": .string("string")]),
                    "title": .object(["type": .string("string"), "maxLength": .number(500)]),
                    "start": .object(["type": .string("string"), "format": .string("date-time")]),
                    "end": .object(["type": .string("string"), "format": .string("date-time")]),
                    "isAllDay": .object(["type": .string("boolean")]),
                    "location": .object(["type": .string("string"), "maxLength": .number(500)]),
                    "notes": .object(["type": .string("string"), "maxLength": .number(10_000)]),
                    "url": .object(["type": .string("string"), "format": .string("uri")]),
                ]),
                "required": .array([.string("calendarId"), .string("title"), .string("start"), .string("end")]),
                "additionalProperties": .bool(false),
            ])
        ),
        ToolDefinition(
            name: "calendar_event_update",
            description: "Update an existing calendar event by ID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "eventId": .object(["type": .string("string")]),
                    "title": .object(["type": .string("string"), "maxLength": .number(500)]),
                    "start": .object(["type": .string("string"), "format": .string("date-time")]),
                    "end": .object(["type": .string("string"), "format": .string("date-time")]),
                    "isAllDay": .object(["type": .string("boolean")]),
                    "location": .object(["type": .string("string"), "maxLength": .number(500)]),
                    "notes": .object(["type": .string("string"), "maxLength": .number(10_000)]),
                    "url": .object(["type": .string("string"), "format": .string("uri")]),
                    "calendarId": .object(["type": .string("string")]),
                    "span": .object(["type": .string("string"), "enum": .array([.string("thisEvent"), .string("futureEvents")])]),
                ]),
                "required": .array([.string("eventId")]),
                "additionalProperties": .bool(false),
            ])
        ),
        ToolDefinition(
            name: "calendar_event_delete",
            description: "Delete an existing calendar event by ID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "eventId": .object(["type": .string("string")]),
                    "span": .object(["type": .string("string"), "enum": .array([.string("thisEvent"), .string("futureEvents")])]),
                ]),
                "required": .array([.string("eventId")]),
                "additionalProperties": .bool(false),
            ])
        ),
    ]

    static func encode(_ tool: ToolDefinition) -> JSONValue {
        .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "inputSchema": tool.inputSchema,
        ])
    }

    static func encode(calendar: CalendarSummary) -> JSONValue {
        .object([
            "id": .string(calendar.id),
            "title": .string(calendar.title),
            "sourceTitle": .string(calendar.sourceTitle),
            "allowsContentModifications": .bool(calendar.allowsContentModifications),
        ])
    }

    static func encode(event: CalendarEvent) -> JSONValue {
        .object([
            "id": .string(event.id),
            "calendarId": .string(event.calendarID),
            "calendarTitle": .string(event.calendarTitle),
            "title": .string(event.title),
            "start": .string(DateCodec.format(event.start)),
            "end": .string(DateCodec.format(event.end)),
            "isAllDay": .bool(event.isAllDay),
            "location": event.location.map(JSONValue.string) ?? .null,
            "notes": event.notes.map(JSONValue.string) ?? .null,
            "url": event.url.map(JSONValue.string) ?? .null,
        ])
    }
}
