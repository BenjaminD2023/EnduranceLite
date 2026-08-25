import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        EnduranceEngine.shared.start()
        NSApp.setActivationPolicy(.accessory)

        let launchedAsLoginItem = getppid() == 1
            || ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != nil
            || ProcessInfo.processInfo.arguments.contains("--background")
        let firstLaunch = !UserDefaults.standard.bool(forKey: "ELHasOpenedSettings")
        let restoringSession = SessionStore.load()?.active == true
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: "ELHasOpenedSettings")
        }
        if (firstLaunch || !launchedAsLoginItem) && !restoringSession {
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
        EnduranceEngine.shared.prepareForTermination()
        if SessionStore.load()?.active != true {
            PidBag.emergencyResume()
        }
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
        hosting.frame = NSRect(x: 0, y: 0, width: 920, height: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
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
        window.contentMinSize = NSSize(width: 920, height: 640)
        window.contentMaxSize = NSSize(width: 920, height: 640)
        window.setContentSize(NSSize(width: 920, height: 640))
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
