import AppKit
import StatusMenusCore
import SwiftUI

@MainActor
private enum SymbolImageCache {
    private static var images: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(named name: String) -> NSImage? {
        if let image = images[name] {
            return image
        }
        if missing.contains(name) {
            return nil
        }

        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            missing.insert(name)
            return nil
        }

        image.isTemplate = true
        images[name] = image
        return image
    }
}

struct SymbolIcon: View {
    let symbolName: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = SymbolImageCache.image(named: symbolName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("•")
                    .font(.system(size: size))
            }
        }
        .frame(width: size, height: size)
    }
}

struct ModuleHeader: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 14) {
            SymbolIcon(symbolName: symbolName, size: 34)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    var symbolName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let symbolName {
                    SymbolIcon(symbolName: symbolName, size: 14)
                        .foregroundStyle(.secondary)
                }
            }

            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: ModuleStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .inactive:
            return .secondary
        case .unavailable:
            return .red
        case .loading:
            return .blue
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbolName: String

    var body: some View {
        VStack(spacing: 10) {
            SymbolIcon(symbolName: symbolName, size: 32)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
