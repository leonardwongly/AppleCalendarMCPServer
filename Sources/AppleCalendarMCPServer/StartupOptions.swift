import Darwin
import Foundation

enum StartupMode: Equatable, Sendable {
    case mcpServer
    case requestCalendarAccess
    case cli(CLICommand)
    case help
    case commandHelp(CLIHelpSystem.Topic)
    case version
    case invalid(String)
}

enum StartupOptions {
    static let requestCalendarAccessFlag = "--request-calendar-access"
    static let mcpServerFlag = "--mcp-server"
    static let cliCommands = ["list", "search", "create", "update", "delete"]

    static func mode(
        arguments: [String] = CommandLine.arguments,
        standardInputIsTerminal: Bool = StartupOptions.standardInputIsTerminal()
    ) -> StartupMode {
        let args = Array(arguments.dropFirst())
        
        // Check for help and version
        if args.contains("--help") || args.contains("-h") {
            if let topic = CLIHelpSystem.topic(arguments: arguments) {
                return .commandHelp(topic)
            }
            return .help
        }
        if args.contains("--version") || args.contains("-v") {
            return .version
        }
        
        if args.contains(requestCalendarAccessFlag) {
            return .requestCalendarAccess
        }

        if args.contains(mcpServerFlag) {
            guard args.count == 1 else {
                return .invalid("\(mcpServerFlag) cannot be combined with other commands or options")
            }
            return .mcpServer
        }
        
        // Check for CLI mode
        if args.count >= 2 {
            if cliCommands.contains(args[0]) {
                do {
                    let (command, _) = try CLICommand.parseValidated(arguments)
                    return .cli(command)
                } catch {
                    return .invalid(error.localizedDescription)
                }
            }
        }

        if !args.isEmpty {
            return .invalid("Unknown command or option: \(args[0])")
        }
        
        return standardInputIsTerminal ? .help : .mcpServer
    }

    private static func standardInputIsTerminal() -> Bool {
        isatty(STDIN_FILENO) == 1
    }
}
