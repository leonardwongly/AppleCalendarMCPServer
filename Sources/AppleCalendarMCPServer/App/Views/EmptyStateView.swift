import SwiftUI

/// A lightweight stand-in for `ContentUnavailableView`, which is only available
/// on macOS 14+. The package targets macOS 13, so we roll our own.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            GlassGroup {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .frame(width: 88, height: 88)
                    .liquidGlass(in: Circle())
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
        .padding(24)
    }
}
