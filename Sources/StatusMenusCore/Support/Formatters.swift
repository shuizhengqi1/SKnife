import Foundation

public enum StatusFormatters {
    public static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }

    public static func percent(used: Int64, total: Int64) -> String {
        guard total > 0 else {
            return "0%"
        }
        let fraction = Double(used) / Double(total)
        return wholePercent(fraction)
    }

    public static func wholePercent(_ fraction: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: fraction)) ?? "0%"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let clampedSeconds = max(0, seconds)
        if clampedSeconds < 1 {
            return "\(Int((clampedSeconds * 1_000).rounded())) ms"
        }
        if clampedSeconds < 60 {
            return String(format: "%.1f s", clampedSeconds)
        }
        let minutes = Int(clampedSeconds / 60)
        let remainder = Int(clampedSeconds.rounded()) % 60
        return "\(minutes)m \(remainder)s"
    }

    public static func shortDateTime(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
