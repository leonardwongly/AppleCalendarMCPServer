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
        let title: String?
        let start: String?
        let end: String?
        let location: String?
        let url: String?
        let notes: String?
        let span: String?
        let json: Bool
    }

    struct DeleteCommand: Equatable, Sendable {
        let eventId: String
        let span: String?
        let json: Bool
    }

    static func parse(_ arguments: [String]) -> (CLICommand, [String: String])? {
        guard arguments.count >= 3 else { return nil }
        
        let args = Array(arguments.dropFirst())
        var positionalArgs: [String] = []
        var flags: [String: String] = [:]
        
        var i = 0
        while i < args.count {
            if args[i].hasPrefix("--") {
                let flagName = String(args[i].dropFirst(2))
                if flagName == "json" || flagName == "all-day" {
                    flags[flagName] = "true"
                    i += 1
                } else if i + 1 < args.count {
                    flags[flagName] = args[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            } else {
                positionalArgs.append(args[i])
                i += 1
            }
        }
        
        guard positionalArgs.count >= 2 else { return nil }
        
        let action = positionalArgs[0]
        let resource = positionalArgs[1]
        let json = flags["json"] == "true"
        
        let command: CLICommand?
        
        switch (action, resource) {
        case ("list", "calendars"):
            command = .list(.calendars(json: json))
            
        case ("search", "events"):
            command = .search(SearchCommand(
                calendar: flags["calendar"],
                from: flags["from"],
                to: flags["to"],
                query: flags["query"],
                json: json
            ))
            
        case ("create", "event"):
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
            guard positionalArgs.count >= 3 else { return nil }
            command = .update(UpdateCommand(
                eventId: positionalArgs[2],
                title: flags["title"],
                start: flags["start"],
                end: flags["end"],
                location: flags["location"],
                url: flags["url"],
                notes: flags["notes"],
                span: flags["span"],
                json: json
            ))
            
        case ("delete", "event"):
            guard positionalArgs.count >= 3 else { return nil }
            command = .delete(DeleteCommand(
                eventId: positionalArgs[2],
                span: flags["span"],
                json: json
            ))
            
        default:
            command = nil
        }
        
        if let cmd = command {
            return (cmd, flags)
        }
        return nil
    }
}
