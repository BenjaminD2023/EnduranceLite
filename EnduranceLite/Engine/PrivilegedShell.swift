import AppKit
import Foundation

enum PrivilegedShell {
    private static var declinedThisSession = false

    static var userDeclined: Bool { declinedThisSession }

    /// Runs a `/bin/zsh -c` command. Tries without privileges first, then
    /// prompts for an administrator password via AppleScript.
    @MainActor
    static func run(_ command: String, requireAdmin: Bool = false) -> Bool {
        if !requireAdmin, runUnprivileged(command) {
            return true
        }
        if declinedThisSession {
            return false
        }
        return runAdmin(command)
    }

    static func runUnprivileged(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    @MainActor
    private static func runAdmin(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        if let error {
            let number = error["NSAppleScriptErrorNumber"] as? Int
            // -128 is user cancelled
            if number == -128 {
                declinedThisSession = true
            }
            return false
        }
        return true
    }
}
