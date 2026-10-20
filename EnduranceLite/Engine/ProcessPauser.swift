import AppKit
import Darwin
import Foundation

final class ProcessPauser {
    private var paused: [PausedApp] = []

    var pausedApps: [PausedApp] { paused }

    private let browserPatterns: [String] = [
        "safari", "google chrome", "chromium", "firefox", "arc", "brave browser",
        "microsoft edge", "opera", "vivaldi", "orion", "zen browser", "dia",
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
        "systemuiserver", "kernel_task", "launchd",
        "raycast", "obsidian"
    ]

    @discardableResult
    func pauseBrowsers(skipFrontmost: Bool = true) -> [PausedApp] {
        pauseMatching(patterns: browserPatterns, reason: "browser", skipFrontmost: skipFrontmost, includeDescendants: true)
    }

    @discardableResult
    func pauseServices() -> [PausedApp] {
        pauseMatching(patterns: servicePatterns, reason: "service", skipFrontmost: false, includeDescendants: false)
    }

    @discardableResult
    func pausePID(_ pid: pid_t, name: String, bundleIdentifier: String?, reason: String) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        guard !isProtected(name: name, bundleIdentifier: bundleIdentifier),
              !Self.isSharedSystemRenderer(pid: pid, name: name, bundleID: bundleIdentifier) else { return false }
        if reason != "service", Self.isSystemProcess(pid) { return false }
        // The browser must remain able to acknowledge Dock/Command-Tab
        // activation. Its helper processes do the background work we pause.
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            let identity = (app.localizedName ?? name) + " " + (app.bundleIdentifier ?? bundleIdentifier ?? "")
            if browserPatterns.contains(where: { Self.matches(haystack: identity, pattern: $0) }) {
                return false
            }
        }
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

    func resumeIfNeeded(processIdentifier: pid_t, bundleIdentifier: String?, name: String?) {
        let family = familyPids(processIdentifier: processIdentifier, bundleIdentifier: bundleIdentifier)
        let matches = paused.filter { app in
            family.contains(app.pid) || Self.shouldResume(paused: app, bundleIdentifier: bundleIdentifier, name: name)
        }
        for app in matches {
            resumePID(app.pid)
        }
    }

    func resumeFrontmostIfNeeded() {
        guard !paused.isEmpty, let front = NSWorkspace.shared.frontmostApplication else { return }
        resumeIfNeeded(processIdentifier: front.processIdentifier, bundleIdentifier: front.bundleIdentifier, name: front.localizedName)
    }

    func resume(reason: String) {
        let ids = paused.filter { $0.reason == reason }.map(\.pid)
        for pid in ids {
            resumePID(pid)
        }
    }

    func resumeBrowsers() {
        resume(reason: "browser")
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

    private func pauseMatching(
        patterns: [String],
        reason: String,
        skipFrontmost: Bool,
        includeDescendants: Bool
    ) -> [PausedApp] {
        let skip = skipFrontmost ? frontmostFamilyPids() : []
        var info: [pid_t: RunningProc] = [:]
        var targets = Set<pid_t>()

        for process in runningUserProcesses() {
            info[process.pid] = process
            if isProtected(name: process.name, bundleIdentifier: process.bundleID) { continue }
            if Self.isSharedSystemRenderer(pid: process.pid, name: process.name, bundleID: process.bundleID) {
                continue
            }
            let haystack = process.name + " " + (process.bundleID ?? "")
            guard patterns.contains(where: { Self.matches(haystack: haystack, pattern: $0) }) else { continue }
            targets.insert(process.pid)
            if includeDescendants {
                collectDescendants(of: process.pid, into: &targets)
            }
        }

        var added: [PausedApp] = []
        for pid in targets {
            if skip.contains(pid) { continue }
            let process = info[pid] ?? namedProc(pid)
            if isProtected(name: process.name, bundleIdentifier: process.bundleID) { continue }
            if Self.isSharedSystemRenderer(pid: process.pid, name: process.name, bundleID: process.bundleID) {
                continue
            }
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
        // proc_listallpids returns a PID count, unlike proc_listpids below.
        let count = min(Int(proc_listallpids(&pids, bytes)), pids.count)
        if count > 0 {
            for i in 0..<count {
                let pid = pids[i]
                guard pid > 1, !seen.contains(pid) else { continue }
                list.append(namedProc(pid))
            }
        }
        return list
    }

    /// "arc" must not match Raycast; "dia" must not match Obsidian.
    static func matches(haystack: String, pattern: String) -> Bool {
        let hay = haystack.lowercased()
        let pat = pattern.lowercased()
        let hayTokens = tokens(hay)
        let patTokens = tokens(pat)
        guard !patTokens.isEmpty else { return false }
        if patTokens.count == 1 {
            let token = patTokens[0]
            if token.count <= 3 {
                return hayTokens.contains(token)
            }
            return hayTokens.contains(token) || hay.contains(pat)
        }
        return patTokens.allSatisfy { hayTokens.contains($0) }
    }

    static func shouldResume(paused: PausedApp, bundleIdentifier: String?, name: String?) -> Bool {
        let bundle = bundleIdentifier?.lowercased()
        let lowered = name?.lowercased()
        if let bundle, let id = paused.bundleIdentifier?.lowercased() {
            if id == bundle { return true }
            if id.hasPrefix(bundle + ".") { return true }
            if bundle.hasPrefix(id + ".") { return true }
        }
        if let lowered, paused.name.lowercased() == lowered { return true }
        let activated = tokens((bundleIdentifier ?? "") + " " + (name ?? ""))
        let pausedTokens = tokens((paused.bundleIdentifier ?? "") + " " + paused.name)
        let distinctive = activated.filter { $0.count >= 5 && !resumeStopwords.contains($0) }
        return distinctive.contains { pausedTokens.contains($0) }
    }

    static func isSharedSystemRenderer(pid: pid_t, name: String, bundleID: String?) -> Bool {
        let hay = ((bundleID ?? "") + " " + name).lowercased()
        if hay.contains("com.apple.webkit") { return true }
        if hay.contains("webkit.gpu") || hay.contains("webkit.webcontent") || hay.contains("webkit.networking") {
            return true
        }
        if hay.contains("safariplatformsupport") { return true }
        return false
    }

    private static func isSystemProcess(_ pid: pid_t) -> Bool {
        var path = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &path, UInt32(path.count))
        if len > 0 {
            let p = String(cString: path)
            if p.hasPrefix("/System/") { return true }
        }
        return false
    }

    private static let resumeStopwords: Set<String> = [
        "helper", "renderer", "gpu", "plugin", "container", "networking",
        "webcontent", "browser", "chrome", "service", "agent", "xpc",
        "com", "app", "macos"
    ]

    private func frontmostFamilyPids() -> Set<pid_t> {
        guard let front = NSWorkspace.shared.frontmostApplication else { return [] }
        return familyPids(processIdentifier: front.processIdentifier, bundleIdentifier: front.bundleIdentifier)
    }

    private func familyPids(processIdentifier: pid_t, bundleIdentifier: String?) -> Set<pid_t> {
        var set: Set<pid_t> = [processIdentifier]
        collectDescendants(of: processIdentifier, into: &set)
        if let id = bundleIdentifier {
            for process in runningUserProcesses() {
                guard let bid = process.bundleID else { continue }
                if bid == id || bid.hasPrefix(id + ".") {
                    set.insert(process.pid)
                    collectDescendants(of: process.pid, into: &set)
                }
            }
        }
        return set
    }

    private func collectDescendants(of parent: pid_t, into set: inout Set<pid_t>) {
        var pids = [pid_t](repeating: 0, count: 512)
        let bytes = Int32(MemoryLayout<pid_t>.stride * pids.count)
        let raw = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(bitPattern: parent), &pids, bytes)
        guard raw > 0 else { return }
        let count = min(Int(raw) / MemoryLayout<pid_t>.stride, pids.count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 1, set.insert(pid).inserted else { continue }
            collectDescendants(of: pid, into: &set)
        }
    }

    private func namedProc(_ pid: pid_t) -> RunningProc {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        return RunningProc(pid: pid, name: name.isEmpty ? "pid \(pid)" : name, bundleID: nil)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
