import Foundation
import IOKit.ps

final class BatteryMonitor {
    var onChange: ((BatterySnapshot) -> Void)?

    private var loopSource: CFRunLoopSource?
    private var timer: Timer?

    func start() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let source = IOPSNotificationCreateRunLoopSource(Self.powerSourceCallback, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            loopSource = source
        }

        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.publish()
        }
        publish()
    }

    func stop() {
        if let loopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), loopSource, .defaultMode)
            self.loopSource = nil
        }
        timer?.invalidate()
        timer = nil
    }

    func snapshot() -> BatterySnapshot {
        Self.read()
    }

    fileprivate func publish() {
        onChange?(Self.read())
    }

    private static let powerSourceCallback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.publish()
    }

    private static func read() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }

        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() else {
                continue
            }
            let desc = raw as NSDictionary
            let type = desc[kIOPSTypeKey] as? String
            if type == kIOPSOffLineValue { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let rawPercent = maxCapacity > 0 ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : current
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            let present = desc[kIOPSIsPresentKey] as? Bool ?? true
            let empty = desc[kIOPSTimeToEmptyKey] as? Int
            let full = desc[kIOPSTimeToFullChargeKey] as? Int
            let cycles = desc["CycleCount"] as? Int

            return BatterySnapshot(
                percent: Swift.max(0, Swift.min(100, rawPercent)),
                isCharging: charging,
                isPluggedIn: plugged,
                isPresent: present,
                timeToEmptyMinutes: (empty ?? 0) > 0 ? empty : nil,
                timeToFullMinutes: (full ?? 0) > 0 ? full : nil,
                cycleCount: cycles,
                updatedAt: Date()
            )
        }
        return .unknown
    }
}
