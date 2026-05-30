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
        let startDate = cmd.from.flatMap(parseDate) ?? Date()
        let endDate = cmd.to.flatMap(parseDate) ?? Calendar.current.date(byAdding: .day, value: 366, to: startDate) ?? startDate

        let request = EventSearchRequest(
            start: startDate,
            end: endDate,
            calendarIDs: cmd.calendar.flatMap { [$0] },
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
            title = providedTitle
        } else {
            guard let prompted = CLIPrompt.getText(prompt: "Title") else {
                throw ServerError.invalidParams("Title is required")
            }
            title = prompted
        }

        // Determine start
        let start: Date
        if let startStr = cmd.start {
            guard let parsed = parseDate(startStr) else {
                throw ServerError.invalidParams("Invalid start date format: \(startStr)")
            }
            start = parsed
        } else {
            guard let prompted = CLIPrompt.getDate(prompt: "Start date/time") else {
                throw ServerError.invalidParams("Start date is required")
            }
            start = prompted
        }

        // Determine end
        let end: Date
        if let endStr = cmd.end {
            guard let parsed = parseDate(endStr) else {
                throw ServerError.invalidParams("Invalid end date format: \(endStr)")
            }
            end = parsed
        } else {
            guard let prompted = CLIPrompt.getDate(prompt: "End date/time") else {
                throw ServerError.invalidParams("End date is required")
            }
            end = prompted
        }

        // Optional fields - only prompt if being run interactively without arguments
        let location = cmd.location
        let urlStr = cmd.url
        let notes = cmd.notes

        let url = urlStr.flatMap { URL(string: $0) }

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
        let span = cmd.span == "futureEvents" ? UpdateEventRequest.Span.futureEvents : UpdateEventRequest.Span.thisEvent

        let request = UpdateEventRequest(
            eventID: cmd.eventId,
            title: cmd.title,
            start: cmd.start.flatMap(parseDate),
            end: cmd.end.flatMap(parseDate),
            isAllDay: nil,
            location: cmd.location,
            notes: cmd.notes,
            url: cmd.url.flatMap { URL(string: $0) },
            calendarID: nil,
            span: span
        )

        let event = try await service.updateEvent(request)
        let output = CLIOutputFormatter.formatEvent(event, json: cmd.json)
        print(output)
    }

    private func handleDeleteEvent(_ cmd: CLICommand.DeleteCommand) async throws {
        let span = cmd.span == "futureEvents" ? UpdateEventRequest.Span.futureEvents : UpdateEventRequest.Span.thisEvent

        let request = DeleteEventRequest(
            eventID: cmd.eventId,
            span: span
        )

        try await service.deleteEvent(request)
        print("Event deleted successfully")
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }
}
