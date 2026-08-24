import Foundation
import SwiftUI

enum PowerFeatureID: String, Codable, CaseIterable, Identifiable {
    case slowProcessor
    case pauseBrowsers
    case pauseServices
    case monitorExpensive
    case hideBackground
    case dimScreen

    var id: String { rawValue }
}

struct PowerFeature: Identifiable {
    var id: PowerFeatureID
    var title: String
    var systemImage: String?
    var usesGhost: Bool = false
    var summary: String
    var detail: String

    static let all: [PowerFeature] = [
        PowerFeature(
            id: .slowProcessor,
            title: "Slow Down Processor",
            systemImage: "cpu",
            summary: "Limits CPU boost so the machine draws less power.",
            detail: "This option saves battery life by disabling high speed processing (Turbo Boost) and limiting the speed of your processor.\n\nOn Apple Silicon, EnduranceLite turns on macOS Low Power Mode — the official equivalent of disabling Turbo Boost. macOS will ask for your administrator password the first time this runs."
        ),
        PowerFeature(
            id: .pauseBrowsers,
            title: "Pause Web Browsers",
            systemImage: "wifi",
            summary: "Freezes Safari, Chrome, Arc, Firefox, Edge and others.",
            detail: "Pauses Safari, Chrome, Arc, Firefox, Edge, Brave and other browsers so they stop burning battery in the background. Your tabs stay right where they were.\n\nClick a browser in the Dock or switch to it to wake it instantly."
        ),
        PowerFeature(
            id: .pauseServices,
            title: "Pause Services",
            systemImage: "arrow.up.arrow.down",
            summary: "Stops indexing, backups and other maintenance.",
            detail: "Pauses background maintenance that quietly drains charge: Photos analysis, media analysis, software updaters, cloud helpers, and similar user-level services.\n\nSpotlight indexing and Time Machine are paused as well when administrator access is available. Everything is resumed when low power mode ends."
        ),
        PowerFeature(
            id: .monitorExpensive,
            title: "Monitor Expensive Apps",
            systemImage: "chart.xyaxis.line",
            summary: "Sleeps apps that are gobbling energy.",
            detail: "Did you know that Chrome can take up 20% of your battery, even when it's just open in the background? EnduranceLite keeps track of what's gobbling up your energy and puts those apps to sleep.\n\nBring an app forward, and it wakes immediately. System apps, developer tools and EnduranceLite itself are left alone."
        ),
        PowerFeature(
            id: .hideBackground,
            title: "Hide Background Apps",
            systemImage: nil,
            usesGhost: true,
            summary: "Hides apps that are not in front.",
            detail: "Your Mac is smart enough to slow down apps which are hidden offscreen. EnduranceLite automatically hides apps that are not in front so macOS can throttle them more aggressively.\n\nThey come back when you click them in the Dock."
        ),
        PowerFeature(
            id: .dimScreen,
            title: "Dim Screen",
            systemImage: "sun.max",
            summary: "Uses Apple's Low Power Mode display savings only.",
            detail: "EnduranceLite does not change brightness itself.\n\nWhen Low Power Mode is on, macOS already reduces display power the same way it does at low battery. That system dim applies only while Low Power Mode is enabled, and it stops when you turn Low Power Mode off or plug in (if restore-on-charger is on)."
        )
    ]

    static func feature(for id: PowerFeatureID) -> PowerFeature {
        all.first { $0.id == id } ?? all[0]
    }
}
