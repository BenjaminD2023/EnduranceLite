import AppKit
import Foundation

enum PrivilegedShell {
    private static var declinedThisSession = false
    private static var didExplainGrant = false
    private static let sudoersPath = "/etc/sudoers.d/endurancelite"

    static var userDeclined: Bool { declinedThisSession }

    /// Runs `/usr/bin/pmset` with the given arguments.
    /// After a one-time administrator grant, later calls use `sudo -n` and
    /// do not show the password dialog.
    @MainActor
    static func pmset(_ arguments: [String]) -> Bool {
        guard arguments.allSatisfy(isSafePmsetArg) else { return false }
        if runSudoNoninteractive(arguments) {
            return true
        }
        if declinedThisSession {
            return false
        }
        return installGrantAndRun(arguments)
    }

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
        runProcess(path: "/bin/zsh", arguments: ["-c", command])
    }

    @MainActor
    static func removePmsetGrant() {
        _ = runAdmin("rm -f \(sudoersPath)")
    }

    @MainActor
    private static func installGrantAndRun(_ arguments: [String]) -> Bool {
        if !didExplainGrant {
            didExplainGrant = true
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Allow Low Power Mode without a password?"
            alert.informativeText = "macOS will ask for your administrator password once. After that, EnduranceLite can turn Low Power Mode on and off without asking every time.\n\nThis only lets EnduranceLite run the pmset command."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() != .alertFirstButtonReturn {
                declinedThisSession = true
                return false
            }
        }

        guard let user = sanitizedUsername() else { return false }
        let args = arguments.joined(separator: " ")
        let shell = """
        printf '%s\\n' '# EnduranceLite — NOPASSWD for pmset only' '\(user) ALL=(root) NOPASSWD: /usr/bin/pmset' > \(sudoersPath) && chmod 440 \(sudoersPath) && chown root:wheel \(sudoersPath) && /usr/sbin/visudo -cf \(sudoersPath) && /usr/bin/pmset \(args)
        """
        let ok = runAdmin(shell)
        if ok {
            return true
        }
        return runSudoNoninteractive(arguments)
    }

    private static func runSudoNoninteractive(_ arguments: [String]) -> Bool {
        runProcess(path: "/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset"] + arguments)
    }

    private static func runProcess(path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
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
            if number == -128 {
                declinedThisSession = true
            }
            return false
        }
        return true
    }

    private static func sanitizedUsername() -> String? {
        let name = NSUserName()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return name
    }

    private static func isSafePmsetArg(_ argument: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return !argument.isEmpty && argument.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
