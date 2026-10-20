import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func waitUntil(_ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(3)
    repeat {
        if predicate() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    } while Date() < deadline
    return false
}

private func isStopped(_ pid: pid_t) -> Bool {
    var info = proc_bsdinfo()
    let expected = Int32(MemoryLayout<proc_bsdinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return false }
    return info.pbi_status == 4 // SSTOP from sys/proc.h
}

/// Only disposable child processes created by this test are ever signalled.
/// The nested shell stands in for an anonymous helper, and sleep for its worker.
private final class DisposableTree {
    let root = Process()
    private let directory: URL
    private(set) var children: [pid_t] = []

    var rootPID: pid_t { root.processIdentifier }
    var allPIDs: [pid_t] { [rootPID] + children }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnduranceLite-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        root.executableURL = URL(fileURLWithPath: "/bin/sh")
        root.arguments = ["-c", """
        /bin/sh -c '/bin/sleep 120 & child=$!; printf "%s\\n" "$child" > "$ENDURANCE_TEST_TREE/grandchild.pid"; wait "$child"' &
        helper=$!
        /bin/sleep 120 &
        worker=$!
        printf '%s\\n%s\\n' "$helper" "$worker" > "$ENDURANCE_TEST_TREE/children.pid"
        wait
        """]
        var environment = ProcessInfo.processInfo.environment
        environment["ENDURANCE_TEST_TREE"] = directory.path
        root.environment = environment
        root.standardOutput = FileHandle.nullDevice
        root.standardError = FileHandle.nullDevice
        do {
            try root.run()
            let ready = waitUntil {
                self.children = self.readPIDs("children.pid") + self.readPIDs("grandchild.pid")
                return self.children.count == 3 && self.children.allSatisfy { kill($0, 0) == 0 }
            }
            try expect(ready, "Disposable process tree did not become ready")
        } catch {
            cleanup()
            throw error
        }
    }

    func cleanup() {
        // Re-read in case setup failed between launching a child and recording it.
        let owned = Set(children + readPIDs("children.pid") + readPIDs("grandchild.pid") + (root.isRunning ? [rootPID] : []))
        for pid in owned where pid > 1 { _ = kill(pid, SIGCONT) }
        for pid in owned where pid > 1 { _ = kill(pid, SIGTERM) }
        if root.isRunning {
            if !waitUntil({ !self.root.isRunning }) { _ = kill(rootPID, SIGKILL) }
            root.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: directory)
        children.removeAll()
    }

    private func readPIDs(_ file: String) -> [pid_t] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
    }
}

private func pause(_ tree: DisposableTree, using pauser: ProcessPauser, reason: String) throws {
    for (index, pid) in tree.allPIDs.enumerated() {
        // Generic and nil identities deliberately cannot match Dia by name/bundle.
        let name = index == 0 ? "Dia" : (index == 1 ? "Browser Helper" : "agent-server")
        let bundle = index == 0 ? "company.thebrowser.dia" : nil
        try expect(pauser.pausePID(pid, name: name, bundleIdentifier: bundle, reason: reason), "Could not pause owned PID \(pid)")
    }
    try expect(waitUntil { tree.allPIDs.allSatisfy(isStopped) }, "Fixture tree must really be SIGSTOP'd before testing resume")
}

private func testActivationResumesEntireTree() throws {
    let pauser = ProcessPauser()
    let activated = try DisposableTree()
    defer { pauser.resumeAll(); activated.cleanup() }
    let unrelated = try DisposableTree()
    defer { pauser.resumeAll(); unrelated.cleanup() }

    try pause(activated, using: pauser, reason: "browser")
    for pid in unrelated.allPIDs {
        try expect(pauser.pausePID(pid, name: "Unrelated Worker", bundleIdentifier: nil, reason: "service"), "Could not pause unrelated fixture")
    }
    try expect(waitUntil { unrelated.allPIDs.allSatisfy(isStopped) }, "Unrelated fixture must start stopped")

    pauser.resumeIfNeeded(processIdentifier: activated.rootPID, bundleIdentifier: "company.thebrowser.dia", name: "Dia")

    try expect(waitUntil { activated.allPIDs.allSatisfy { !isStopped($0) } }, "Activation must resume root, generic helper, direct worker, and grandchild")
    try expect(unrelated.allPIDs.allSatisfy(isStopped), "Activating one browser must leave an unrelated paused process tree stopped")
    let stillPaused = Set(pauser.pausedApps.map(\.pid))
    try expect(stillPaused.isDisjoint(with: Set(activated.allPIDs)), "Resumed descendants must leave paused-app bookkeeping")
    try expect(Set(unrelated.allPIDs).isSubset(of: stillPaused), "Unrelated paused process bookkeeping must be preserved")
}

private func testActivationResumesExpensiveDescendants() throws {
    let pauser = ProcessPauser()
    let tree = try DisposableTree()
    defer { pauser.resumeAll(); tree.cleanup() }
    try pause(tree, using: pauser, reason: "expensive")

    // PID ancestry still identifies anonymous helpers when app identity is absent.
    pauser.resumeIfNeeded(processIdentifier: tree.rootPID, bundleIdentifier: nil, name: nil)
    try expect(waitUntil { tree.allPIDs.allSatisfy { !isStopped($0) } }, "Activating a process must resume its descendants regardless of why they were paused")
    try expect(pauser.pausedApps.isEmpty, "Activation must clear all matching tree records")
}

private func testBrowserWakePreservesServicePausing() throws {
    let pauser = ProcessPauser()
    let browser = try DisposableTree()
    defer { pauser.resumeAll(); browser.cleanup() }
    let service = try DisposableTree()
    defer { pauser.resumeAll(); service.cleanup() }
    try pause(browser, using: pauser, reason: "browser")
    for pid in service.allPIDs {
        try expect(pauser.pausePID(pid, name: "Service Worker", bundleIdentifier: nil, reason: "service"), "Could not pause service fixture")
    }
    try expect(waitUntil { service.allPIDs.allSatisfy(isStopped) }, "Service fixture must start stopped")

    pauser.resumeBrowsers()
    try expect(waitUntil { browser.allPIDs.allSatisfy { !isStopped($0) } }, "Display wake must resume every browser record")
    try expect(service.allPIDs.allSatisfy(isStopped), "Browser wake must preserve service pausing")
    try expect(pauser.pausedApps.allSatisfy { $0.reason == "service" }, "Browser wake must only clear browser records")
}

private func testUserProcessEnumerationIncludesChildren() throws {
    let tree = try DisposableTree()
    defer { tree.cleanup() }
    let pids = Set(ProcessPauser().runningUserProcesses().map(\.pid))
    try expect(Set(tree.allPIDs).isSubset(of: pids), "Process enumeration must include every recent shell/helper/grandchild PID")
}

private func testMatcherSafety() throws {
    try expect(ProcessPauser.matches(haystack: "Dia company.thebrowser.dia", pattern: "dia"), "Dia must be recognized")
    try expect(!ProcessPauser.matches(haystack: "Obsidian md.obsidian", pattern: "dia"), "Dia must not match Obsidian")
    try expect(!ProcessPauser.matches(haystack: "Raycast com.raycast.macos", pattern: "arc"), "Arc must not match Raycast")
    try expect(ProcessPauser.matches(haystack: "Google Chrome Helper (GPU)", pattern: "google chrome"), "Browser helpers must remain recognized")
    let pauser = ProcessPauser()
    try expect(pauser.isProtected(name: "Obsidian", bundleIdentifier: "md.obsidian"), "Obsidian must stay protected")
    try expect(pauser.isProtected(name: "Raycast", bundleIdentifier: "com.raycast.macos"), "Raycast must stay protected")
    try expect(ProcessPauser.isSharedSystemRenderer(pid: -1, name: "com.apple.WebKit.GPU", bundleID: nil), "Shared WebKit renderers must stay protected")
    try expect(!ProcessPauser.isSharedSystemRenderer(pid: -1, name: "Dia Helper (GPU)", bundleID: "company.thebrowser.dia.helper.GPU"), "Browser-owned GPU helper must remain eligible")
}

@main
private struct ProcessPauserTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("matcher and shared-renderer safety", testMatcherSafety),
            ("complete user-process enumeration", testUserProcessEnumerationIncludesChildren),
            ("activation resumes anonymous descendant tree only", testActivationResumesEntireTree),
            ("activation resumes expensive descendants without identity", testActivationResumesExpensiveDescendants),
            ("browser wake preserves service pausing", testBrowserWakePreservesServicePausing)
        ]
        do {
            for (name, test) in tests {
                try test()
                print("PASS \(name)")
            }
            print("All \(tests.count) ProcessPauser regression checks passed.")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
