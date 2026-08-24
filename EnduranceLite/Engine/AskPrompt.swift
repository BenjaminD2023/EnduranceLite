import AppKit
import Foundation
import UserNotifications

enum AskPrompt {
    static let categoryID = "ENDURANCE_LITE_ASK"
    static let startAction = "START"
    static let laterAction = "LATER"

    static func register() {
        let start = UNNotificationAction(identifier: startAction, title: "Start", options: [.foreground])
        let later = UNNotificationAction(identifier: laterAction, title: "Not Now", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [start, later],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postNotification(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Battery is at \(percent)%"
        content.body = "Start low power mode to stretch the rest of the charge?"
        content.categoryIdentifier = categoryID
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "endurance.ask.\(percent)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    @MainActor
    static func presentAlert(percent: Int) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Start low power mode?"
        alert.informativeText = "Battery is at \(percent)%. EnduranceLite can slow the processor, pause background work, and dim the display."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational
        return alert.runModal() == .alertFirstButtonReturn
    }
}
