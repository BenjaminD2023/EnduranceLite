import Foundation
import IOKit
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
            if let snapshot = snapshot(from: raw as NSDictionary, updatedAt: Date(), temperatureC: readTemperatureC()) {
                return snapshot
            }
        }
        return .unknown
    }

    /// Power-source lists can also contain a UPS, disconnected sources, and empty
    /// battery slots. Only a usable internal battery should drive laptop policy.
    static func snapshot(from description: NSDictionary, updatedAt: Date, temperatureC: Double?) -> BatterySnapshot? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool == true,
              let state = description[kIOPSPowerSourceStateKey] as? String,
              state == kIOPSACPowerValue || state == kIOPSBatteryPowerValue,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
              maxCapacity > 0 else { return nil }

        let rawPercent = (Double(current) / Double(maxCapacity) * 100).rounded()
        let percent = Int(Swift.max(0, Swift.min(100, rawPercent)))
        let plugged = state == kIOPSACPowerValue
        let charging = plugged && (description[kIOPSIsChargingKey] as? Bool ?? false)
        let empty = description[kIOPSTimeToEmptyKey] as? Int
        let full = description[kIOPSTimeToFullChargeKey] as? Int

        return BatterySnapshot(
            percent: percent,
            isCharging: charging,
            isPluggedIn: plugged,
            isPresent: true,
            timeToEmptyMinutes: !plugged && (empty ?? 0) > 0 ? empty : nil,
            timeToFullMinutes: charging && (full ?? 0) > 0 ? full : nil,
            cycleCount: description["CycleCount"] as? Int,
            temperatureC: temperatureC,
            updatedAt: updatedAt
        )
    }

    /// AppleSmartBattery reports temperature in centi-Celsius (3100 → 31°C).
    private static func readTemperatureC() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let raw: Double
        if let value = props["Temperature"] as? Int {
            raw = Double(value)
        } else if let value = props["Temperature"] as? Double {
            raw = value
        } else {
            return nil
        }

        let celsius = raw > 200 ? raw / 100.0 : raw
        guard celsius > 0, celsius < 90 else { return nil }
        return celsius
    }
}
