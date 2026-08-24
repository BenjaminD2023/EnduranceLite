import Foundation

/// Wraps macOS Low Power Mode (`pmset lowpowermode`) and records the value
/// we found on launch so we can restore it instead of blindly turning it off.
final class NativeLowPower {
    private(set) var valueOnLaunch: Bool
    private(set) var lastSetSucceeded = false

    var isEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    init() {
        valueOnLaunch = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @MainActor
    func setEnabled(_ on: Bool) -> Bool {
        if isEnabled == on {
            lastSetSucceeded = true
            return true
        }
        let flag = on ? "1" : "0"
        // Battery-only keeps the machine fast on charger once we restore.
        let command = "pmset -b lowpowermode \(flag) && pmset -b powernap \(on ? "0" : "1")"
        let ok = PrivilegedShell.run(command, requireAdmin: true)
        lastSetSucceeded = ok
        return ok
    }

    @MainActor
    func restoreLaunchState() {
        _ = setEnabled(valueOnLaunch)
    }
}
