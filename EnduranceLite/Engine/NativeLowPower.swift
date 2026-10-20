import Foundation

/// Controls the battery policy, which can differ from the currently active AC
/// policy. Only changes lowpowermode; unrelated settings such as Power Nap stay
/// under the user's control.
final class NativeLowPower {
    typealias BatteryPolicyReader = () -> Bool?
    typealias BatteryPolicyWriter = @MainActor (Bool) -> Bool

    private let readBatteryPolicy: BatteryPolicyReader
    private let writeBatteryPolicy: BatteryPolicyWriter
    private let readActiveMode: () -> Bool

    private(set) var restoreTarget: Bool
    private(set) var hasRestoreTarget: Bool
    private(set) var lastSetSucceeded = false

    var isEnabled: Bool {
        readActiveMode()
    }

    init(
        readBatteryPolicy: @escaping BatteryPolicyReader = NativeLowPower.readSystemBatteryPolicy,
        writeBatteryPolicy: @escaping BatteryPolicyWriter = { on in
            PrivilegedShell.pmset(["-b", "lowpowermode", on ? "1" : "0"])
        },
        readActiveMode: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.readBatteryPolicy = readBatteryPolicy
        self.writeBatteryPolicy = writeBatteryPolicy
        self.readActiveMode = readActiveMode
        let batteryPolicy = readBatteryPolicy()
        restoreTarget = batteryPolicy ?? false
        hasRestoreTarget = batteryPolicy != nil
    }

    func setRestoreTarget(_ value: Bool) {
        restoreTarget = value
        hasRestoreTarget = true
    }

    @discardableResult
    func captureRestoreTarget() -> Bool {
        guard let batteryPolicy = readBatteryPolicy() else {
            hasRestoreTarget = false
            return false
        }
        restoreTarget = batteryPolicy
        hasRestoreTarget = true
        return true
    }

    @discardableResult
    @MainActor
    func setEnabled(_ on: Bool) -> Bool {
        guard let batteryPolicy = readBatteryPolicy() else {
            lastSetSucceeded = false
            return false
        }
        if !hasRestoreTarget {
            restoreTarget = batteryPolicy
            hasRestoreTarget = true
        }
        if batteryPolicy == on {
            lastSetSucceeded = true
            return true
        }
        lastSetSucceeded = writeBatteryPolicy(on) && readBatteryPolicy() == on
        return lastSetSucceeded
    }

    @MainActor
    func restoreLaunchState() {
        guard hasRestoreTarget else {
            lastSetSucceeded = false
            return
        }
        _ = setEnabled(restoreTarget)
    }

    static func batteryPolicy(from output: String) -> Bool? {
        var inBatterySection = false
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") {
                inBatterySection = trimmed == "Battery Power:"
                continue
            }
            guard inBatterySection else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0] == "lowpowermode" else { continue }
            switch fields[1] {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }
        return nil
    }

    private static func readSystemBatteryPolicy() -> Bool? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
            return batteryPolicy(from: text)
        } catch {
            return nil
        }
    }
}
