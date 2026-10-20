import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func testUnplugSurvivesDeferral() throws {
    var policy = PowerStartPolicy()
    policy.observe(onBattery: false, mode: .unplug, isLowPowerActive: false)
    // No decision is made during the 45-second startup or 20-second wake grace.
    for _ in 0..<10 {
        policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    }
    try expect(policy.decision(onBattery: true, percent: 98, mode: .unplug, thresholdPercent: 70) == .unplug,
               "A deferred unplug must start even above the battery threshold")
    try expect(policy.decision(onBattery: true, percent: 98, mode: .unplug, thresholdPercent: 70) == nil,
               "A consumed unplug must not start another session")
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 30, mode: .unplug, thresholdPercent: 70) == nil,
               "Remaining on battery must not manufacture another unplug")
    policy.observe(onBattery: false, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 80, mode: .unplug, thresholdPercent: 70) == .unplug,
               "A later real unplug must still start a session")
}

private func testLaunchOnBattery() throws {
    var policy = PowerStartPolicy()
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 95, mode: .unplug, thresholdPercent: 70) == .unplug,
               "Launching on battery must preserve the initial on-unplug behavior after grace")
}

private func testReplugCancelsPendingUnplug() throws {
    var policy = PowerStartPolicy()
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: false, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: false, percent: 50, mode: .unplug, thresholdPercent: 70) == nil,
               "Reconnecting power must cancel the queued unplug")
    // A decision that sees AC also cancels a queued edge, even before observation.
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    _ = policy.decision(onBattery: false, percent: 50, mode: .unplug, thresholdPercent: 70)
    try expect(policy.decision(onBattery: true, percent: 50, mode: .unplug, thresholdPercent: 70) == nil,
               "An AC decision must discard a stale queued unplug")
}

private func testActiveSessionConsumesPendingUnplug() throws {
    var policy = PowerStartPolicy()
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: true)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 40, mode: .unplug, thresholdPercent: 70) == nil,
               "Ending a session on battery must not reuse its earlier unplug")
}

private func testModeChangeCancelsPendingUnplug() throws {
    var policy = PowerStartPolicy()
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .never, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 50, mode: .unplug, thresholdPercent: 70) == nil,
               "Switching modes on battery must discard an earlier unplug")
    policy.observe(onBattery: false, mode: .unplug, isLowPowerActive: false)
    policy.observe(onBattery: true, mode: .unplug, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 50, mode: .unplug, thresholdPercent: 70) == .unplug,
               "Changing modes must not suppress a subsequent real unplug")
}

private func testThresholdModes() throws {
    for mode in [StartMode.always, .ask] {
        var policy = PowerStartPolicy()
        policy.observe(onBattery: true, mode: mode, isLowPowerActive: false)
        try expect(policy.decision(onBattery: true, percent: 71, mode: mode, thresholdPercent: 70) == nil,
                   "\(mode.rawValue) must wait until the threshold")
        try expect(policy.decision(onBattery: true, percent: 70, mode: mode, thresholdPercent: 70) == mode,
                   "\(mode.rawValue) must start exactly at the threshold")
        try expect(policy.decision(onBattery: true, percent: 30, mode: mode, thresholdPercent: 70) == mode,
                   "\(mode.rawValue) must start below the threshold")
        try expect(policy.decision(onBattery: false, percent: 30, mode: mode, thresholdPercent: 70) == nil,
                   "\(mode.rawValue) must never start while plugged in")
    }
    var policy = PowerStartPolicy()
    policy.observe(onBattery: true, mode: .never, isLowPowerActive: false)
    try expect(policy.decision(onBattery: true, percent: 1, mode: .never, thresholdPercent: 100) == nil,
               "Never must not start even below the threshold")
}

@main
private struct PowerStartPolicyTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("deferred unplug is retained and consumed once", testUnplugSurvivesDeferral),
            ("launch on battery retains on-unplug behavior", testLaunchOnBattery),
            ("AC reconnect cancels pending unplug", testReplugCancelsPendingUnplug),
            ("active session clears pending unplug", testActiveSessionConsumesPendingUnplug),
            ("mode change clears pending unplug", testModeChangeCancelsPendingUnplug),
            ("ask, always, and never threshold rules", testThresholdModes)
        ]
        do {
            for (name, test) in tests {
                try test()
                print("PASS \(name)")
            }
            print("All \(tests.count) PowerStartPolicy regression checks passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
