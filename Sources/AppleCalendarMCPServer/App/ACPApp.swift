import AppKit
import SwiftUI

/// Entry point bridge for the ACP (Apple Calendar Protocol) app.
///
/// `ACPApp` intentionally does *not* carry the `@main` attribute — the module's
/// real entry point is ``AppleCalendarMCPServer`` which dispatches between
/// MCP-server, CLI, one-shot, and GUI modes. When GUI mode is selected we call
/// ``ACPApp/main()`` (provided by the SwiftUI `App` protocol) explicitly through
/// this launcher so the entry point file has no SwiftUI import.
enum ACPLauncher {
    @MainActor
    static func run() {
        // Ensure the process behaves like a normal, activatable GUI app even when
        // launched from a terminal rather than via LaunchServices.
        NSApplication.shared.setActivationPolicy(.regular)
        ACPApp.main()
    }
}

struct ACPApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup("ACP") {
            RootView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    await viewModel.loadInitialDataIfPossible()
                    settings.pruneWritableCalendarIDs(knownIDs: Set(viewModel.calendars.map(\.id)))
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
