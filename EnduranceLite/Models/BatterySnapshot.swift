import Foundation

struct BatterySnapshot: Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isPresent: Bool
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var cycleCount: Int?
    var updatedAt: Date

    static let unknown = BatterySnapshot(
        percent: 0,
        isCharging: false,
        isPluggedIn: true,
        isPresent: false,
        timeToEmptyMinutes: nil,
        timeToFullMinutes: nil,
        cycleCount: nil,
        updatedAt: .distantPast
    )

    var onBattery: Bool { isPresent && !isPluggedIn }

    var timeRemainingLabel: String {
        if isPluggedIn {
            if isCharging, let minutes = timeToFullMinutes, minutes > 0 {
                return "\(Self.format(minutes)) to full"
            }
            return "Plugged in"
        }
        if let minutes = timeToEmptyMinutes, minutes > 0 {
            return Self.format(minutes) + " left"
        }
        return "Calculating…"
    }

    var percentLabel: String { "\(percent)%" }

    private static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

struct PausedApp: Identifiable, Equatable {
    var id: pid_t { pid }
    var pid: pid_t
    var name: String
    var bundleIdentifier: String?
    var reason: String
}

struct EnergySample: Identifiable, Equatable {
    var id: pid_t { pid }
    var pid: pid_t
    var name: String
    var bundleIdentifier: String?
    var cpuPercent: Double
}
