import Foundation

enum StartMode: String, CaseIterable, Identifiable, Codable {
    case ask = "Ask"
    case always = "Always"
    case never = "Never"
    case unplug = "On Unplug"

    var id: String { rawValue }
}

enum MenuBarStyle: String, CaseIterable, Identifiable, Codable {
    case iconOnly = "Icon only"
    case iconAndPercent = "Icon and percentage"
    case iconAndTime = "Icon and time"

    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable {
    var startMode: StartMode = .ask
    var thresholdPercent: Double = 70
    var enabledFeatures: Set<PowerFeatureID> = [
        .slowProcessor, .pauseServices, .monitorExpensive, .dimScreen
    ]
    var showBatteryIcon: Bool = false
    var menuBarStyle: MenuBarStyle = .iconOnly
    var restoreWhenPluggedIn: Bool = true
    var launchAtLogin: Bool = true

    func isEnabled(_ feature: PowerFeatureID) -> Bool {
        enabledFeatures.contains(feature)
    }

    mutating func set(_ feature: PowerFeatureID, enabled: Bool) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }
}

enum SettingsStore {
    private static let key = "EnduranceLite.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
