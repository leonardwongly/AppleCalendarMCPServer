import Foundation

struct CLIOutputFormatter {
    static func formatCalendars(_ calendars: [CalendarSummary], json: Bool) -> String {
        if json {
            return formatCalendarsJSON(calendars)
        } else {
            return formatCalendarsTable(calendars)
        }
    }

    static func formatEvents(_ events: [CalendarEvent], json: Bool) -> String {
        if json {
            return formatEventsJSON(events)
        } else {
            return formatEventsTable(events)
        }
    }

    static func formatEvent(_ event: CalendarEvent, json: Bool) -> String {
        if json {
            return formatEventJSON(event)
        } else {
            return formatEventTable(event)
        }
    }

    // MARK: - JSON Formatters

    private static func formatCalendarsJSON(_ calendars: [CalendarSummary]) -> String {
        let data: [String: Any] = [
            "calendars": calendars.map { calendar in
                [
                    "id": calendar.id,
                    "title": calendar.title,
                    "sourceTitle": calendar.sourceTitle,
                    "allowsContentModifications": calendar.allowsContentModifications,
                ]
            }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private static func formatEventsJSON(_ events: [CalendarEvent]) -> String {
        let data: [String: Any] = [
            "events": events.map { event in
                [
                    "id": event.id,
                    "calendarID": event.calendarID,
                    "calendarTitle": event.calendarTitle,
                    "title": event.title,
                    "start": ISO8601DateFormatter().string(from: event.start),
                    "end": ISO8601DateFormatter().string(from: event.end),
                    "isAllDay": event.isAllDay,
                    "location": event.location as Any,
                    "notes": event.notes as Any,
                    "url": event.url as Any,
                ]
            }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private static func formatEventJSON(_ event: CalendarEvent) -> String {
        let data: [String: Any] = [
            "id": event.id,
            "calendarID": event.calendarID,
            "calendarTitle": event.calendarTitle,
            "title": event.title,
            "start": ISO8601DateFormatter().string(from: event.start),
            "end": ISO8601DateFormatter().string(from: event.end),
            "isAllDay": event.isAllDay,
            "location": event.location as Any,
            "notes": event.notes as Any,
            "url": event.url as Any,
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    // MARK: - Table Formatters

    private static func formatCalendarsTable(_ calendars: [CalendarSummary]) -> String {
        if calendars.isEmpty {
            return "No calendars found"
        }

        var lines: [String] = []
        lines.append("CALENDARS:")
        lines.append("")

        let titleWidth = max(calendars.map { $0.title.count }.max() ?? 0, 20)
        let idWidth = max(calendars.map { $0.id.count }.max() ?? 0, 30)
        let writableWidth = 10

        lines.append(
            "Title".padding(toLength: titleWidth, withPad: " ", startingAt: 0) + "  " +
            "ID".padding(toLength: idWidth, withPad: " ", startingAt: 0) + "  " +
            "Writable"
        )
        lines.append(String(repeating: "─", count: titleWidth + idWidth + writableWidth + 4))

        for calendar in calendars {
            let writable = calendar.allowsContentModifications ? "Yes" : "No"
            lines.append(
                calendar.title.padding(toLength: titleWidth, withPad: " ", startingAt: 0) + "  " +
                calendar.id.padding(toLength: idWidth, withPad: " ", startingAt: 0) + "  " +
                writable
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func formatEventsTable(_ events: [CalendarEvent]) -> String {
        if events.isEmpty {
            return "No events found"
        }

        var lines: [String] = []
        lines.append("EVENTS (\(events.count) results):")
        lines.append("")

        let titleWidth = max(events.map { $0.title.count }.max() ?? 0, 25)
        let calendarWidth = max(events.map { $0.calendarTitle.count }.max() ?? 0, 15)
        let dateTimeWidth = 20

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        lines.append(
            "Title".padding(toLength: titleWidth, withPad: " ", startingAt: 0) + "  " +
            "Start".padding(toLength: dateTimeWidth, withPad: " ", startingAt: 0) + "  " +
            "End".padding(toLength: dateTimeWidth, withPad: " ", startingAt: 0) + "  " +
            "Calendar"
        )
        lines.append(String(repeating: "─", count: titleWidth + dateTimeWidth + dateTimeWidth + calendarWidth + 6))

        for event in events {
            let startStr = dateFormatter.string(from: event.start)
            let endStr = dateFormatter.string(from: event.end)
            lines.append(
                event.title.padding(toLength: titleWidth, withPad: " ", startingAt: 0) + "  " +
                startStr.padding(toLength: dateTimeWidth, withPad: " ", startingAt: 0) + "  " +
                endStr.padding(toLength: dateTimeWidth, withPad: " ", startingAt: 0) + "  " +
                event.calendarTitle
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func formatEventTable(_ event: CalendarEvent) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("EVENT:")
        lines.append("")
        lines.append("Title:    \(event.title)")
        lines.append("Calendar: \(event.calendarTitle)")
        lines.append("Start:    \(dateFormatter.string(from: event.start))")
        lines.append("End:      \(dateFormatter.string(from: event.end))")
        lines.append("All Day:  \(event.isAllDay ? "Yes" : "No")")
        if let location = event.location {
            lines.append("Location: \(location)")
        }
        if let url = event.url {
            lines.append("URL:      \(url)")
        }
        if let notes = event.notes {
            lines.append("Notes:    \(notes)")
        }

        return lines.joined(separator: "\n")
    }
}
