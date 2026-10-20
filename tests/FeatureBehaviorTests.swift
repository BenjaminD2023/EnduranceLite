import AppKit
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

/// CPU counters, time, and foreground state are injected; no live apps are read
/// or signalled by these feature tests.
private final class EnergyFixture {
    var readings: [EnergyMonitor.ProcessReading] = []
    var frontmost: pid_t?
    var date = Date(timeIntervalSince1970: 0)
    var monitor: EnergyMonitor!

    init(cores: Int = 1) {
        monitor = EnergyMonitor(
            processReadings: { [unowned self] in self.readings },
            frontmostPID: { [unowned self] in self.frontmost },
            currentDate: { [unowned self] in self.date },
            processorCount: { cores }
        )
        monitor.start()
    }

    func set(_ ticks: UInt64?, pid: pid_t = 100) {
        readings.removeAll { $0.pid == pid }
        readings.append(EnergyMonitor.ProcessReading(pid: pid, name: "Fixture \(pid)", bundleIdentifier: "test.fixture.\(pid)", ticks: ticks))
    }

    @discardableResult
    func poll(after seconds: TimeInterval = 5) -> (samples: [EnergySample], hot: [EnergySample]) {
        date = date.addingTimeInterval(seconds)
        return monitor.poll()
    }
}

private func testCPUCalculationAndConsecutiveHeat() throws {
    let fixture = EnergyFixture(cores: 4)
    fixture.set(0)
    try expect(fixture.poll(after: 0).samples.isEmpty, "First CPU read must establish a baseline")
    fixture.set(5_000_000_000)
    let first = fixture.poll()
    try expect(first.samples.count == 1 && abs(first.samples[0].cpuPercent - 25) < 0.001, "CPU percentage must use elapsed time and total processor capacity")
    try expect(first.hot.isEmpty, "One hot interval must not pause an app")
    fixture.set(10_000_000_000)
    try expect(fixture.poll().hot.map(\.pid) == [100], "Two consecutive hot background intervals must identify the app")
    fixture.set(10_100_000_000)
    try expect(fixture.poll().hot.isEmpty, "A cool interval must clear the hot streak")
    fixture.set(15_100_000_000)
    try expect(fixture.poll().hot.isEmpty, "The first hot interval after cooling must start a new streak")
}

private func testForegroundBreaksBackgroundHeat() throws {
    let fixture = EnergyFixture()
    fixture.set(0)
    fixture.poll(after: 0)
    fixture.set(5_000_000_000)
    fixture.poll()
    fixture.frontmost = 100
    fixture.set(10_000_000_000)
    try expect(fixture.poll().hot.isEmpty, "Foreground apps must never be hot-pause candidates")
    fixture.frontmost = nil
    fixture.set(15_000_000_000)
    try expect(fixture.poll().hot.isEmpty, "Foreground use must break the previous background streak")
    fixture.set(20_000_000_000)
    try expect(fixture.poll().hot.map(\.pid) == [100], "Fresh consecutive background heat must still be detected")
}

private func testFailedReadDoesNotInflateNextSample() throws {
    let fixture = EnergyFixture()
    fixture.set(0)
    fixture.poll(after: 0)
    fixture.set(5_000_000_000)
    fixture.poll()
    fixture.set(nil)
    try expect(fixture.poll().samples.isEmpty, "A failed counter read must not invent a CPU sample")
    fixture.set(15_000_000_000)
    let recovered = fixture.poll()
    try expect(recovered.samples.isEmpty && recovered.hot.isEmpty, "Recovery from a missing read must establish a fresh baseline")
    fixture.set(20_000_000_000)
    try expect(fixture.poll().hot.isEmpty, "Missing reads must also break the hot streak")
    fixture.set(25_000_000_000)
    try expect(fixture.poll().hot.map(\.pid) == [100], "Hot detection must recover after valid consecutive reads")
}

private func testProcessRemovalAndMonitorRestartResetBaselines() throws {
    let fixture = EnergyFixture()
    fixture.set(0)
    fixture.poll(after: 0)
    fixture.set(5_000_000_000)
    fixture.poll()
    fixture.readings.removeAll()
    fixture.poll()
    fixture.set(15_000_000_000)
    try expect(fixture.poll().samples.isEmpty, "A returning PID must not inherit the old process CPU baseline")
    fixture.set(20_000_000_000)
    try expect(fixture.poll().hot.isEmpty, "A returning PID must not inherit its old hot streak")
    fixture.monitor.stop()
    fixture.monitor.start()
    fixture.set(25_000_000_000)
    try expect(fixture.poll().samples.isEmpty, "Restarting the monitor must start with a fresh CPU baseline")
}

private func testTopSamplesDoNotLimitHotDetection() throws {
    let fixture = EnergyFixture()
    for pid: pid_t in 100..<110 { fixture.set(0, pid: pid) }
    fixture.poll(after: 0)
    for pid: pid_t in 100..<110 { fixture.set(UInt64(pid - 98) * 1_000_000_000, pid: pid) }
    fixture.poll()
    for pid: pid_t in 100..<110 { fixture.set(UInt64(pid - 98) * 2_000_000_000, pid: pid) }
    var delivered: [EnergySample] = []
    fixture.monitor.onSamples = { delivered = $0 }
    let result = fixture.poll()
    try expect(result.samples.count == 8 && result.hot.count == 10, "The UI's top-eight limit must not hide eligible hot apps from monitoring")
    try expect(result.samples.first?.pid == 109 && result.samples.last?.pid == 102, "Live CPU samples must be sorted from highest to lowest")
    try expect(delivered == result.samples, "Sample callback and polling result must expose the same top list")
}

private final class FakeApplication: BackgroundHideableApp {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    var activationPolicy: NSApplication.ActivationPolicy
    var isHidden: Bool
    var hideSucceeds = true
    var hideCalls = 0
    var unhideCalls = 0

    init(_ pid: pid_t, bundle: String? = "test.fixture", policy: NSApplication.ActivationPolicy = .regular, hidden: Bool = false) {
        processIdentifier = pid
        bundleIdentifier = bundle
        activationPolicy = policy
        isHidden = hidden
    }

    func hide() -> Bool {
        hideCalls += 1
        if hideSucceeds { isHidden = true }
        return hideSucceeds
    }

    func unhide() -> Bool {
        unhideCalls += 1
        isHidden = false
        return true
    }
}

private func testHiderProtectsForegroundAndExistingHiddenApps() throws {
    let front = FakeApplication(100)
    let own = FakeApplication(101)
    let finder = FakeApplication(102, bundle: "com.apple.finder")
    let helper = FakeApplication(103, policy: .prohibited)
    let alreadyHidden = FakeApplication(104, hidden: true)
    let background = FakeApplication(105)
    let failed = FakeApplication(106)
    failed.hideSucceeds = false
    let apps = [front, own, finder, helper, alreadyHidden, background, failed]
    let hider = BackgroundHider(runningApplications: { apps }, frontmostPID: { 100 }, ownPID: 101)
    hider.hideBackgroundApps()
    try expect([front, own, finder, helper, alreadyHidden].allSatisfy { $0.hideCalls == 0 }, "Hiding must exclude the foreground, EnduranceLite, Finder, helpers, and apps already hidden by the user")
    try expect(background.hideCalls == 1 && background.isHidden, "Eligible background apps must be hidden")
    hider.restore()
    try expect(background.unhideCalls == 1 && !background.isHidden, "A successfully hidden app must be restored")
    try expect(failed.unhideCalls == 0 && alreadyHidden.unhideCalls == 0, "Restoration must not unhide apps EnduranceLite did not hide")
    hider.restore()
    try expect(background.unhideCalls == 1, "Restoration must clear its ownership records")
}

private func testHiderRestoresEveryInstanceAcrossRepeatedPasses() throws {
    let first = FakeApplication(100)
    let second = FakeApplication(101) // Same bundle ID, distinct application.
    let noBundle = FakeApplication(102, bundle: nil)
    let later = FakeApplication(103)
    var apps: [FakeApplication] = [first, second, noBundle]
    let hider = BackgroundHider(runningApplications: { apps }, frontmostPID: { 999 }, ownPID: 998)
    hider.hideBackgroundApps()
    apps.append(later)
    hider.hideBackgroundApps()
    try expect([first, second, noBundle, later].allSatisfy { $0.hideCalls == 1 && $0.isHidden }, "Repeated passes must hide new apps while preserving prior restoration records")
    // Restore original process handles even if workspace no longer lists them;
    // a replacement instance with the same bundle ID must remain untouched.
    let replacement = FakeApplication(104, hidden: true)
    apps = [replacement]
    hider.restore()
    try expect([first, second, noBundle, later].allSatisfy { $0.unhideCalls == 1 && !$0.isHidden }, "Every instance, including apps without bundle IDs, must be restored")
    try expect(replacement.unhideCalls == 0, "A newly launched replacement must not inherit another process's restoration")
}

@main
private struct FeatureBehaviorTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("CPU calculation and consecutive heat", testCPUCalculationAndConsecutiveHeat),
            ("foreground use breaks background heat", testForegroundBreaksBackgroundHeat),
            ("failed counters reset measurement and heat", testFailedReadDoesNotInflateNextSample),
            ("process removal and restart reset baselines", testProcessRemovalAndMonitorRestartResetBaselines),
            ("hot detection covers apps beyond the UI limit", testTopSamplesDoNotLimitHotDetection),
            ("hiding respects foreground and user-hidden apps", testHiderProtectsForegroundAndExistingHiddenApps),
            ("hiding restores all instances across repeated passes", testHiderRestoresEveryInstanceAcrossRepeatedPasses)
        ]
        do {
            for (name, test) in tests {
                try test()
                print("PASS \(name)")
            }
            print("All \(tests.count) feature behavior tests passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
