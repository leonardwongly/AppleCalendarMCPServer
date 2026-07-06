import Foundation
import SwiftUI

/// Persists the management-app preferences that shape the generated MCP server
/// configuration. These settings describe how the user wants the *MCP server*
/// (the same binary, launched by an AI client) to behave — they do not restrict
/// what the management app itself can do.
@MainActor
final class AppSettingsStore: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let readOnly = "settings.readOnly"
        static let writableCalendarIDs = "settings.writableCalendarIDs"
        static let serverBinaryPath = "settings.serverBinaryPath"
        static let serverName = "settings.serverName"
        static let restrictWritableCalendars = "settings.restrictWritableCalendars"
    }

    /// When true, the generated config runs the server with writes disabled.
    @Published var readOnly: Bool {
        didSet { defaults.set(readOnly, forKey: Key.readOnly) }
    }

    /// When true, writes are limited to `writableCalendarIDs`. When false, the
    /// allowlist env var is omitted entirely (server may write to any calendar).
    @Published var restrictWritableCalendars: Bool {
        didSet { defaults.set(restrictWritableCalendars, forKey: Key.restrictWritableCalendars) }
    }

    /// Calendar identifiers allowed for writes when `restrictWritableCalendars` is on.
    @Published var writableCalendarIDs: Set<String> {
        didSet { defaults.set(Array(writableCalendarIDs), forKey: Key.writableCalendarIDs) }
    }

    /// Absolute path to the server executable used in the generated config.
    @Published var serverBinaryPath: String {
        didSet { defaults.set(serverBinaryPath, forKey: Key.serverBinaryPath) }
    }

    /// The key used for this server in the MCP client's `mcpServers` map.
    @Published var serverName: String {
        didSet { defaults.set(serverName, forKey: Key.serverName) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readOnly = defaults.object(forKey: Key.readOnly) as? Bool ?? false
        self.restrictWritableCalendars = defaults.object(forKey: Key.restrictWritableCalendars) as? Bool ?? false
        self.writableCalendarIDs = Set(defaults.stringArray(forKey: Key.writableCalendarIDs) ?? [])
        self.serverName = defaults.string(forKey: Key.serverName) ?? "apple-calendar"
        self.serverBinaryPath = defaults.string(forKey: Key.serverBinaryPath)
            ?? AppSettingsStore.defaultServerBinaryPath()
    }

    /// Best guess for the server binary path. The management app and the MCP
    /// server are the same executable, so the current binary is a valid target
    /// when launched by a client with the `--mcp-server` argument.
    static func defaultServerBinaryPath() -> String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    func toggleWritable(_ calendarID: String, isOn: Bool) {
        if isOn {
            writableCalendarIDs.insert(calendarID)
        } else {
            writableCalendarIDs.remove(calendarID)
        }
    }

    /// Drops any allowlisted IDs that no longer correspond to a known calendar so
    /// the generated config never references stale identifiers.
    func pruneWritableCalendarIDs(knownIDs: Set<String>) {
        let pruned = writableCalendarIDs.intersection(knownIDs)
        if pruned != writableCalendarIDs {
            writableCalendarIDs = pruned
        }
    }
}
