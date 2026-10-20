import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

private let settingsKey = "EnduranceLite.settings.v1"
private let sessionKey = "EnduranceLite.session.v1"

private var settingsFixture: AppSettings {
    var settings = AppSettings()
    settings.startMode = .unplug
    settings.thresholdPercent = 40
    settings.enabledFeatures = [.pauseBrowsers, .hideBackground]
    settings.showBatteryIcon = true
    settings.menuBarStyle = .iconAndTime
    settings.restoreWhenPluggedIn = false
    settings.launchAtLogin = false
    return settings
}

private var sessionFixture: SessionStore.State {
    SessionStore.State(
        active: false,
        restoreNativeLowPower: true,
        updatedAt: Date(timeIntervalSinceReferenceDate: 4_321),
        restoreBatteryLowPower: false,
        restorePending: true
    )
}

private func testSettingsRoundTrips() throws {
    try check(SettingsStore.load() == AppSettings(), "Missing settings must load defaults")
    for mode in StartMode.allCases {
        for style in MenuBarStyle.allCases {
            var settings = settingsFixture
            settings.startMode = mode
            settings.menuBarStyle = style
            SettingsStore.save(settings)
            try check(SettingsStore.load() == settings, "Settings must preserve every field for \(mode.rawValue)/\(style.rawValue)")
        }
    }
    var settings = settingsFixture
    for feature in PowerFeatureID.allCases {
        settings.set(feature, enabled: true)
        try check(settings.isEnabled(feature), "Feature must enable independently")
        settings.set(feature, enabled: false)
        try check(!settings.isEnabled(feature), "Feature must disable independently")
    }
    UserDefaults.standard.set(Data("invalid".utf8), forKey: settingsKey)
    try check(SettingsStore.load() == AppSettings(), "Damaged settings must recover to defaults")
}

private func testSessionMigration() throws {
    SessionStore.clear()
    try check(SessionStore.load() == nil, "Cleared session must stay absent")
    let legacy: [String: Any] = ["active": true, "restoreNativeLowPower": true, "updatedAt": 0]
    UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: legacy), forKey: sessionKey)
    let oldSession = SessionStore.load()
    try check(oldSession?.active == true, "Existing session must remain readable")
    try check(oldSession?.restoreBatteryLowPower == nil, "Legacy session must not invent a battery policy")
    try check(oldSession?.restorePending == nil, "Legacy session must not invent a pending restoration")
    try check(oldSession?.batteryLowPowerRestoreTarget == true, "Legacy restore target must remain the migration fallback")

    SessionStore.save(sessionFixture)
    try check(SessionStore.load() == sessionFixture, "New battery-policy session must round-trip")
    try check(SessionStore.load()?.active == false && SessionStore.load()?.restorePending == true, "An ended session must preserve a pending restoration independently of active state")
    try check(SessionStore.load()?.batteryLowPowerRestoreTarget == false, "Captured battery policy must take precedence over legacy active-source value")
    UserDefaults.standard.set(Data("invalid".utf8), forKey: sessionKey)
    try check(SessionStore.load() == nil, "Damaged session must not activate low power mode")
    SessionStore.clear()
}

private func testBatteryPolicyParsing() throws {
    let mixedPolicies = """
    Battery Power:
     lowpowermode 1
     powernap 0
    AC Power:
     lowpowermode 0
     powernap 1
    """
    try check(NativeLowPower.batteryPolicy(from: mixedPolicies) == true, "Battery policy must be selected independently of AC policy")
    let reverseOrder = "AC Power:\n lowpowermode 1\nBattery Power:\n lowpowermode 0\n"
    try check(NativeLowPower.batteryPolicy(from: reverseOrder) == false, "Section order must not change policy selection")
    try check(NativeLowPower.batteryPolicy(from: "AC Power:\n lowpowermode 1") == nil, "Missing battery policy must not be guessed from AC")
    try check(NativeLowPower.batteryPolicy(from: "Battery Power:\n lowpowermode unknown") == nil, "Unknown policy values must fail safely")
}

@MainActor
private func testRestorationWhileOnAC() throws {
    var batteryPolicy: Bool? = false
    var writes: [Bool] = []
    let native = NativeLowPower(
        readBatteryPolicy: { batteryPolicy },
        writeBatteryPolicy: { value in writes.append(value); batteryPolicy = value; return true },
        readActiveMode: { false }
    )
    try check(native.captureRestoreTarget(), "Battery baseline must be captured")
    try check(native.setEnabled(true), "Battery Low Power Mode must enable while AC policy stays off")
    try check(!native.isEnabled, "Active-source UI must still reflect AC mode")
    native.restoreLaunchState()
    try check(batteryPolicy == false && writes == [true, false], "Restoring on AC must write battery policy back instead of early-returning")
    try check(native.lastSetSucceeded, "Verified restore must report success")
}

@MainActor
private func testExistingBatteryPolicyAndRelaunch() throws {
    var batteryPolicy: Bool? = true
    var writes: [Bool] = []
    let native = NativeLowPower(
        readBatteryPolicy: { batteryPolicy },
        writeBatteryPolicy: { value in writes.append(value); batteryPolicy = value; return true },
        readActiveMode: { false }
    )
    try check(native.restoreTarget, "Initial restore target must use battery policy, even while AC mode is off")
    try check(native.setEnabled(true) && writes.isEmpty, "An already-enabled battery policy must need no privileged write")

    // Recreated controller starts while the session's battery policy is on.
    // Its persisted baseline must override the new instance's launch reading.
    native.setRestoreTarget(sessionFixture.batteryLowPowerRestoreTarget)
    native.restoreLaunchState()
    try check(batteryPolicy == false && writes == [false], "Relaunch must restore the persisted battery baseline")
}

@MainActor
private func testNativeFailures() throws {
    var writes = 0
    let unavailable = NativeLowPower(
        readBatteryPolicy: { nil },
        writeBatteryPolicy: { _ in writes += 1; return true },
        readActiveMode: { true }
    )
    try check(!unavailable.captureRestoreTarget() && !unavailable.hasRestoreTarget, "Missing battery policy must not capture the active-source value")
    try check(!unavailable.setEnabled(false), "Unavailable battery policy must fail without changing settings")
    unavailable.restoreLaunchState()
    try check(writes == 0 && !unavailable.lastSetSucceeded, "An unknown baseline must not cause privileged writes")

    let failedWrite = NativeLowPower(readBatteryPolicy: { false }, writeBatteryPolicy: { _ in false })
    try check(!failedWrite.setEnabled(true) && !failedWrite.lastSetSucceeded, "Failed privileged writes must be reported")
    let ineffectiveWrite = NativeLowPower(readBatteryPolicy: { false }, writeBatteryPolicy: { _ in true })
    try check(!ineffectiveWrite.setEnabled(true), "Command success without the expected battery policy must not report success")
}

@main
private struct SettingsTests {
    @MainActor
    static func main() {
        let domain = ProcessInfo.processInfo.processName
        guard domain.hasPrefix("EnduranceLiteSettingsTests-"), Bundle.main.bundleIdentifier == nil else {
            fputs("Refusing to use a non-isolated defaults domain. Run scripts/test-settings.sh.\n", stderr)
            exit(1)
        }
        if CommandLine.arguments.contains("--cleanup") {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
            return
        }
        do {
            if CommandLine.arguments.contains("--verify-persistence") {
                try check(SettingsStore.load() == settingsFixture, "Settings must survive a separate process launch")
                try check(SessionStore.load() == sessionFixture, "Battery restore session must survive a separate process launch")
                try check(SessionStore.load()?.active == false && SessionStore.load()?.restorePending == true && SessionStore.load()?.batteryLowPowerRestoreTarget == false,
                          "Pending restoration and original battery baseline must survive relaunch after the session has ended")
                print("PASS settings and session persistence across process launches")
                return
            }
            UserDefaults.standard.removePersistentDomain(forName: domain)
            try testSettingsRoundTrips()
            print("PASS settings fields, feature toggles, and corrupt-data recovery")
            try testSessionMigration()
            print("PASS legacy session migration and captured battery restore target")
            try testBatteryPolicyParsing()
            print("PASS battery/AC policy parsing")
            try testRestorationWhileOnAC()
            print("PASS native battery restoration while AC mode is off")
            try testExistingBatteryPolicyAndRelaunch()
            print("PASS original battery policy and relaunch restoration")
            try testNativeFailures()
            print("PASS native read, write, and verification failures")
            SettingsStore.save(settingsFixture)
            SessionStore.save(sessionFixture)
            try check(UserDefaults.standard.persistentDomain(forName: domain)?[settingsKey] != nil, "Saved settings must belong to the isolated test domain")
            UserDefaults.standard.synchronize()
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
