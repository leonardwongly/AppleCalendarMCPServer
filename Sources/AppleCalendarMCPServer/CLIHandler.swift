import Foundation

struct CLIHandler {
    let service: CalendarServing

    func handle(_ command: CLICommand) async throws {
        switch command {
        case .list(.calendars(let json)):
            try await handleListCalendars(json: json)
            
        case .search(let cmd):
            try await handleSearchEvents(cmd)
            
        case .create(let cmd):
            try await handleCreateEvent(cmd)
            
        case .update(let cmd):
            try await handleUpdateEvent(cmd)
            
        case .delete(let cmd):
            try await handleDeleteEvent(cmd)
        }
    }

    private func handleListCalendars(json: Bool) async throws {
        let calendars = try await service.listCalendars()
        let output = CLIOutputFormatter.formatCalendars(calendars, json: json)
        print(output)
    }

    private func handleSearchEvents(_ cmd: CLICommand.SearchCommand) async throws {
        let startDate = try cmd.from.map { try parseDate($0, fieldName: "from") } ?? Date()
        let endDate = try cmd.to.map { try parseDate($0, fieldName: "to") }
            ?? Calendar.current.date(byAdding: .day, value: 366, to: startDate)
            ?? startDate
        try validateDateRange(start: startDate, end: endDate)

        let request = EventSearchRequest(
            start: startDate,
            end: endDate,
            calendarIDs: cmd.calendar.map { [$0] },
            query: cmd.query
        )

        let events = try await service.searchEvents(request)
        let output = CLIOutputFormatter.formatEvents(events, json: cmd.json)
        print(output)
    }

    private func handleCreateEvent(_ cmd: CLICommand.CreateCommand) async throws {
        let calendars = try await service.listCalendars()

        // Determine calendar
        let calendar: CalendarSummary
        if let calendarId = cmd.calendar {
            guard let found = calendars.first(where: { $0.id == calendarId }) else {
                throw ServerError.calendarNotFound(calendarId)
            }
            calendar = found
        } else {
            guard let selected = CLIPrompt.selectCalendar(from: calendars) else {
                throw ServerError.calendarNotFound("No calendar selected")
            }
            calendar = selected
        }

        guard calendar.allowsContentModifications else {
            throw ServerError.calendarNotWritable(calendar.id)
        }

        // Determine title
        let title: String
        if let providedTitle = cmd.title {
            title = try validateRequiredText(providedTitle, fieldName: "title", maxLength: 500)
        } else {
            guard let prompted = CLIPrompt.getText(prompt: "Title") else {
                throw ServerError.invalidParams("Title is required")
            }
            title = try validateRequiredText(prompted, fieldName: "title", maxLength: 500)
        }

        // Determine start
        let start: Date
        if let startStr = cmd.start {
            start = try parseDate(startStr, fieldName: "start")
        } else {
            guard let prompted = CLIPrompt.getDate(prompt: "Start date/time") else {
                throw ServerError.invalidParams("Start date is required")
            }
            start = prompted
        }

        // Determine end
        let end: Date
        if let endStr = cmd.end {
            end = try parseDate(endStr, fieldName: "end")
        } else {
            guard let prompted = CLIPrompt.getDate(prompt: "End date/time") else {
                throw ServerError.invalidParams("End date is required")
            }
            end = prompted
        }
        try validateStartEnd(start: start, end: end)

        // Optional fields - only prompt if being run interactively without arguments
        let location = try cmd.location.map { try validateOptionalText($0, fieldName: "location", maxLength: 500) }
        let notes = try cmd.notes.map { try validateOptionalText($0, fieldName: "notes", maxLength: 10_000) }
        let url = try parseURL(cmd.url)

        let request = CreateEventRequest(
            calendarID: calendar.id,
            title: title,
            start: start,
            end: end,
            isAllDay: cmd.allDay,
            location: location,
            notes: notes,
            url: url
        )

        let event = try await service.createEvent(request)
        let output = CLIOutputFormatter.formatEvent(event, json: cmd.json)
        print(output)
    }

    private func handleUpdateEvent(_ cmd: CLICommand.UpdateCommand) async throws {
        let span = try parseSpan(cmd.span)
        let title = try cmd.title.map { try validateOptionalText($0, fieldName: "title", maxLength: 500) }
        let start = try cmd.start.map { try parseDate($0, fieldName: "start") }
        let end = try cmd.end.map { try parseDate($0, fieldName: "end") }
        if let start, let end {
            try validateStartEnd(start: start, end: end)
        }
        let location = try cmd.location.map { try validateOptionalText($0, fieldName: "location", maxLength: 500) }
        let notes = try cmd.notes.map { try validateOptionalText($0, fieldName: "notes", maxLength: 10_000) }
        let url = try parseURL(cmd.url)

        guard title != nil || start != nil || end != nil || location != nil || notes != nil || url != nil else {
            throw ServerError.invalidParams("At least one mutable field must be provided for update")
        }

        let request = UpdateEventRequest(
            eventID: cmd.eventId,
            title: title,
            start: start,
            end: end,
            isAllDay: nil,
            location: location,
            notes: notes,
            url: url,
            calendarID: nil,
            span: span
        )

        let event = try await service.updateEvent(request)
        let output = CLIOutputFormatter.formatEvent(event, json: cmd.json)
        print(output)
    }

    private func handleDeleteEvent(_ cmd: CLICommand.DeleteCommand) async throws {
        let span = try parseSpan(cmd.span)

        let request = DeleteEventRequest(
            eventID: cmd.eventId,
            span: span
        )

        try await service.deleteEvent(request)
        print(CLIOutputFormatter.formatDelete(eventID: cmd.eventId, json: cmd.json))
    }

    private func parseDate(_ dateString: String, fieldName: String) throws -> Date {
        if let date = DateCodec.parse(dateString) {
            return date
        }

        let formatters = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        throw ServerError.invalidParams("\(fieldName) must be a valid date or ISO 8601 date-time string")
    }

    private func parseURL(_ value: String?) throws -> URL? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw ServerError.invalidParams("url must be a valid http or https URL")
        }
        return url
    }

    private func parseSpan(_ value: String?) throws -> UpdateEventRequest.Span {
        let raw = value ?? UpdateEventRequest.Span.thisEvent.rawValue
        guard let span = UpdateEventRequest.Span(rawValue: raw) else {
            throw ServerError.invalidParams("span must be one of: thisEvent, futureEvents")
        }
        return span
    }

    private func validateRequiredText(_ value: String, fieldName: String, maxLength: Int) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServerError.invalidParams("\(fieldName) is required")
        }
        return try validateOptionalText(trimmed, fieldName: fieldName, maxLength: maxLength)
    }

    private func validateOptionalText(_ value: String, fieldName: String, maxLength: Int) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else {
            throw ServerError.invalidParams("\(fieldName) must be at most \(maxLength) characters")
        }
        return trimmed
    }

    private func validateStartEnd(start: Date, end: Date) throws {
        guard end >= start else {
            throw ServerError.invalidParams("end must be greater than or equal to start")
        }
    }

    private func validateDateRange(start: Date, end: Date) throws {
        try validateStartEnd(start: start, end: end)
        guard end.timeIntervalSince(start) <= 366 * 24 * 60 * 60 else {
            throw ServerError.invalidParams("Date range must not exceed 366 days")
        }
    }
}
