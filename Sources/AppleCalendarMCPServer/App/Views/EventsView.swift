import SwiftUI

struct EventsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var editorMode: EventEditorMode?
    @State private var eventPendingDelete: CalendarEvent?

    var body: some View {
        VStack(spacing: 0) {
            searchControls
            Divider()
            eventList
        }
        .navigationTitle("Events")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorMode = .create
                } label: {
                    Label("New Event", systemImage: "plus")
                }
                .disabled(!viewModel.hasReadAccess || viewModel.writableCalendars.isEmpty)
                .help(viewModel.writableCalendars.isEmpty
                    ? "No writable calendars available"
                    : "Create a new event")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $editorMode) { mode in
            EventEditorView(mode: mode)
                .environmentObject(viewModel)
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: Binding(get: { eventPendingDelete != nil }, set: { if !$0 { eventPendingDelete = nil } }),
            presenting: eventPendingDelete
        ) { event in
            Button("Delete \"\(event.title)\"", role: .destructive) {
                Task { await viewModel.deleteEvent(event) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the event from your calendar.")
        }
    }

    // MARK: - Search controls

    private var searchControls: some View {
        VStack(spacing: 10) {
            HStack {
                DatePicker("From", selection: $viewModel.searchStart, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                DatePicker("To", selection: $viewModel.searchEnd, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
            }
            HStack(spacing: 10) {
                TextField("Search text (optional)", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.searchEvents() } }

                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        calendarFilterMenu

                        Button {
                            Task { await viewModel.searchEvents() }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Search", systemImage: "magnifyingglass")
                            }
                        }
                        .glassProminentButtonStyle()
                        .disabled(!viewModel.hasReadAccess || viewModel.isLoading)
                        .keyboardShortcut("r", modifiers: .command)
                    }
                }
            }
        }
        .padding(12)
    }

    private var calendarFilterMenu: some View {
        Menu {
            Button("All calendars") { viewModel.selectedCalendarIDs.removeAll() }
            Divider()
            ForEach(viewModel.calendars) { calendar in
                Button {
                    if viewModel.selectedCalendarIDs.contains(calendar.id) {
                        viewModel.selectedCalendarIDs.remove(calendar.id)
                    } else {
                        viewModel.selectedCalendarIDs.insert(calendar.id)
                    }
                } label: {
                    Label(
                        calendar.title,
                        systemImage: viewModel.selectedCalendarIDs.contains(calendar.id) ? "checkmark" : ""
                    )
                }
            }
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .glassButtonStyle()
        .fixedSize()
    }

    private var filterLabel: String {
        let count = viewModel.selectedCalendarIDs.count
        return count == 0 ? "All calendars" : "\(count) selected"
    }

    // MARK: - Event list

    @ViewBuilder
    private var eventList: some View {
        if viewModel.events.isEmpty {
            EmptyStateView(
                title: "No Events",
                systemImage: "calendar.badge.exclamationmark",
                message: "Adjust the date range or filters, then search."
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.events) { event in
                    EventRow(event: event, calendarColor: viewModel.calendar(withID: event.calendarID)?.color)
                        .contentShape(Rectangle())
                        .onTapGesture { editorMode = .edit(event) }
                        .contextMenu {
                            Button("Edit") { editorMode = .edit(event) }
                            Button("Delete", role: .destructive) { eventPendingDelete = event }
                        }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    var calendarColor: String? = nil

    private var accent: Color { Color(hex: calendarColor) ?? .accentColor }

    var body: some View {
        HStack(spacing: 14) {
            dateChip
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "(Untitled)" : event.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.timeText(for: event))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        CalendarColorDot(hex: calendarColor, size: 8)
                        Text(event.calendarTitle)
                    }
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var dateChip: some View {
        VStack(spacing: 1) {
            Text(event.start.formatted(.dateTime.month(.abbreviated)))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(accent)
            Text(event.start.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 46, height: 46)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.35))
        )
    }

    static func timeText(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
        let end = sameDay
            ? event.end.formatted(date: .omitted, time: .shortened)
            : event.end.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
}
