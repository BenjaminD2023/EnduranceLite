import AppKit
import Foundation

final class BackgroundHider {
    private var hiddenBundleIDs: [String] = []

    func hideBackgroundApps() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        hiddenBundleIDs.removeAll()
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            guard app.bundleIdentifier != front else { continue }
            if app.bundleIdentifier == "com.apple.finder" { continue }
            if app.isHidden { continue }
            if app.hide() {
                if let id = app.bundleIdentifier {
                    hiddenBundleIDs.append(id)
                }
            }
        }
    }

    func restore() {
        for id in hiddenBundleIDs {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == id })?
                .unhide()
        }
        hiddenBundleIDs.removeAll()
    }
}
