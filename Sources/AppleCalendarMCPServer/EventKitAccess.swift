import EventKit
import Foundation

enum CalendarAccessMode: Equatable, Sendable {
    case none
    case writeOnly
    case full

    var canReadEvents: Bool {
        self == .full
    }

    var canCreateEvents: Bool {
        self == .full || self == .writeOnly
    }
}

enum EventKitAccess {
    static func authorizationStatusDescription() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .fullAccess:
            return "fullAccess"
        case .writeOnly:
            return "writeOnly"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }

    static func currentMode() -> CalendarAccessMode {
        mode(for: EKEventStore.authorizationStatus(for: .event))
    }

    static func mode(for status: EKAuthorizationStatus) -> CalendarAccessMode {
        switch status {
        case .fullAccess, .authorized:
            return .full
        case .writeOnly:
            return .writeOnly
        case .notDetermined, .restricted, .denied:
            return .none
        @unknown default:
            return .none
        }
    }

    static func requestFullAccess(store: EKEventStore = EKEventStore()) async throws -> CalendarAccessMode {
        let current = currentMode()
        if current.canReadEvents {
            return current
        }

        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .full : currentMode()
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .full : currentMode()
    }

    static func requestWriteAccess(store: EKEventStore = EKEventStore()) async throws -> CalendarAccessMode {
        let current = currentMode()
        if current.canCreateEvents {
            return current
        }

        if #available(macOS 14.0, *) {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            return granted ? .writeOnly : currentMode()
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .full : currentMode()
    }
}
