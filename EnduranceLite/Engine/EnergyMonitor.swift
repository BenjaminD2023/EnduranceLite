import AppKit
import Darwin
import Foundation

final class EnergyMonitor {
    var onSamples: (([EnergySample]) -> Void)?

    private var timer: Timer?
    private var lastTicks: [pid_t: UInt64] = [:]
    private var lastStamp: Date?
    private var consecutiveHot: [pid_t: Int] = [:]

    var hotThresholdPercent: Double = 18
    var consecutiveNeeded: Int = 2

    func start() {
        lastStamp = Date()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks.removeAll()
        consecutiveHot.removeAll()
    }

    func resetHotTracking() {
        consecutiveHot.removeAll()
    }

    /// Returns samples plus any PIDs that have been hot long enough to sleep.
    func poll() -> (samples: [EnergySample], hot: [EnergySample]) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastStamp ?? now)
        lastStamp = now
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let elapsedNs = elapsed * 1_000_000_000

        var samples: [EnergySample] = []
        var stillAround = Set<pid_t>()

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 1, app.activationPolicy == .regular else { continue }
            stillAround.insert(pid)
            guard let ticks = Self.cpuTicks(pid: pid) else { continue }
            let previous = lastTicks[pid]
            lastTicks[pid] = ticks
            guard let previous, elapsedNs > 0 else { continue }
            let delta = ticks >= previous ? ticks - previous : 0
            let percent = (Double(delta) / elapsedNs) * 100.0 / Double(cores)
            samples.append(EnergySample(
                pid: pid,
                name: app.localizedName ?? "App",
                bundleIdentifier: app.bundleIdentifier,
                cpuPercent: max(0, percent)
            ))
        }

        lastTicks = lastTicks.filter { stillAround.contains($0.key) }
        consecutiveHot = consecutiveHot.filter { stillAround.contains($0.key) }

        samples.sort { $0.cpuPercent > $1.cpuPercent }
        let top = Array(samples.prefix(8))
        onSamples?(top)

        var hot: [EnergySample] = []
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for sample in samples {
            if sample.pid == frontmost { continue }
            if sample.cpuPercent >= hotThresholdPercent {
                consecutiveHot[sample.pid, default: 0] += 1
                if consecutiveHot[sample.pid, default: 0] >= consecutiveNeeded {
                    hot.append(sample)
                }
            } else {
                consecutiveHot[sample.pid] = 0
            }
        }
        return (top, hot)
    }

    private static func cpuTicks(pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info.pti_total_user + info.pti_total_system
    }
}
