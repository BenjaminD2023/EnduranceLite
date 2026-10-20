/// Keeps power-source observations separate from the time at which starting a
/// session is safe. An unplug observed during startup or wake must not be lost.
struct PowerStartPolicy {
    private var wasOnBattery = false
    private var observedMode: StartMode?
    private var pendingUnplug = false

    mutating func observe(onBattery: Bool, mode: StartMode, isLowPowerActive: Bool) {
        let unplugged = onBattery && !wasOnBattery
        let modeChanged = observedMode.map { $0 != mode } ?? false
        wasOnBattery = onBattery
        observedMode = mode

        guard onBattery, mode == .unplug, !isLowPowerActive, !modeChanged else {
            pendingUnplug = false
            return
        }
        if unplugged { pendingUnplug = true }
    }

    /// Call only after startup/wake deferrals have expired and no session is active.
    mutating func decision(onBattery: Bool, percent: Int, mode: StartMode, thresholdPercent: Double) -> StartMode? {
        guard onBattery else {
            pendingUnplug = false
            return nil
        }

        if mode == .unplug {
            guard observedMode == mode, pendingUnplug else { return nil }
            pendingUnplug = false
            return .unplug
        }

        pendingUnplug = false
        guard Double(percent) <= thresholdPercent else { return nil }
        switch mode {
        case .always, .ask:
            return mode
        case .never, .unplug:
            return nil
        }
    }
}
