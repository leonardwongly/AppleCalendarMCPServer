import Foundation

enum StartupMode: Equatable, Sendable {
    case mcpServer
    case requestCalendarAccess
    case cli(CLICommand)
    case help
    case version
}

enum StartupOptions {
    static let requestCalendarAccessFlag = "--request-calendar-access"
    static let cliCommands = ["list", "search", "create", "update", "delete"]

    static func mode(arguments: [String] = CommandLine.arguments) -> StartupMode {
        let args = Array(arguments.dropFirst())
        
        // Check for help and version
        if args.contains("--help") || args.contains("-h") {
            return .help
        }
        if args.contains("--version") || args.contains("-v") {
            return .version
        }
        
        if args.contains(requestCalendarAccessFlag) {
            return .requestCalendarAccess
        }
        
        // Check for CLI mode
        if args.count >= 2 {
            if cliCommands.contains(args[0]) {
                if let (command, _) = CLICommand.parse(arguments) {
                    return .cli(command)
                }
            }
        }
        
        return .mcpServer
    }
}
