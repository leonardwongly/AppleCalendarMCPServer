import SwiftUI

enum EventEditorMode: Identifiable {
    case create
    case edit(CalendarEvent)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let event): return "edit-\(event.id)"
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

struct EventEditorView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let mode: EventEditorMode

    @State private var title: String
    @State private var calendarID: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var urlString: String
    @State private var notes: String
    @State private var span: UpdateEventRequest.Span
    @State private var validationError: String?
    @State private var isSaving = false

    init(mode: EventEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            let now = Date()
            let start = Calendar.current.nextDate(
                after: now,
                matching: DateComponents(minute: 0),
                matchingPolicy: .nextTime
            ) ?? now
            _title = State(initialValue: "")
            _calendarID = State(initialValue: "")
            _start = State(initialValue: start)
            _end = State(initialValue: start.addingTimeInterval(3600))
            _isAllDay = State(initialValue: false)
            _location = State(initialValue: "")
            _urlString = State(initialValue: "")
            _notes = State(initialValue: "")
            _span = State(initialValue: .thisEvent)
        case .edit(let event):
            _title = State(initialValue: event.title)
            _calendarID = State(initialValue: event.calendarID)
            _start = State(initialValue: event.start)
            _end = State(initialValue: event.end)
            _isAllDay = State(initialValue: event.isAllDay)
            _location = State(initialValue: event.location ?? "")
            _urlString = State(initialValue: event.url ?? "")
            _notes = State(initialValue: event.notes ?? "")
            _span = State(initialValue: .thisEvent)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Calendar", selection: $calendarID) {
                        ForEach(viewModel.writableCalendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                }

                Section {
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: dateComponents)
                    DatePicker("Ends", selection: $end, displayedComponents: dateComponents)
                }

                Section("Details") {
                    TextField("Location", text: $location)
                    TextField("URL (http/https)", text: $urlString)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if mode.isEditing {
                    Section {
                        Picker("Apply to", selection: $span) {
                            Text("This event").tag(UpdateEventRequest.Span.thisEvent)
                            Text("This and future events").tag(UpdateEventRequest.Span.futureEvents)
                        }
                    } footer: {
                        Text("\"This and future events\" only affects recurring events.")
                            .font(.caption)
                    }
                }

                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .glassButtonStyle()
                Spacer()
                Button(mode.isEditing ? "Save Changes" : "Create Event") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .glassProminentButtonStyle()
                .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty || calendarID.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .onAppear {
            if calendarID.isEmpty {
                calendarID = viewModel.writableCalendars.first?.id ?? ""
            }
        }
    }

    private var dateComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private func save() {
        validationError = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationError = "Title is required."
            return
        }
        guard end >= start else {
            validationError = "End must be on or after start."
            return
        }

        var parsedURL: URL?
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            guard let url = URL(string: trimmedURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                validationError = "URL must be a valid http or https address."
                return
            }
            parsedURL = url
        }

        let optionalLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location
        let optionalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes

        isSaving = true
        Task {
            let success: Bool
            switch mode {
            case .create:
                success = await viewModel.createEvent(
                    CreateEventRequest(
                        calendarID: calendarID,
                        title: trimmedTitle,
                        start: start,
                        end: end,
                        isAllDay: isAllDay,
                        location: optionalLocation,
                        notes: optionalNotes,
                        url: parsedURL
                    )
                )
            case .edit(let event):
                let clearLocation = event.location != nil && optionalLocation == nil
                let clearNotes = event.notes != nil && optionalNotes == nil
                let clearURL = event.url != nil && parsedURL == nil
                success = await viewModel.updateEvent(
                    UpdateEventRequest(
                        eventID: event.id,
                        title: trimmedTitle,
                        start: start,
                        end: end,
                        isAllDay: isAllDay,
                        location: optionalLocation,
                        notes: optionalNotes,
                        url: parsedURL,
                        calendarID: calendarID == event.calendarID ? nil : calendarID,
                        span: span,
                        clearLocation: clearLocation,
                        clearNotes: clearNotes,
                        clearURL: clearURL
                    )
                )
            }
            isSaving = false
            if success { dismiss() }
        }
    }
}
