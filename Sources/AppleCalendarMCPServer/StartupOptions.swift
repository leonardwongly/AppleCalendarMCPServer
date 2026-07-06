import Darwin
import Foundation

enum StartupMode: Equatable, Sendable {
    case mcpServer
    case requestCalendarAccess
    case cli(CLICommand)
    case app
    case help
    case commandHelp(CLIHelpSystem.Topic)
    case version
    case invalid(String)
}

enum StartupOptions {
    static let requestCalendarAccessFlag = "--request-calendar-access"
    static let mcpServerFlag = "--mcp-server"
    static let appModeFlag = "--app"
    static let appModeEnvironmentKey = "APPLE_CALENDAR_APP_MODE"
    static let cliCommands = ["list", "search", "create", "update", "delete"]

    static func mode(
        arguments: [String] = CommandLine.arguments,
        standardInputIsTerminal: Bool = StartupOptions.standardInputIsTerminal(),
        appModeEnvironmentEnabled: Bool = StartupOptions.appModeEnvironmentEnabled()
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

        // GUI management app: explicit --app flag always wins. The bundled app also
        // sets APPLE_CALENDAR_APP_MODE via LSEnvironment; only honor the env variable
        // when no other arguments are present so it never hijacks a CLI invocation
        // that inherits the variable from the surrounding shell.
        if args.contains(appModeFlag) || (appModeEnvironmentEnabled && args.isEmpty) {
            return .app
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

    static func appModeEnvironmentEnabled(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let raw = environment[appModeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(raw)
    }
}
