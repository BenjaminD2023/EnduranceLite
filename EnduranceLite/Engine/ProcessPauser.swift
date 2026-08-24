import AppKit
import Darwin
import Foundation

final class ProcessPauser {
    private var paused: [PausedApp] = []

    var pausedApps: [PausedApp] { paused }

    private let browserPatterns: [String] = [
        "safari", "google chrome", "chromium", "firefox", "arc", "brave browser",
        "microsoft edge", "opera", "vivaldi", "orion", "zen browser", "dia",
        "webkit.webcontent", "webkit.gpu", "webkit.networking",
        "chrome helper", "firefoxcp", "plugin-container"
    ]

    private let servicePatterns: [String] = [
        "photoanalysisd", "mediaanalysisd", "photolibraryd",
        "knowledgeconstructiond", "corespotlightd", "siriausp",
        "googleupdater", "google software update", "microsoft update",
        "adobe desktop service", "adobe cr daemon", "ccxprocess",
        "dropbox", "onedrive", "zoomopener", "steam_osx",
        "crewchief", "creative cloud", "box sync", "backupd-helper"
    ]

    private let protectedNameBits: [String] = [
        "endurancelite", "grok", "cursor", "xcode", "instruments",
        "terminal", "iterm", "warp", "ghostty", "activity monitor",
        "windowserver", "loginwindow", "dock", "finder", "control center",
        "systemuiserver", "kernel_task", "launchd"
    ]

    @discardableResult
    func pauseBrowsers() -> [PausedApp] {
        pauseMatching(patterns: browserPatterns, reason: "browser")
    }

    @discardableResult
    func pauseServices() -> [PausedApp] {
        let userLevel = pauseMatching(patterns: servicePatterns, reason: "service")
        // Best-effort system services; ignore permission failures.
        _ = PrivilegedShell.runUnprivileged("killall -STOP photoanalysisd mediaanalysisd 2>/dev/null; true")
        return userLevel
    }

    @discardableResult
    func pausePID(_ pid: pid_t, name: String, bundleIdentifier: String?, reason: String) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        if PidBag.shared.contains(pid) { return true }
        if kill(pid, SIGSTOP) == 0 {
            PidBag.shared.insert(pid)
            let record = PausedApp(pid: pid, name: name, bundleIdentifier: bundleIdentifier, reason: reason)
            paused.append(record)
            return true
        }
        return false
    }

    func resumePID(_ pid: pid_t) {
        _ = kill(pid, SIGCONT)
        PidBag.shared.remove(pid)
        paused.removeAll { $0.pid == pid }
    }

    func resumeIfNeeded(bundleIdentifier: String?, name: String?) {
        let bundle = bundleIdentifier?.lowercased()
        let lowered = name?.lowercased()
        let matches = paused.filter { app in
            if let bundle, let id = app.bundleIdentifier?.lowercased(), id == bundle { return true }
            if let lowered, app.name.lowercased() == lowered { return true }
            return false
        }
        for app in matches {
            resumePID(app.pid)
        }
    }

    func resumeAll() {
        for pid in PidBag.shared.removeAll() where pid > 1 {
            _ = kill(pid, SIGCONT)
        }
        paused.removeAll()
    }

    func isProtected(name: String, bundleIdentifier: String?) -> Bool {
        let haystack = ((bundleIdentifier ?? "") + " " + name).lowercased()
        if haystack.contains("com.apple.dt") { return true }
        if haystack.contains("com.apple.finder") { return true }
        if haystack.contains("com.apple.dock") { return true }
        return protectedNameBits.contains { haystack.contains($0) }
    }

    private func pauseMatching(patterns: [String], reason: String) -> [PausedApp] {
        var added: [PausedApp] = []
        for process in runningUserProcesses() {
            if isProtected(name: process.name, bundleIdentifier: process.bundleID) { continue }
            let haystack = (process.name + " " + (process.bundleID ?? "")).lowercased()
            guard patterns.contains(where: { haystack.contains($0) }) else { continue }
            if pausePID(process.pid, name: process.name, bundleIdentifier: process.bundleID, reason: reason) {
                if let last = paused.last { added.append(last) }
            }
        }
        return added
    }

    struct RunningProc {
        var pid: pid_t
        var name: String
        var bundleID: String?
    }

    func runningUserProcesses() -> [RunningProc] {
        var list: [RunningProc] = []
        var seen = Set<pid_t>()

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 1 else { continue }
            seen.insert(pid)
            list.append(RunningProc(
                pid: pid,
                name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "pid \(pid)",
                bundleID: app.bundleIdentifier
            ))
        }

        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = Int32(MemoryLayout<pid_t>.stride * pids.count)
        let count = proc_listallpids(&pids, bytes) / Int32(MemoryLayout<pid_t>.stride)
        if count > 0 {
            for i in 0..<Int(count) {
                let pid = pids[i]
                guard pid > 1, !seen.contains(pid) else { continue }
                var buffer = [CChar](repeating: 0, count: 256)
                proc_name(pid, &buffer, UInt32(buffer.count))
                let name = String(cString: buffer)
                guard !name.isEmpty else { continue }
                list.append(RunningProc(pid: pid, name: name, bundleID: nil))
            }
        }
        return list
    }
}
