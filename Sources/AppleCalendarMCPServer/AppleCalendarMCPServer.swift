import Darwin
import Foundation

@main
struct AppleCalendarMCPServer {
    static func main() async {
        do {
            let mode = StartupOptions.mode()
            
            if case .help = mode {
                CLIHelpSystem.printHelp()
                Darwin.exit(0)
            }

            if case .commandHelp(let topic) = mode {
                CLIHelpSystem.handleHelp(for: topic)
                Darwin.exit(0)
            }
            
            if case .version = mode {
                CLIHelpSystem.printVersion()
                Darwin.exit(0)
            }

            if case .invalid(let message) = mode {
                FileHandle.standardError.write(Data("Error: \(message)\n\n".utf8))
                CLIHelpSystem.printHelp()
                Darwin.exit(2)
            }
            
            if case .requestCalendarAccess = mode {
                CalendarPermissionPrompt.prepareForPrompt()
                let before = EventKitAccess.authorizationStatusDescription()
                let accessMode = try await EventKitAccess.requestFullAccess()
                let after = EventKitAccess.authorizationStatusDescription()
                let message = """
                Apple Calendar full access \(accessMode.canReadEvents ? "granted" : "denied by macOS").
                Authorization status before request: \(before)
                Authorization status after request: \(after)
                """
                FileHandle.standardOutput.write(Data(message.utf8))
                Darwin.exit(accessMode.canReadEvents ? 0 : 1)
            }

            if case .cli(let command) = mode {
                let configuration = try ServerConfiguration.fromEnvironment()
                let service = EventKitCalendarService(configuration: configuration)
                let handler = CLIHandler(service: service)
                
                do {
                    try await handler.handle(command)
                    Darwin.exit(0)
                } catch {
                    let errorMessage = "\u{001B}[31m❌ Error:\u{001B}[0m \(error.localizedDescription)\n"
                    FileHandle.standardError.write(Data(errorMessage.utf8))
                    if case ServerError.invalidParams = error {
                        Darwin.exit(2)
                    }
                    Darwin.exit(1)
                }
            }

            // MCP Server mode (default)
            let configuration = try ServerConfiguration.fromEnvironment()
            let server = MCPServer(calendarService: EventKitCalendarService(configuration: configuration))
            var buffer = Data()
            let input = FileHandle.standardInput
            let output = FileHandle.standardOutput

            while true {
                let chunk = input.availableData
                if chunk.isEmpty {
                    break
                }

                buffer.append(chunk)

                do {
                    while let payload = StdioFraming.extractMessage(from: &buffer) {
                        if let response = await server.handleMessage(payload) {
                            try output.write(contentsOf: response)
                        }
                    }
                } catch {
                    let message = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}}"
                    let framed = StdioFraming.frame(Data(message.utf8))
                    try? output.write(contentsOf: framed)
                    break
                }
            }
        } catch {
            FileHandle.standardError.write(Data("Configuration error: \(error.localizedDescription)\n".utf8))
        }
    }
}
