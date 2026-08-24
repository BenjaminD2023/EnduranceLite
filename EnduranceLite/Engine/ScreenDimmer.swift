import CoreGraphics
import Darwin
import Foundation

final class ScreenDimmer {
    private var originalBrightness: Float?
    private var targetBrightness: Float = 0.35
    private var timer: Timer?
    private var userOverride = false

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightness: GetBrightnessFn?
    private var setBrightness: SetBrightnessFn?
    private var handle: UnsafeMutableRawPointer?

    var isAvailable: Bool { setBrightness != nil && getBrightness != nil }

    init() {
        let paths = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
        ]
        for path in paths {
            if let loaded = dlopen(path, RTLD_LAZY) {
                handle = loaded
                break
            }
        }
        if let handle {
            if let getPtr = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightness = unsafeBitCast(getPtr, to: GetBrightnessFn.self)
            }
            if let setPtr = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightness = unsafeBitCast(setPtr, to: SetBrightnessFn.self)
            }
        }
        if getBrightness == nil || setBrightness == nil || !probe() {
            getBrightness = nil
            setBrightness = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func start() {
        guard isAvailable else { return }
        stopTimer()
        userOverride = false
        let current = readBrightness() ?? 1.0
        originalBrightness = current
        targetBrightness = max(0.18, current * 0.58)
        if current <= targetBrightness + 0.02 { return }

        timer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.4
    }

    func restore() {
        stopTimer()
        userOverride = false
        if let original = originalBrightness {
            _ = writeBrightness(original)
        }
        originalBrightness = nil
    }

    private func tick() {
        guard !userOverride else { return }
        guard let current = readBrightness() else { return }
        // If the user raised brightness, get out of the way.
        if let original = originalBrightness, current > original + 0.03 {
            userOverride = true
            stopTimer()
            return
        }
        if current <= targetBrightness + 0.01 {
            stopTimer()
            return
        }
        let next = max(targetBrightness, current - 0.025)
        _ = writeBrightness(next)
    }

    private func probe() -> Bool {
        var value: Float = 0
        guard let getBrightness, let setBrightness else { return false }
        let display = CGMainDisplayID()
        // A successful get should return 0.
        let got = getBrightness(display, &value)
        return got == 0 && value >= 0 && value <= 1.5
    }

    private func readBrightness() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        let status = getBrightness(CGMainDisplayID(), &value)
        return status == 0 ? value : nil
    }

    @discardableResult
    private func writeBrightness(_ value: Float) -> Bool {
        guard let setBrightness else { return false }
        return setBrightness(CGMainDisplayID(), max(0, min(1, value))) == 0
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
