import SwiftUI
import AppKit

struct WindowChrome: NSViewRepresentable {
    var width: CGFloat = 900
    var height: CGFloat = 610

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView)
        }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.setContentSize(NSSize(width: width, height: height))
        if window.styleMask.contains(.resizable) {
            window.styleMask.remove(.resizable)
        }
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}
