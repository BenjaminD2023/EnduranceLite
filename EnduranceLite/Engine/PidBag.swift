import Darwin
import Foundation

/// Process IDs we have SIGSTOP'd, shared with a signal handler so force-quit
/// still resumes frozen apps.
final class PidBag: @unchecked Sendable {
    static let shared = PidBag()

    private let lock = NSLock()
    private var pids: Set<pid_t> = []

    func insert(_ pid: pid_t) {
        lock.lock()
        pids.insert(pid)
        lock.unlock()
    }

    func insert<S: Sequence>(_ newPids: S) where S.Element == pid_t {
        lock.lock()
        pids.formUnion(newPids)
        lock.unlock()
    }

    func remove(_ pid: pid_t) {
        lock.lock()
        pids.remove(pid)
        lock.unlock()
    }

    func contains(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pids.contains(pid)
    }

    func all() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return Array(pids)
    }

    @discardableResult
    func removeAll() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = Array(pids)
        pids.removeAll()
        return snapshot
    }

    static func emergencyResume() {
        for pid in shared.all() where pid > 1 {
            _ = kill(pid, SIGCONT)
        }
        shared.removeAll()
    }
}
