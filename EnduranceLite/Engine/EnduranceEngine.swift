import AppKit
import Combine
import Foundation
import UserNotifications

extension Notification.Name {
    static let enduranceOpenSettings = Notification.Name("EnduranceLite.openSettings")
    static let enduranceDidAskStart = Notification.Name("EnduranceLite.didAskStart")
}

@MainActor
final class EnduranceEngine: NSObject, ObservableObject {
    static let shared = EnduranceEngine()

    @Published var settings: AppSettings {
        didSet { SettingsStore.save(settings) }
    }
    @Published var battery: BatterySnapshot = .unknown
    @Published var isLowPowerActive = false
    @Published var nativeLowPowerEnabled = false
    @Published var selectedFeature: PowerFeatureID = .slowProcessor
    @Published var pausedApps: [PausedApp] = []
    @Published var expensiveApps: [EnergySample] = []
    @Published var statusMessage: String = "Low power mode is off"
    @Published var lastError: String?
    @Published var adminDeclined = false

    private let batteryMonitor = BatteryMonitor()
    private let nativeLowPower = NativeLowPower()
    private let dimmer = ScreenDimmer()
    private let pauser = ProcessPauser()
    private let energy = EnergyMonitor()
    private let hider = BackgroundHider()

    private var started = false
    private var askedThisDischarge = false
    private var graceUntil = Date().addingTimeInterval(45)
    private var lastOnBattery = false
    private var cancellables: Set<AnyCancellable> = []
    private var energyTimer: Timer?

    private override init() {
        settings = SettingsStore.load()
        super.init()
        nativeLowPowerEnabled = nativeLowPower.isEnabled
    }

    func start() {
        guard !started else { return }
        started = true

        installEmergencyResume()
        AskPrompt.register()
        UNUserNotificationCenter.current().delegate = self

        if settings.launchAtLogin {
            _ = LoginItem.setEnabled(true)
        }

        batteryMonitor.onChange = { [weak self] snapshot in
            Task { @MainActor in
                self?.handleBattery(snapshot)
            }
        }
        batteryMonitor.start()
        energy.start()

        energyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollEnergy()
            }
        }

        NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.pauser.resumeIfNeeded(bundleIdentifier: app.bundleIdentifier, name: app.localizedName)
                self?.pausedApps = self?.pauser.pausedApps ?? []
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.nativeLowPowerEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tearDownForQuit()
            }
            .store(in: &cancellables)

        handleBattery(batteryMonitor.snapshot())
    }

    func toggleFeature(_ id: PowerFeatureID) {
        settings.set(id, enabled: !settings.isEnabled(id))
        selectedFeature = id
        if isLowPowerActive {
            // Re-apply so toggling mid-session has an effect.
            applyFeatures(entering: true)
        }
    }

    func setFeature(_ id: PowerFeatureID, enabled: Bool) {
        settings.set(id, enabled: enabled)
        if isLowPowerActive {
            applyFeatures(entering: true)
        }
    }

    func userToggleLowPower(_ on: Bool) {
        if on {
            enterLowPower(reason: "manual")
        } else {
            exitLowPower(reason: "manual")
        }
    }

    func openSettings() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showSettings()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .enduranceOpenSettings, object: nil)
    }

    func settingsDidClose() {
        if NSApp.windows.filter({ $0.isVisible && $0.identifier?.rawValue == "settings" }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func uninstall() {
        exitLowPower(reason: "uninstall")
        _ = LoginItem.setEnabled(false)
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([appURL]) { _, error in
            if let error {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                }
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func confirmUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall EnduranceLite?"
        alert.informativeText = "This turns off low power tweaks, resumes paused apps, removes the login item, and moves EnduranceLite to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            uninstall()
        }
    }

    func syncLoginItem() {
        _ = LoginItem.setEnabled(settings.launchAtLogin)
    }

    // MARK: - Policy

    private func handleBattery(_ snapshot: BatterySnapshot) {
        let wasOnBattery = lastOnBattery
        battery = snapshot
        lastOnBattery = snapshot.onBattery
        nativeLowPowerEnabled = nativeLowPower.isEnabled

        if snapshot.isPluggedIn {
            askedThisDischarge = false
            if isLowPowerActive && settings.restoreWhenPluggedIn {
                exitLowPower(reason: "plugged in")
            }
            return
        }

        if Date() < graceUntil { return }
        if isLowPowerActive { return }

        if settings.startMode == .unplug, !wasOnBattery, snapshot.onBattery {
            enterLowPower(reason: "unplug")
            return
        }

        guard snapshot.onBattery, snapshot.percent <= Int(settings.thresholdPercent) else { return }

        switch settings.startMode {
        case .always:
            enterLowPower(reason: "threshold")
        case .ask:
            askUser(percent: snapshot.percent)
        case .never, .unplug:
            break
        }
    }

    private func askUser(percent: Int) {
        guard !askedThisDischarge else { return }
        askedThisDischarge = true
        AskPrompt.postNotification(percent: percent)
        if AskPrompt.presentAlert(percent: percent) {
            enterLowPower(reason: "ask")
        }
    }

    private func enterLowPower(reason: String) {
        guard !isLowPowerActive else { return }
        isLowPowerActive = true
        lastError = nil
        applyFeatures(entering: true)
        statusMessage = "Low power mode is enabled"
        nativeLowPowerEnabled = nativeLowPower.isEnabled
        if adminDeclined && settings.isEnabled(.slowProcessor) {
            lastError = "Administrator access was declined, so native Low Power Mode could not be turned on. Other measures are still running."
        }
        _ = reason
    }

    private func exitLowPower(reason: String) {
        guard isLowPowerActive else {
            applyFeatures(entering: false)
            return
        }
        isLowPowerActive = false
        applyFeatures(entering: false)
        statusMessage = "Low power mode is off"
        nativeLowPowerEnabled = nativeLowPower.isEnabled
        _ = reason
    }

    private func applyFeatures(entering: Bool) {
        if entering {
            if settings.isEnabled(.slowProcessor) {
                let ok = nativeLowPower.setEnabled(true)
                adminDeclined = PrivilegedShell.userDeclined
                if !ok && PrivilegedShell.userDeclined {
                    lastError = "Administrator access was declined."
                }
            }
            if settings.isEnabled(.pauseBrowsers) {
                _ = pauser.pauseBrowsers()
            }
            if settings.isEnabled(.pauseServices) {
                _ = pauser.pauseServices()
            }
            if settings.isEnabled(.hideBackground) {
                hider.hideBackgroundApps()
            }
            if settings.isEnabled(.dimScreen) {
                dimmer.start()
            }
            energy.resetHotTracking()
        } else {
            if settings.isEnabled(.slowProcessor) {
                nativeLowPower.restoreLaunchState()
            }
            pauser.resumeAll()
            hider.restore()
            dimmer.restore()
            energy.resetHotTracking()
        }
        pausedApps = pauser.pausedApps
        nativeLowPowerEnabled = nativeLowPower.isEnabled
    }

    private func pollEnergy() {
        let result = energy.poll()
        expensiveApps = result.samples
        guard isLowPowerActive, settings.isEnabled(.monitorExpensive) else { return }
        for sample in result.hot {
            if pauser.isProtected(name: sample.name, bundleIdentifier: sample.bundleIdentifier) { continue }
            if pauser.pausePID(sample.pid, name: sample.name, bundleIdentifier: sample.bundleIdentifier, reason: "expensive") {
                pausedApps = pauser.pausedApps
            }
        }
    }

    private func tearDownForQuit() {
        if isLowPowerActive {
            applyFeatures(entering: false)
            isLowPowerActive = false
        } else {
            pauser.resumeAll()
            dimmer.restore()
        }
    }

    private func installEmergencyResume() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            PidBag.emergencyResume()
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }
}

extension EnduranceEngine: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == AskPrompt.startAction ||
            response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                self.enterLowPower(reason: "notification")
            }
        }
        completionHandler()
    }
}
