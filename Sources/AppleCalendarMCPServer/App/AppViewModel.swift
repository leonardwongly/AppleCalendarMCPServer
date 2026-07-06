import Combine
import EventKit
import Foundation

/// Main-actor view model that bridges SwiftUI to the shared, actor-isolated
/// ``EventKitCalendarService``. The management app always talks to the service
/// with full capability; the read-only / allowlist preferences live in
/// ``AppSettingsStore`` and only shape the *generated MCP config*.
@MainActor
final class AppViewModel: ObservableObject {
    private let service: EventKitCalendarService

    @Published var accessMode: CalendarAccessMode = EventKitAccess.currentMode()
    @Published var authStatusDescription: String = EventKitAccess.authorizationStatusDescription()

    /// True when access was explicitly denied or restricted. macOS will not
    /// re-prompt in this state, so the user must enable access in System Settings.
    @Published var needsSystemSettings = false

    @Published var calendars: [CalendarSummary] = []
    @Published var events: [CalendarEvent] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    // Event search controls.
    @Published var searchStart: Date
    @Published var searchEnd: Date
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var query: String = ""

    init(service: EventKitCalendarService = EventKitCalendarService(
        configuration: ServerConfiguration(readOnly: false, writableCalendarIDs: nil)
    )) {
        self.service = service
        let now = Date()
        let calendar = Calendar.current
        self.searchStart = calendar.startOfDay(for: now)
        self.searchEnd = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: now)) ?? now
    }

    var hasReadAccess: Bool { accessMode.canReadEvents }

    var writableCalendars: [CalendarSummary] {
        calendars.filter(\.allowsContentModifications)
    }

    func calendar(withID id: String) -> CalendarSummary? {
        calendars.first { $0.id == id }
    }

    // MARK: - Permissions

    func refreshPermissionStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        accessMode = EventKitAccess.mode(for: status)
        authStatusDescription = EventKitAccess.authorizationStatusDescription()
        needsSystemSettings = (status == .denied || status == .restricted)
    }

    func requestAccess() async {
        errorMessage = nil
        do {
            accessMode = try await EventKitAccess.requestFullAccess()
            refreshPermissionStatus()
            if accessMode.canReadEvents {
                await loadCalendars()
                await searchEvents()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Loading

    func loadInitialDataIfPossible() async {
        refreshPermissionStatus()
        // Trigger the macOS prompt automatically on first launch. Once a decision
        // exists (granted/denied), macOS won't prompt again, so we don't retry.
        if !hasReadAccess, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            await requestAccess()
        }
        if hasReadAccess {
            await loadCalendars()
            await searchEvents()
        }
    }

    func loadCalendars() async {
        await run {
            self.calendars = try await self.service.listCalendars()
        }
    }

    func searchEvents() async {
        guard searchEnd >= searchStart else {
            errorMessage = "End date must be on or after the start date."
            return
        }
        let request = EventSearchRequest(
            start: searchStart,
            end: searchEnd,
            calendarIDs: selectedCalendarIDs.isEmpty ? nil : Array(selectedCalendarIDs),
            query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query
        )
        await run {
            self.events = try await self.service.searchEvents(request)
        }
    }

    // MARK: - Mutations

    @discardableResult
    func createEvent(_ request: CreateEventRequest) async -> Bool {
        await run {
            _ = try await self.service.createEvent(request)
            self.events = try await self.service.searchEvents(self.currentSearchRequest())
        }
    }

    @discardableResult
    func updateEvent(_ request: UpdateEventRequest) async -> Bool {
        await run {
            _ = try await self.service.updateEvent(request)
            self.events = try await self.service.searchEvents(self.currentSearchRequest())
        }
    }

    @discardableResult
    func deleteEvent(_ event: CalendarEvent, span: UpdateEventRequest.Span = .thisEvent) async -> Bool {
        await run {
            try await self.service.deleteEvent(DeleteEventRequest(eventID: event.id, span: span))
            self.events.removeAll { $0.id == event.id }
        }
    }

    // MARK: - Helpers

    private func currentSearchRequest() -> EventSearchRequest {
        EventSearchRequest(
            start: searchStart,
            end: searchEnd,
            calendarIDs: selectedCalendarIDs.isEmpty ? nil : Array(selectedCalendarIDs),
            query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query
        )
    }

    /// Runs an async operation with unified loading + error handling.
    /// Returns `true` when the operation completed without throwing.
    @discardableResult
    private func run(_ operation: @escaping () async throws -> Void) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
