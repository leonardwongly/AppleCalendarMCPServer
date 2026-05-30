import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum CalendarPermissionPrompt {
    @MainActor
    static func prepareForPrompt() {
        #if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }
}
