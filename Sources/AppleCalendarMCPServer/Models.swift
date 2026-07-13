import Foundation

struct CalendarSummary: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
    let allowsContentModifications: Bool
    /// Hex color string (e.g. "#RRGGBB") sourced from EventKit, when available.
    let color: String?

    init(
        id: String,
        title: String,
        sourceTitle: String,
        allowsContentModifications: Bool,
        color: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.allowsContentModifications = allowsContentModifications
        self.color = color
    }
}

struct CalendarEvent: Codable, Equatable, Sendable {
    let id: String
    let calendarID: String
    let calendarTitle: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
}

struct EventSearchRequest: Equatable, Sendable {
    let start: Date
    let end: Date
    let calendarIDs: [String]?
    let query: String?
    let limit: Int

    init(start: Date, end: Date, calendarIDs: [String]?, query: String?, limit: Int = 1_000) {
        self.start = start
        self.end = end
        self.calendarIDs = calendarIDs
        self.query = query
        self.limit = limit
    }
}

struct CreateEventRequest: Equatable, Sendable {
    let calendarID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
}

struct UpdateEventRequest: Equatable, Sendable {
    enum Span: String, Equatable, Sendable {
        case thisEvent
        case futureEvents
    }

    let eventID: String
    let title: String?
    let start: Date?
    let end: Date?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: URL?
    let calendarID: String?
    let span: Span
    let clearLocation: Bool
    let clearNotes: Bool
    let clearURL: Bool

    init(
        eventID: String,
        title: String?,
        start: Date?,
        end: Date?,
        isAllDay: Bool?,
        location: String?,
        notes: String?,
        url: URL?,
        calendarID: String?,
        span: Span,
        clearLocation: Bool = false,
        clearNotes: Bool = false,
        clearURL: Bool = false
    ) {
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
        self.calendarID = calendarID
        self.span = span
        self.clearLocation = clearLocation
        self.clearNotes = clearNotes
        self.clearURL = clearURL
    }
}

struct DeleteEventRequest: Equatable, Sendable {
    let eventID: String
    let span: UpdateEventRequest.Span
}

protocol CalendarServing: Sendable {
    func listCalendars() async throws -> [CalendarSummary]
    func searchEvents(_ request: EventSearchRequest) async throws -> [CalendarEvent]
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent
    func deleteEvent(_ request: DeleteEventRequest) async throws
}

enum ServerError: Error, LocalizedError, Equatable, Sendable {
    case invalidParams(String)
    case permissionDenied
    case readOnlyMode
    case calendarNotFound(String)
    case calendarNotWritable(String)
    case eventNotFound(String)
    case unsupported(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidParams(message):
            return message
        case .permissionDenied:
            return "Calendar access was denied by macOS."
        case .readOnlyMode:
            return "Write operations are disabled because the server is running in read-only mode."
        case let .calendarNotFound(id):
            return "Calendar not found: \(id)"
        case let .calendarNotWritable(id):
            return "Calendar does not allow modifications: \(id)"
        case let .eventNotFound(id):
            return "Event not found: \(id)"
        case let .unsupported(message):
            return message
        case let .internalError(message):
            return message
        }
    }
}
