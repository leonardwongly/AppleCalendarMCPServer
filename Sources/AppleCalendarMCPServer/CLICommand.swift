import Foundation

enum CLICommand: Equatable, Sendable {
    case list(ListCommand)
    case search(SearchCommand)
    case create(CreateCommand)
    case update(UpdateCommand)
    case delete(DeleteCommand)

    enum ListCommand: Equatable, Sendable {
        case calendars(json: Bool)
    }

    struct SearchCommand: Equatable, Sendable {
        let calendar: String?
        let from: String?
        let to: String?
        let query: String?
        let limit: String?
        let json: Bool
    }

    struct CreateCommand: Equatable, Sendable {
        let calendar: String?
        let title: String?
        let start: String?
        let end: String?
        let location: String?
        let url: String?
        let allDay: Bool
        let notes: String?
        let json: Bool
    }

    struct UpdateCommand: Equatable, Sendable {
        let eventId: String
        let calendar: String?
        let title: String?
        let start: String?
        let end: String?
        let location: String?
        let url: String?
        let allDay: Bool?
        let notes: String?
        let clearLocation: Bool
        let clearNotes: Bool
        let clearURL: Bool
        let span: String?
        let json: Bool
    }

    struct DeleteCommand: Equatable, Sendable {
        let eventId: String
        let span: String?
        let json: Bool
    }

    static func parse(_ arguments: [String]) -> (CLICommand, [String: String])? {
        try? parseValidated(arguments)
    }

    static func parseValidated(_ arguments: [String]) throws -> (CLICommand, [String: String]) {
        guard arguments.count >= 3 else {
            throw ServerError.invalidParams("Expected usage: ical <command> <resource> [options]")
        }

        let args = Array(arguments.dropFirst())
        var positionalArgs: [String] = []
        var flags: [String: String] = [:]

        let booleanFlags: Set<String> = ["json", "all-day", "clear-location", "clear-notes", "clear-url"]
        let valueFlags: Set<String> = [
            "calendar", "from", "to", "query", "title", "start", "end",
            "location", "url", "notes", "span", "limit",
        ]

        var i = 0
        while i < args.count {
            if args[i].hasPrefix("--") {
                let flagName = String(args[i].dropFirst(2))
                if booleanFlags.contains(flagName) {
                    flags[flagName] = "true"
                    i += 1
                } else if valueFlags.contains(flagName) {
                    guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
                        throw ServerError.invalidParams("--\(flagName) requires a value")
                    }
                    flags[flagName] = args[i + 1]
                    i += 2
                } else {
                    throw ServerError.invalidParams("Unknown option: --\(flagName)")
                }
            } else {
                positionalArgs.append(args[i])
                i += 1
            }
        }

        guard positionalArgs.count >= 2 else {
            throw ServerError.invalidParams("Expected usage: ical <command> <resource> [options]")
        }

        let action = positionalArgs[0]
        let resource = positionalArgs[1]
        let json = flags["json"] == "true"

        let command: CLICommand?
        let allowedFlags: Set<String>
        
        switch (action, resource) {
        case ("list", "calendars"):
            guard positionalArgs.count == 2 else {
                throw ServerError.invalidParams("list calendars does not accept positional arguments")
            }
            allowedFlags = ["json"]
            command = .list(.calendars(json: json))
            
        case ("search", "events"):
            guard positionalArgs.count == 2 else {
                throw ServerError.invalidParams("search events does not accept positional arguments")
            }
            allowedFlags = ["calendar", "from", "to", "query", "limit", "json"]
            command = .search(SearchCommand(
                calendar: flags["calendar"],
                from: flags["from"],
                to: flags["to"],
                query: flags["query"],
                limit: flags["limit"],
                json: json
            ))
            
        case ("create", "event"):
            guard positionalArgs.count == 2 else {
                throw ServerError.invalidParams("create event does not accept positional arguments")
            }
            allowedFlags = ["calendar", "title", "start", "end", "location", "url", "all-day", "notes", "json"]
            command = .create(CreateCommand(
                calendar: flags["calendar"],
                title: flags["title"],
                start: flags["start"],
                end: flags["end"],
                location: flags["location"],
                url: flags["url"],
                allDay: flags["all-day"] == "true",
                notes: flags["notes"],
                json: json
            ))
            
        case ("update", "event"):
            guard positionalArgs.count == 3 else {
                throw ServerError.invalidParams("Expected usage: ical update event EVENT_ID [options]")
            }
            allowedFlags = [
                "calendar", "title", "start", "end", "location", "url", "all-day", "notes",
                "clear-location", "clear-notes", "clear-url", "span", "json",
            ]
            if flags["location"] != nil, flags["clear-location"] == "true" {
                throw ServerError.invalidParams("--location cannot be combined with --clear-location")
            }
            if flags["notes"] != nil, flags["clear-notes"] == "true" {
                throw ServerError.invalidParams("--notes cannot be combined with --clear-notes")
            }
            if flags["url"] != nil, flags["clear-url"] == "true" {
                throw ServerError.invalidParams("--url cannot be combined with --clear-url")
            }
            command = .update(UpdateCommand(
                eventId: positionalArgs[2],
                calendar: flags["calendar"],
                title: flags["title"],
                start: flags["start"],
                end: flags["end"],
                location: flags["location"],
                url: flags["url"],
                allDay: flags["all-day"] == "true" ? true : nil,
                notes: flags["notes"],
                clearLocation: flags["clear-location"] == "true",
                clearNotes: flags["clear-notes"] == "true",
                clearURL: flags["clear-url"] == "true",
                span: flags["span"],
                json: json
            ))
            
        case ("delete", "event"):
            guard positionalArgs.count == 3 else {
                throw ServerError.invalidParams("Expected usage: ical delete event EVENT_ID [options]")
            }
            allowedFlags = ["span", "json"]
            command = .delete(DeleteCommand(
                eventId: positionalArgs[2],
                span: flags["span"],
                json: json
            ))
            
        default:
            command = nil
            allowedFlags = []
        }

        guard let cmd = command else {
            throw ServerError.invalidParams("Unknown command: \(action) \(resource)")
        }

        let unknownForCommand = flags.keys.filter { !allowedFlags.contains($0) }.sorted()
        guard unknownForCommand.isEmpty else {
            throw ServerError.invalidParams("Unsupported option for \(action) \(resource): --\(unknownForCommand.joined(separator: ", --"))")
        }

        return (cmd, flags)
    }
}
