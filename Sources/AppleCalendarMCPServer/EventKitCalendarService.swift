import AppKit
import EventKit
import Foundation

actor EventKitCalendarService: CalendarServing {
    private let store: EKEventStore
    private let configuration: ServerConfiguration
    private let localFallback: LocalCalendarFallbackReading?
    private var accessMode: CalendarAccessMode = .none

    init(
        store: EKEventStore = EKEventStore(),
        configuration: ServerConfiguration = ServerConfiguration(readOnly: false, writableCalendarIDs: nil),
        localFallback: LocalCalendarFallbackReading? = LocalCalendarDatabase.defaultIfReadable()
    ) {
        self.store = store
        self.configuration = configuration
        self.localFallback = localFallback
    }

    func listCalendars() async throws -> [CalendarSummary] {
        do {
            try await ensureFullAccess()
        } catch ServerError.permissionDenied {
            guard let localFallback else {
                throw ServerError.permissionDenied
            }
            return try localFallback.listCalendars(configuration: configuration)
        }

        return store.calendars(for: .event)
            .map {
                CalendarSummary(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title,
                    allowsContentModifications: configuration.effectiveAllowsContentModifications(
                        for: $0.calendarIdentifier,
                        systemAllows: $0.allowsContentModifications
                    ),
                    color: Self.hexString(from: $0.color)
                )
            }
            .sorted { lhs, rhs in
                if lhs.sourceTitle == rhs.sourceTitle {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
            }
    }

    func searchEvents(_ request: EventSearchRequest) async throws -> [CalendarEvent] {
        do {
            try await ensureFullAccess()
        } catch ServerError.permissionDenied {
            guard let localFallback else {
                throw ServerError.permissionDenied
            }
            return try localFallback.searchEvents(request)
        }

        let calendars = try resolveCalendars(matching: request.calendarIDs)
        let predicate = store.predicateForEvents(withStart: request.start, end: request.end, calendars: calendars)
        let normalizedQuery = request.query?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return Array(store.events(matching: predicate)
            .filter { event in
                guard let normalizedQuery else { return true }
                let haystack = [event.title, event.location, event.notes, event.url?.absoluteString]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return haystack.contains(normalizedQuery)
            }
            .sorted { $0.startDate < $1.startDate }
            .compactMap(Self.mapEvent)
            .prefix(request.limit))
    }

    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await ensureWriteAccess()
        try guardWritesEnabled()
        let calendar = try resolveWritableCalendar(id: request.calendarID)

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        applyCreate(request, to: event)
        try save(event, span: .thisEvent)
        guard let mapped = Self.mapEvent(event) else {
            throw ServerError.internalError("Created event could not be reloaded")
        }
        return mapped
    }

    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await ensureFullAccess()
        try guardWritesEnabled()
        guard let event = store.event(withIdentifier: request.eventID) else {
            throw ServerError.eventNotFound(request.eventID)
        }
        try guardCalendarAllowedForWrite(id: event.calendar.calendarIdentifier)
        guard event.calendar.allowsContentModifications else {
            throw ServerError.calendarNotWritable(event.calendar.calendarIdentifier)
        }

        if let calendarID = request.calendarID {
            event.calendar = try resolveWritableCalendar(id: calendarID)
        }
        if let title = request.title { event.title = title }
        if let start = request.start { event.startDate = start }
        if let end = request.end { event.endDate = end }
        if let isAllDay = request.isAllDay { event.isAllDay = isAllDay }
        if request.clearLocation {
            event.location = nil
        } else if let location = request.location {
            event.location = location
        }
        if request.clearNotes {
            event.notes = nil
        } else if let notes = request.notes {
            event.notes = notes
        }
        if request.clearURL {
            event.url = nil
        } else if let url = request.url {
            event.url = url
        }

        guard event.endDate >= event.startDate else {
            throw ServerError.invalidParams("end must be greater than or equal to start")
        }

        try save(event, span: span(from: request.span))

        guard let refreshedID = event.eventIdentifier, let refreshed = store.event(withIdentifier: refreshedID), let mapped = Self.mapEvent(refreshed) else {
            throw ServerError.internalError("Updated event could not be reloaded")
        }
        return mapped
    }

    func deleteEvent(_ request: DeleteEventRequest) async throws {
        try await ensureFullAccess()
        try guardWritesEnabled()
        guard let event = store.event(withIdentifier: request.eventID) else {
            throw ServerError.eventNotFound(request.eventID)
        }
        try guardCalendarAllowedForWrite(id: event.calendar.calendarIdentifier)
        guard event.calendar.allowsContentModifications else {
            throw ServerError.calendarNotWritable(event.calendar.calendarIdentifier)
        }

        do {
            try store.remove(event, span: span(from: request.span), commit: true)
        } catch {
            throw ServerError.internalError("Failed to delete event: \(error.localizedDescription)")
        }
    }

    private func ensureFullAccess() async throws {
        if accessMode.canReadEvents {
            return
        }

        accessMode = try await requestFullAccess()
        guard accessMode.canReadEvents else {
            throw ServerError.permissionDenied
        }
    }

    private func ensureWriteAccess() async throws {
        if accessMode.canCreateEvents {
            return
        }

        accessMode = try await requestWriteAccess()
        guard accessMode.canCreateEvents else {
            throw ServerError.permissionDenied
        }
    }

    private func requestFullAccess() async throws -> CalendarAccessMode {
        let current = EventKitAccess.currentMode()
        if current.canReadEvents {
            return current
        }

        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .full : EventKitAccess.currentMode()
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .full : EventKitAccess.currentMode()
    }

    private func requestWriteAccess() async throws -> CalendarAccessMode {
        let current = EventKitAccess.currentMode()
        if current.canCreateEvents {
            return current
        }

        if #available(macOS 14.0, *) {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            return granted ? .writeOnly : EventKitAccess.currentMode()
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .full : EventKitAccess.currentMode()
    }

    private func resolveCalendars(matching ids: [String]?) throws -> [EKCalendar]? {
        let calendars = store.calendars(for: .event)
        guard let ids, !ids.isEmpty else {
            return calendars
        }

        let selected = calendars.filter { ids.contains($0.calendarIdentifier) }
        guard selected.count == ids.count else {
            let known = Set(selected.map(\.calendarIdentifier))
            let missing = ids.filter { !known.contains($0) }
            throw ServerError.calendarNotFound(missing.joined(separator: ", "))
        }
        return selected
    }

    private func resolveWritableCalendar(id: String) throws -> EKCalendar {
        guard let calendar = store.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) else {
            throw ServerError.calendarNotFound(id)
        }
        try guardCalendarAllowedForWrite(id: id)
        guard calendar.allowsContentModifications else {
            throw ServerError.calendarNotWritable(id)
        }
        return calendar
    }

    private func guardWritesEnabled() throws {
        if configuration.readOnly {
            throw ServerError.readOnlyMode
        }
    }

    private func guardCalendarAllowedForWrite(id: String) throws {
        if !configuration.allowsWrite(to: id) {
            throw ServerError.calendarNotWritable(id)
        }
    }

    private func applyCreate(_ request: CreateEventRequest, to event: EKEvent) {
        event.title = request.title
        event.startDate = request.start
        event.endDate = request.end
        event.isAllDay = request.isAllDay
        event.location = request.location
        event.notes = request.notes
        event.url = request.url
    }

    private func save(_ event: EKEvent, span: EKSpan) throws {
        do {
            try store.save(event, span: span, commit: true)
        } catch {
            throw ServerError.internalError("Failed to save event: \(error.localizedDescription)")
        }
    }

    private func span(from span: UpdateEventRequest.Span) -> EKSpan {
        switch span {
        case .thisEvent:
            return .thisEvent
        case .futureEvents:
            return .futureEvents
        }
    }

    private static func hexString(from color: NSColor?) -> String? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func mapEvent(_ event: EKEvent) -> CalendarEvent? {
        guard let id = event.eventIdentifier else {
            return nil
        }

        return CalendarEvent(
            id: id,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString
        )
    }
}
