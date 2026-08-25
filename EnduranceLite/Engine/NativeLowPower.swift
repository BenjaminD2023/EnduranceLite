import Foundation

/// Wraps macOS Low Power Mode (`pmset lowpowermode`) and records the value
/// we found on launch so we can restore it instead of blindly turning it off.
final class NativeLowPower {
    private(set) var restoreTarget: Bool
    private(set) var lastSetSucceeded = false

    var isEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    init() {
        restoreTarget = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func setRestoreTarget(_ value: Bool) {
        restoreTarget = value
    }

    func captureRestoreTarget() {
        restoreTarget = isEnabled
    }

    @MainActor
    func setEnabled(_ on: Bool) -> Bool {
        if isEnabled == on {
            lastSetSucceeded = true
            return true
        }
        let flag = on ? "1" : "0"
        // Battery-only keeps the machine fast on charger once we restore.
        let lowPower = PrivilegedShell.pmset(["-b", "lowpowermode", flag])
        let powerNap = PrivilegedShell.pmset(["-b", "powernap", on ? "0" : "1"])
        lastSetSucceeded = lowPower && powerNap
        return lastSetSucceeded
    }

    @MainActor
    func restoreLaunchState() {
        _ = setEnabled(restoreTarget)
    }
}
