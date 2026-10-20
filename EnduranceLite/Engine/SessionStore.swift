import Foundation

/// Survives sleep, lid close, lock, and app relaunch so Low Power Mode
/// does not reset when the Mac wakes and is unlocked.
enum SessionStore {
    private static let key = "EnduranceLite.session.v1"

    struct State: Codable, Equatable {
        var active: Bool
        var restoreNativeLowPower: Bool
        var updatedAt: Date
        // New sessions capture the battery policy rather than the active power
        // source. Keep the old field so saved sessions remain decodable.
        var restoreBatteryLowPower: Bool? = nil
        // An ended session can still owe a native-policy restore after a failed
        // command. Preserve its baseline until a later retry succeeds.
        var restorePending: Bool? = nil

        var batteryLowPowerRestoreTarget: Bool {
            restoreBatteryLowPower ?? restoreNativeLowPower
        }
    }

    static func load() -> State? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    static func save(_ state: State) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
    }
}
