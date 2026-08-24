import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        EnduranceEngine.shared.start()
        NSApp.setActivationPolicy(.accessory)

        let launchedAsLoginItem = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != nil
            || ProcessInfo.processInfo.arguments.contains("--background")
        let firstLaunch = !UserDefaults.standard.bool(forKey: "ELHasOpenedSettings")
        if firstLaunch || !launchedAsLoginItem {
            UserDefaults.standard.set(true, forKey: "ELHasOpenedSettings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        PidBag.emergencyResume()
    }

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsWindow()
            .environmentObject(EnduranceEngine.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 610)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "EnduranceLite"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 900, height: 610)
        window.contentMaxSize = NSSize(width: 900, height: 610)
        window.setContentSize(NSSize(width: 900, height: 610))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
