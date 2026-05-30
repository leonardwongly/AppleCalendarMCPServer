import Foundation

enum StartupMode: Equatable, Sendable {
    case mcpServer
    case requestCalendarAccess
    case cli(CLICommand)
}

enum StartupOptions {
    static let requestCalendarAccessFlag = "--request-calendar-access"
    static let cliCommands = ["list", "search", "create", "update", "delete"]

    static func mode(arguments: [String] = CommandLine.arguments) -> StartupMode {
        if arguments.dropFirst().contains(requestCalendarAccessFlag) {
            return .requestCalendarAccess
        }
        
        // Check for CLI mode
        if arguments.count >= 3 {
            let args = Array(arguments.dropFirst())
            if cliCommands.contains(args[0]) {
                if let (command, _) = CLICommand.parse(arguments) {
                    return .cli(command)
                }
            }
        }
        
        return .mcpServer
    }
}
