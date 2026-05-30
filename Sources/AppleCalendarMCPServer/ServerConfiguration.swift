import Foundation

struct ServerConfiguration: Equatable, Sendable {
    let readOnly: Bool
    let writableCalendarIDs: Set<String>?

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ServerConfiguration {
        let readOnly = try parseBool(
            environment["APPLE_CALENDAR_MCP_READ_ONLY"],
            key: "APPLE_CALENDAR_MCP_READ_ONLY"
        ) ?? false

        let writableCalendarIDs = try parseCSVSet(
            environment["APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS"],
            key: "APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS"
        )

        return ServerConfiguration(
            readOnly: readOnly,
            writableCalendarIDs: writableCalendarIDs
        )
    }

    func allowsWrite(to calendarID: String) -> Bool {
        guard let writableCalendarIDs else {
            return true
        }
        return writableCalendarIDs.contains(calendarID)
    }

    func effectiveAllowsContentModifications(for calendarID: String, systemAllows: Bool) -> Bool {
        guard systemAllows, !readOnly else {
            return false
        }
        return allowsWrite(to: calendarID)
    }
}

private func parseBool(_ rawValue: String?, key: String) throws -> Bool? {
    guard let rawValue else { return nil }
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        throw ServerError.invalidParams("\(key) must be one of: true, false, 1, 0, yes, no, on, off")
    }
}

private func parseCSVSet(_ rawValue: String?, key: String) throws -> Set<String>? {
    guard let rawValue else { return nil }
    let values = rawValue
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !values.isEmpty else {
        throw ServerError.invalidParams("\(key) must contain at least one non-empty calendar identifier when set")
    }

    return Set(values)
}
