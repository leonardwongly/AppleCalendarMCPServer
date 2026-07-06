import SwiftUI

extension Color {
    /// Creates a color from a `#RRGGBB` (or `RRGGBB`) hex string. Returns nil for
    /// nil/invalid input so callers can fall back gracefully.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

/// A small filled dot representing a calendar's color, with a subtle ring so it
/// stays visible on any background. Falls back to the secondary color.
struct CalendarColorDot: View {
    let hex: String?
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? Color.secondary)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.25)))
    }
}
