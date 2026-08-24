import SwiftUI

@main
struct EnduranceLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var engine = EnduranceEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(engine)
        } label: {
            MenuBarLabel()
                .environmentObject(engine)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("EnduranceLite Settings…") {
                    engine.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appTermination) {
                Button("Uninstall EnduranceLite…") {
                    engine.confirmUninstall()
                }
            }
        }
    }
}
