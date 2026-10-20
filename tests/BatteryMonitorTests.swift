import Foundation
import IOKit.ps

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

private func description(_ overrides: [String: Any] = [:]) -> NSDictionary {
    var values: [String: Any] = [
        kIOPSTypeKey: kIOPSInternalBatteryType,
        kIOPSIsPresentKey: true,
        kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        kIOPSCurrentCapacityKey: 37,
        kIOPSMaxCapacityKey: 50,
        kIOPSIsChargingKey: false,
        kIOPSTimeToEmptyKey: 135,
        kIOPSTimeToFullChargeKey: 45,
        "CycleCount": 123
    ]
    values.merge(overrides) { _, replacement in replacement }
    return values as NSDictionary
}

private func parse(_ overrides: [String: Any] = [:], temperatureC: Double? = 31.5) -> BatterySnapshot? {
    BatteryMonitor.snapshot(from: description(overrides), updatedAt: sampleDate, temperatureC: temperatureC)
}

private func testBatterySourceSelection() throws {
    for type in [kIOPSUPSType, "ExternalBattery", "Unknown", kIOPSOffLineValue] {
        try expect(parse([kIOPSTypeKey: type]) == nil, "Source type \(type) must not become the laptop battery")
    }
    try expect(parse([kIOPSPowerSourceStateKey: kIOPSOffLineValue]) == nil,
               "An offline internal battery must be skipped by its power-source state")
    try expect(parse([kIOPSPowerSourceStateKey: "Unknown"]) == nil,
               "An unknown power state must not be treated as discharging")
    try expect(parse([kIOPSIsPresentKey: false]) == nil, "An empty battery slot must be skipped")
    for key in [kIOPSTypeKey, kIOPSIsPresentKey, kIOPSPowerSourceStateKey] {
        let incomplete = description().mutableCopy() as! NSMutableDictionary
        incomplete.removeObject(forKey: key)
        try expect(BatteryMonitor.snapshot(from: incomplete, updatedAt: sampleDate, temperatureC: nil) == nil,
                   "A source missing \(key) must not drive laptop power policy")
    }
}

private func testCapacityMath() throws {
    try expect(parse()?.percent == 74, "Capacity must be scaled by maximum capacity")
    try expect(parse([kIOPSCurrentCapacityKey: 2, kIOPSMaxCapacityKey: 3])?.percent == 67,
               "Fractional capacity percentages must be rounded")
    try expect(parse([kIOPSCurrentCapacityKey: -1])?.percent == 0, "Capacity must clamp to zero")
    try expect(parse([kIOPSCurrentCapacityKey: 60])?.percent == 100, "Capacity must clamp to 100")
    try expect(parse([kIOPSCurrentCapacityKey: Int.max, kIOPSMaxCapacityKey: 1])?.percent == 100,
               "Clamping must happen before converting an extreme ratio to Int")
    for maximum in [0, -1] {
        try expect(parse([kIOPSMaxCapacityKey: maximum]) == nil,
                   "An invalid maximum must not produce a fake battery percentage")
    }
    for key in [kIOPSCurrentCapacityKey, kIOPSMaxCapacityKey] {
        let incomplete = description().mutableCopy() as! NSMutableDictionary
        incomplete.removeObject(forKey: key)
        try expect(BatteryMonitor.snapshot(from: incomplete, updatedAt: sampleDate, temperatureC: nil) == nil,
                   "A source missing \(key) must not produce a false low-battery reading")
    }
}

private func testDischargingSnapshot() throws {
    guard let snapshot = parse() else { throw TestFailure(description: "Discharging fixture was rejected") }
    try expect(snapshot.onBattery && snapshot.isPresent && !snapshot.isCharging && !snapshot.isPluggedIn,
               "A discharging internal battery must expose consistent power state")
    try expect(snapshot.timeToEmptyMinutes == 135 && snapshot.timeToFullMinutes == nil,
               "Discharging must retain only the time-to-empty estimate")
    try expect(snapshot.timeRemainingLabel == "2h 15m left" && snapshot.percentLabel == "74%",
               "Status labels must use the parsed capacity and discharge estimate")
    try expect(snapshot.cycleCount == 123 && snapshot.temperatureC == 31.5 && snapshot.updatedAt == sampleDate,
               "Cycle count, validated temperature, and observation date must be preserved")
    try expect(parse(temperatureC: nil)?.temperatureC == nil, "Missing temperature must stay unknown")
    try expect(parse([kIOPSIsChargingKey: true])?.isCharging == false,
               "A stale charging flag must not contradict battery power")
}

private func testACSnapshot() throws {
    guard let charging = parse([kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true]) else {
        throw TestFailure(description: "Charging fixture was rejected")
    }
    try expect(charging.isPluggedIn && charging.isCharging && !charging.onBattery,
               "An AC charging battery must not report battery power")
    try expect(charging.timeToEmptyMinutes == nil && charging.timeToFullMinutes == 45,
               "Charging must retain only the time-to-full estimate")
    try expect(charging.timeRemainingLabel == "45m to full", "Charging label must use time to full")
    let charged = parse([kIOPSPowerSourceStateKey: kIOPSACPowerValue])
    try expect(charged?.timeToFullMinutes == nil && charged?.timeToEmptyMinutes == nil,
               "AC without charging must omit stale time estimates")
    try expect(charged?.timeRemainingLabel == "Plugged in", "Idle AC label must show plugged in")
}

private func testUnknownTimesAndBatteryFallback() throws {
    for minutes in [-1, 0] {
        try expect(parse([kIOPSTimeToEmptyKey: minutes])?.timeToEmptyMinutes == nil,
                   "Unknown/zero time-to-empty must stay unknown")
        try expect(parse([kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true,
                          kIOPSTimeToFullChargeKey: minutes])?.timeToFullMinutes == nil,
                   "Unknown/zero time-to-full must stay unknown")
    }
    try expect(!BatterySnapshot.unknown.onBattery && !BatterySnapshot.unknown.isPresent,
               "No usable internal battery must safely avoid battery-only automation")
}

@main
private struct BatteryMonitorTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("only present internal batteries drive policy", testBatterySourceSelection),
            ("capacity scaling, rounding, clamping, and missing values", testCapacityMath),
            ("discharging state, estimates, labels, and metadata", testDischargingSnapshot),
            ("AC charging and idle estimates", testACSnapshot),
            ("unknown times and safe battery fallback", testUnknownTimesAndBatteryFallback)
        ]
        do {
            for (name, test) in tests {
                try test()
                print("PASS \(name)")
            }
            print("All \(tests.count) BatteryMonitor regression checks passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
