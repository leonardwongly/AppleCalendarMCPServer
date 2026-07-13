import Foundation

/// Builds a ready-to-paste MCP client configuration snippet for the calendar
/// server, mirroring the `env` runtime controls the server understands
/// (`APPLE_CALENDAR_MCP_READ_ONLY`, `APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS`).
enum MCPConfigBuilder {
    static let readOnlyEnvKey = "APPLE_CALENDAR_MCP_READ_ONLY"
    static let writableIDsEnvKey = "APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS"

    /// The `env` dictionary that would be passed to the launched server.
    static func environment(readOnly: Bool, writableCalendarIDs: [String]?) -> [String: String] {
        var env: [String: String] = [readOnlyEnvKey: readOnly ? "true" : "false"]
        if let writableCalendarIDs {
            let ids = writableCalendarIDs.filter { !$0.isEmpty }.sorted()
            env[writableIDsEnvKey] = ids.joined(separator: ",")
        }
        return env
    }

    /// A pretty-printed `mcpServers` JSON snippet with deterministic key order.
    static func makeConfigJSON(
        serverName: String,
        binaryPath: String,
        readOnly: Bool,
        writableCalendarIDs: [String]?
    ) -> String {
        let env = environment(readOnly: readOnly, writableCalendarIDs: writableCalendarIDs)
        let envObject = JSONValue.object(env.mapValues(JSONValue.string))

        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "apple-calendar"
            : serverName

        let serverEntry = JSONValue.object([
            "command": .string(binaryPath),
            "args": .array([.string(StartupOptions.mcpServerFlag)]),
            "env": envObject,
        ])

        let root = JSONValue.object([
            "mcpServers": .object([name: serverEntry]),
        ])

        return encode(root)
    }

    private static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
