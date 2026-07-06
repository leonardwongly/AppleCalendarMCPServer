import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case calendars
    case events
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendars: return "Calendars"
        case .events: return "Events"
        case .server: return "MCP Server"
        }
    }

    var systemImage: String {
        switch self {
        case .calendars: return "calendar"
        case .events: return "list.bullet.rectangle"
        case .server: return "server.rack"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selection: AppSection? = .events

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("ACP")
        } detail: {
            VStack(spacing: 0) {
                if !viewModel.hasReadAccess {
                    PermissionBanner()
                }
                detailView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                ErrorToast(message: message) { viewModel.errorMessage = nil }
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .events {
        case .calendars:
            CalendarsView()
        case .events:
            EventsView()
        case .server:
            ServerSettingsView()
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var requesting = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.needsSystemSettings ? "Calendar access was denied" : "Calendar access required")
                    .font(.headline)
                Text(bannerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.needsSystemSettings {
                Button("Open System Settings") { openCalendarPrivacySettings() }
                    .glassProminentButtonStyle()
            } else {
                Button {
                    requesting = true
                    Task {
                        await viewModel.requestAccess()
                        requesting = false
                    }
                } label: {
                    if requesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Grant Access")
                    }
                }
                .glassProminentButtonStyle()
                .disabled(requesting)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, tint: .orange)
        .padding(12)
    }

    private var bannerDetail: String {
        if viewModel.needsSystemSettings {
            return "Enable ACP under Privacy & Security ▸ Calendars, then reopen the app. (Status: \(viewModel.authStatusDescription))"
        }
        return "Status: \(viewModel.authStatusDescription). Grant access to read and manage events."
    }

    private func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ErrorToast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .foregroundStyle(.white)
                .lineLimit(3)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule(), tint: .red, interactive: true)
        .frame(maxWidth: 560)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}
