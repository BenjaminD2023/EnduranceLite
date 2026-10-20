import AppKit
import Darwin
import Foundation

final class EnergyMonitor {
    struct ProcessReading {
        var pid: pid_t
        var name: String
        var bundleIdentifier: String?
        var ticks: UInt64?
    }

    var onSamples: (([EnergySample]) -> Void)?

    private let processReadings: () -> [ProcessReading]
    private let frontmostPID: () -> pid_t?
    private let currentDate: () -> Date
    private let processorCount: () -> Int
    private var timer: Timer?
    private var lastTicks: [pid_t: UInt64] = [:]
    private var lastStamp: Date?
    private var consecutiveHot: [pid_t: Int] = [:]

    var hotThresholdPercent: Double = 18
    var consecutiveNeeded: Int = 2

    init(
        processReadings: (() -> [ProcessReading])? = nil,
        frontmostPID: (() -> pid_t?)? = nil,
        currentDate: @escaping () -> Date = { Date() },
        processorCount: @escaping () -> Int = { ProcessInfo.processInfo.activeProcessorCount }
    ) {
        self.processReadings = processReadings ?? Self.runningProcessReadings
        self.frontmostPID = frontmostPID ?? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        self.currentDate = currentDate
        self.processorCount = processorCount
    }

    func start() {
        lastStamp = currentDate()
        lastTicks.removeAll()
        consecutiveHot.removeAll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks.removeAll()
        consecutiveHot.removeAll()
        lastStamp = nil
    }

    func resetHotTracking() {
        consecutiveHot.removeAll()
    }

    /// Returns samples plus any PIDs that have been hot long enough to sleep.
    func poll() -> (samples: [EnergySample], hot: [EnergySample]) {
        let now = currentDate()
        let elapsed = now.timeIntervalSince(lastStamp ?? now)
        lastStamp = now
        let cores = max(1, processorCount())
        let elapsedNs = elapsed * 1_000_000_000

        var samples: [EnergySample] = []
        var stillAround = Set<pid_t>()

        for process in processReadings() {
            let pid = process.pid
            guard pid > 1 else { continue }
            stillAround.insert(pid)
            guard let ticks = process.ticks else {
                // A missing sample breaks the consecutive sequence. Keeping the
                // old baseline would count several intervals in the next one.
                lastTicks.removeValue(forKey: pid)
                consecutiveHot.removeValue(forKey: pid)
                continue
            }
            let previous = lastTicks[pid]
            lastTicks[pid] = ticks
            guard let previous, elapsedNs > 0 else {
                consecutiveHot.removeValue(forKey: pid)
                continue
            }
            let delta = ticks >= previous ? ticks - previous : 0
            let percent = (Double(delta) / elapsedNs) * 100.0 / Double(cores)
            samples.append(EnergySample(
                pid: pid,
                name: process.name,
                bundleIdentifier: process.bundleIdentifier,
                cpuPercent: max(0, percent)
            ))
        }

        lastTicks = lastTicks.filter { stillAround.contains($0.key) }
        consecutiveHot = consecutiveHot.filter { stillAround.contains($0.key) }

        samples.sort { $0.cpuPercent > $1.cpuPercent }
        let top = Array(samples.prefix(8))
        onSamples?(top)

        var hot: [EnergySample] = []
        let frontmost = frontmostPID()
        for sample in samples {
            if sample.pid == frontmost {
                consecutiveHot.removeValue(forKey: sample.pid)
                continue
            }
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

    private static func runningProcessReadings() -> [ProcessReading] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid > 1, app.activationPolicy == .regular else { return nil }
            return ProcessReading(
                pid: pid,
                name: app.localizedName ?? "App",
                bundleIdentifier: app.bundleIdentifier,
                ticks: cpuTicks(pid: pid)
            )
        }
    }

    private static func cpuTicks(pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info.pti_total_user + info.pti_total_system
    }
}
