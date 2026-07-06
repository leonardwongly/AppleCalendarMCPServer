import Foundation

// The domain models already expose a stable `id: String`. Conforming them to
// Identifiable in the app layer keeps SwiftUI-specific concerns out of the
// shared model definitions while enabling `ForEach`, `List`, and `sheet(item:)`.
extension CalendarSummary: Identifiable {}
extension CalendarEvent: Identifiable {}
