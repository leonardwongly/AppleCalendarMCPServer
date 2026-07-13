import Foundation

struct CLIHelpSystem {
    static let version = "1.2.0"

    enum Topic: Equatable, Sendable {
        case listCalendars
        case searchEvents
        case createEvent
        case updateEvent
        case deleteEvent
    }

    static func topic(arguments: [String]) -> Topic? {
        let positionalArgs = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard positionalArgs.count >= 2 else {
            return nil
        }

        switch (positionalArgs[positionalArgs.startIndex], positionalArgs[positionalArgs.index(after: positionalArgs.startIndex)]) {
        case ("list", "calendars"):
            return .listCalendars
        case ("search", "events"):
            return .searchEvents
        case ("create", "event"):
            return .createEvent
        case ("update", "event"):
            return .updateEvent
        case ("delete", "event"):
            return .deleteEvent
        default:
            return nil
        }
    }

    static func printHelp() {
        let help = """
        Apple Calendar CLI - Version \(version)

        A command-line interface to manage Apple Calendar events.

        USAGE:
            ical <command> <resource> [options]

        COMMANDS:
            list      List resources (calendars)
            search    Search for events
            create    Create a new event
            update    Update an existing event
            delete    Delete an event

        EXAMPLES:

            List all calendars:
            $ ical list calendars

            Search events in June 2026:
            $ ical search events --calendar "458E8C11-C395-4D63-AAF9-DB1BDE27FB86" \\
              --from "2026-06-01" --to "2026-06-30"

            Create an event:
            $ ical create event \\
              --calendar "458E8C11-C395-4D63-AAF9-DB1BDE27FB86" \\
              --title "Team Meeting" \\
              --start "2026-06-15 10:00" \\
              --end "2026-06-15 11:00" \\
              --location "Conference Room A" \\
              --url "https://meet.example.com"

            Update an event:
            $ ical update event "event-id" --title "Updated Title"

            Delete an event:
            $ ical delete event "event-id"

            Get JSON output:
            $ ical list calendars --json

        OPTIONS:
            --help              Show this help message
            --version           Show version
            --mcp-server        Start MCP stdio server mode
            --json              Output as JSON instead of table format

        COMMAND HELP:
            ical list calendars --help
            ical search events --help
            ical create event --help
            ical update event --help
            ical delete event --help

        For more information, visit: https://github.com/leonardwongly/AppleCalendarMCPServer
        """
        print(help)
    }

    static func printVersion() {
        print("ical version \(version)")
    }

    static func printListCalendarsHelp() {
        let help = """
        List all available calendars

        USAGE:
            ical list calendars [options]

        OPTIONS:
            --json              Output as JSON instead of table format
            --help              Show this help message

        EXAMPLES:
            $ ical list calendars
            $ ical list calendars --json
        """
        print(help)
    }

    static func printSearchEventsHelp() {
        let help = """
        Search for events in calendar

        USAGE:
            ical search events [options]

        OPTIONS:
            --calendar ID       Calendar ID to search in (optional)
            --from DATE         Start date (YYYY-MM-DD, default: today)
            --to DATE           End date (YYYY-MM-DD, default: +366 days)
            --query TEXT        Text to search for
            --limit NUMBER      Maximum results, 1-5000 (default: 1000)
            --json              Output as JSON instead of table format
            --help              Show this help message

        EXAMPLES:
            $ ical search events --calendar "458E8C11-C395-4D63-AAF9-DB1BDE27FB86"
            $ ical search events --query "meeting" --from "2026-06-01" --to "2026-06-30"
            $ ical search events --json
        """
        print(help)
    }

    static func printCreateEventHelp() {
        let help = """
        Create a new calendar event

        USAGE:
            ical create event [options]

        REQUIRED OPTIONS:
            --calendar ID       Calendar ID (if not provided, you'll be prompted)
            --title TEXT        Event title
            --start DATETIME    Start date/time (YYYY-MM-DD HH:MM or YYYY-MM-DD)
            --end DATETIME      End date/time (YYYY-MM-DD HH:MM or YYYY-MM-DD)

        OPTIONAL OPTIONS:
            --location TEXT     Event location
            --url URL           Event URL (http or https only)
            --all-day           Create as all-day event
            --notes TEXT        Event notes/description
            --json              Output as JSON instead of table format
            --help              Show this help message

        EXAMPLES:
            $ ical create event --calendar "ID" --title "Meeting" \\
              --start "2026-06-15 10:00" --end "2026-06-15 11:00"

            $ ical create event --title "Birthday" --all-day \\
              --start "2026-06-20" --end "2026-06-20"

            $ ical create event --calendar "ID" --title "Lunch" \\
              --start "2026-06-15 12:00" --end "2026-06-15 13:00" \\
              --location "Downtown" --url "https://restaurant.com"
        """
        print(help)
    }

    static func printUpdateEventHelp() {
        let help = """
        Update an existing calendar event

        USAGE:
            ical update event EVENT_ID [options]

        REQUIRED:
            EVENT_ID            Event identifier (required)

        OPTIONAL:
            --calendar ID       Move the event to another calendar (by ID)
            --title TEXT        New event title
            --start DATETIME    New start date/time
            --end DATETIME      New end date/time
            --location TEXT     New location
            --clear-location    Remove the existing location
            --url URL           New URL
            --clear-url         Remove the existing URL
            --all-day           Convert the event to an all-day event
            --notes TEXT        New notes
            --clear-notes       Remove the existing notes
            --span MODE         Update mode: thisEvent (default) or futureEvents
            --json              Output as JSON instead of table format
            --help              Show this help message

        EXAMPLES:
            $ ical update event "event-id" --title "Updated Title"
            $ ical update event "event-id" --location "New Room"
            $ ical update event "event-id" --clear-location --clear-url
            $ ical update event "event-id" --calendar "OTHER-CALENDAR-ID"
            $ ical update event "event-id" --span futureEvents --title "Series Title"
        """
        print(help)
    }

    static func printDeleteEventHelp() {
        let help = """
        Delete a calendar event

        USAGE:
            ical delete event EVENT_ID [options]

        REQUIRED:
            EVENT_ID            Event identifier (required)

        OPTIONS:
            --span MODE         Delete mode: thisEvent (default) or futureEvents
            --json              Output as JSON instead of table format
            --help              Show this help message

        EXAMPLES:
            $ ical delete event "event-id"
            $ ical delete event "event-id" --span futureEvents
        """
        print(help)
    }

    static func handleHelp(for topic: Topic) {
        switch topic {
        case .listCalendars:
            printListCalendarsHelp()
        case .searchEvents:
            printSearchEventsHelp()
        case .createEvent:
            printCreateEventHelp()
        case .updateEvent:
            printUpdateEventHelp()
        case .deleteEvent:
            printDeleteEventHelp()
        }
    }
}
