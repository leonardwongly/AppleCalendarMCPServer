import SwiftUI

struct CalendarsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettingsStore

    private var groupedBySource: [(source: String, calendars: [CalendarSummary])] {
        let groups = Dictionary(grouping: viewModel.calendars, by: \.sourceTitle)
        return groups
            .map { (source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        List {
            if viewModel.calendars.isEmpty {
                EmptyStateView(
                    title: "No Calendars",
                    systemImage: "calendar",
                    message: viewModel.hasReadAccess
                        ? "No calendars were found for this account."
                        : "Grant calendar access to load your calendars."
                )
            }

            ForEach(groupedBySource, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars) { calendar in
                        CalendarRow(calendar: calendar)
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadCalendars() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
    }
}

private struct CalendarRow: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let calendar: CalendarSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.body)
                .foregroundStyle(calendar.allowsContentModifications ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.title)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if calendar.allowsContentModifications {
                        Badge(text: "Writable", color: .green)
                    } else {
                        Badge(text: "Read-only", color: .secondary)
                    }
                    Text(calendar.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if settings.restrictWritableCalendars {
                Toggle("Allow writes", isOn: Binding(
                    get: { settings.writableCalendarIDs.contains(calendar.id) },
                    set: { settings.toggleWritable(calendar.id, isOn: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Include this calendar in the MCP server's write allowlist")
                .disabled(!calendar.allowsContentModifications)
            }
        }
        .padding(.vertical, 4)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
