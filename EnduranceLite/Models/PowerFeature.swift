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
            detail: "This option saves battery life by disabling high speed processing (Turbo Boost) and limiting the speed of your processor.\n\nOn Apple Silicon, EnduranceLite turns on macOS Low Power Mode — the official equivalent of disabling Turbo Boost. macOS asks for your administrator password once; after that, toggling Low Power Mode does not prompt again."
        ),
        PowerFeature(
            id: .pauseBrowsers,
            title: "Pause Web Browsers",
            systemImage: "wifi",
            summary: "Freezes Safari, Chrome, Arc, Firefox, Edge and others.",
            detail: "Pauses browser helpers so background tabs stop burning battery. The browser's main process stays awake to keep switching responsive, and your tabs stay right where they were.\n\nSwitch back with Command-Tab or the Dock to resume the whole browser, including its GPU, network and renderer helpers. The browser you are using stays awake.\n\nWaking the display unfreezes browser helpers. After a short idle, background helpers pause again.\n\nRaycast, Obsidian, and shared system WebKit processes are never paused."
        ),
        PowerFeature(
            id: .pauseServices,
            title: "Pause Services",
            systemImage: "arrow.up.arrow.down",
            summary: "Stops indexing, backups and other maintenance.",
            detail: "Pauses supported background maintenance running under your account, including Photos analysis, media analysis, software updaters and cloud helpers.\n\nEvery process paused by this feature is tracked and resumed when you turn it off, leave low power mode or quit EnduranceLite. Protected system processes and services owned by other users are left alone."
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
            title: "Display Savings",
            systemImage: "sun.max",
            summary: "Uses Apple's Low Power Mode display savings only.",
            detail: "macOS manages display power savings when native Low Power Mode is on. Use Slow Down Processor to enable Low Power Mode.\n\nBrightness continues to follow your macOS display settings. This row shows information about those automatic savings."
        )
    ]

    static func feature(for id: PowerFeatureID) -> PowerFeature {
        all.first { $0.id == id } ?? all[0]
    }
}
