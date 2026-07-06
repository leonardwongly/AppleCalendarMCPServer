import AppKit
import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var didCopy = false

    private var generatedConfig: String {
        MCPConfigBuilder.makeConfigJSON(
            serverName: settings.serverName,
            binaryPath: settings.serverBinaryPath,
            readOnly: settings.readOnly,
            writableCalendarIDs: settings.restrictWritableCalendars
                ? Array(settings.writableCalendarIDs)
                : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader("MCP Server", subtitle: "Permission, runtime policy, and client configuration")
                permissionSection
                runtimeSection
                identitySection
                configSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("MCP Server")
    }

    // MARK: - Permission

    private var permissionSection: some View {
        SectionCard("Calendar Permission", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.hasReadAccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.hasReadAccess ? .green : .orange)
                        .imageScale(.large)
                    Text(viewModel.authStatusDescription)
                        .font(.body.monospaced())
                    Spacer()
                }
                Text("The server and this app share one macOS Calendar permission grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Request Access") {
                            Task { await viewModel.requestAccess() }
                        }
                        .glassProminentButtonStyle()
                        Button("Refresh Status") { viewModel.refreshPermissionStatus() }
                            .glassButtonStyle()
                        Button("Open System Settings") { openCalendarPrivacySettings() }
                            .glassButtonStyle()
                    }
                }
            }
        }
    }

    // MARK: - Runtime controls

    private var runtimeSection: some View {
        SectionCard("Runtime Controls", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.readOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read-only mode")
                        Text("Blocks create, update, and delete (APPLE_CALENDAR_MCP_READ_ONLY).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $settings.restrictWritableCalendars) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restrict writes to an allowlist")
                        Text("Only allowlisted calendars accept writes (APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.readOnly)

                if settings.restrictWritableCalendars {
                    let count = settings.writableCalendarIDs.count
                    Label(
                        count == 0
                            ? "No calendars allowlisted yet — enable them per-calendar in the Calendars tab."
                            : "\(count) calendar\(count == 1 ? "" : "s") allowlisted for writes.",
                        systemImage: count == 0 ? "exclamationmark.circle" : "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(count == 0 ? .orange : .secondary)
                }
            }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        SectionCard("Server Identity", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Server name") {
                    TextField("apple-calendar", text: $settings.serverName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                LabeledContent("Binary path") {
                    HStack(spacing: 6) {
                        TextField("Path to server executable", text: $settings.serverBinaryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                        Button("Choose…") { chooseBinary() }
                            .glassButtonStyle()
                        Button("Use This App") {
                            settings.serverBinaryPath = AppSettingsStore.defaultServerBinaryPath()
                        }
                        .glassButtonStyle()
                    }
                }
                Text("The client launches this binary with the \(StartupOptions.mcpServerFlag) argument.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Generated config

    private var configSection: some View {
        SectionCard("MCP Client Configuration", systemImage: "curlybraces.square") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste this into your MCP client configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    Text(generatedConfig)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary)
                )

                Button {
                    copyConfig()
                } label: {
                    Label(didCopy ? "Copied!" : "Copy to Clipboard",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .glassProminentButtonStyle()
            }
        }
    }

    // MARK: - Actions

    private func copyConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedConfig, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }

    private func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose the AppleCalendarMCPServer executable"
        if panel.runModal() == .OK, let url = panel.url {
            settings.serverBinaryPath = url.path
        }
    }
}
