import AppKit
import Foundation

protocol BackgroundHideableApp: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var activationPolicy: NSApplication.ActivationPolicy { get }
    var isHidden: Bool { get }
    func hide() -> Bool
    func unhide() -> Bool
}

extension NSRunningApplication: BackgroundHideableApp {}

final class BackgroundHider {
    private let runningApplications: () -> [BackgroundHideableApp]
    private let frontmostPID: () -> pid_t?
    private let ownPID: pid_t
    private var hiddenApps: [pid_t: BackgroundHideableApp] = [:]

    init(
        runningApplications: (() -> [BackgroundHideableApp])? = nil,
        frontmostPID: (() -> pid_t?)? = nil,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.runningApplications = runningApplications ?? { NSWorkspace.shared.runningApplications }
        self.frontmostPID = frontmostPID ?? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        self.ownPID = ownPID
    }

    func hideBackgroundApps() {
        let front = frontmostPID()
        for app in runningApplications() {
            guard app.activationPolicy == .regular else { continue }
            guard app.processIdentifier != ownPID else { continue }
            guard app.processIdentifier != front else { continue }
            if app.bundleIdentifier == "com.apple.finder" { continue }
            if app.isHidden { continue }
            if app.hide() {
                hiddenApps[app.processIdentifier] = app
            }
        }
    }

    func restore() {
        // Keep the original process handles: multiple instances can share a
        // bundle ID, and some regular apps do not have one at all.
        for app in hiddenApps.values {
            _ = app.unhide()
        }
        hiddenApps.removeAll()
    }
}
