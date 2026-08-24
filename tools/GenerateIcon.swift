#!/usr/bin/env swift
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true
    NSGraphicsContext.current = ctx

    let s = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // Soft squircle backdrop
    let inset = s * 0.08
    let backdrop = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2), xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.95, alpha: 1).setFill()
    backdrop.fill()

    drawBattery(in: NSRect(x: s * 0.16, y: s * 0.30, width: s * 0.68, height: s * 0.40))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawBattery(in rect: NSRect) {
    let nubW = rect.width * 0.09
    let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width - nubW, height: rect.height)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: body.height * 0.22, yRadius: body.height * 0.22)

    let nub = NSRect(
        x: body.maxX - 1,
        y: rect.midY - rect.height * 0.16,
        width: nubW + 1,
        height: rect.height * 0.32
    )
    let nubPath = NSBezierPath(roundedRect: nub, xRadius: nub.height * 0.35, yRadius: nub.height * 0.35)

    let combined = NSBezierPath()
    combined.append(bodyPath)
    combined.append(nubPath)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.04)
    shadow.shadowBlurRadius = rect.height * 0.08
    shadow.set()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.55, green: 0.86, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.30, green: 0.72, blue: 0.28, alpha: 1)
    ])!
    gradient.draw(in: combined, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    gradient.draw(in: combined, angle: -90)

    // Gloss
    let gloss = NSBezierPath(roundedRect: NSRect(x: body.minX + 2, y: body.midY, width: body.width - 4, height: body.height * 0.46), xRadius: body.height * 0.18, yRadius: body.height * 0.18)
    NSColor.white.withAlphaComponent(0.22).setFill()
    gloss.fill()

    drawInfinity(in: NSRect(
        x: body.minX + body.width * 0.16,
        y: body.minY + body.height * 0.28,
        width: body.width * 0.68,
        height: body.height * 0.44
    ), lineWidth: body.height * 0.13)
}

func drawInfinity(in rect: NSRect, lineWidth: CGFloat) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = lineWidth

    let mid = NSPoint(x: rect.midX, y: rect.midY)
    path.move(to: mid)
    path.curve(
        to: mid,
        controlPoint1: NSPoint(x: rect.minX - rect.width * 0.05, y: rect.maxY + rect.height * 0.15),
        controlPoint2: NSPoint(x: rect.minX - rect.width * 0.05, y: rect.minY - rect.height * 0.15)
    )
    path.curve(
        to: mid,
        controlPoint1: NSPoint(x: rect.maxX + rect.width * 0.05, y: rect.maxY + rect.height * 0.15),
        controlPoint2: NSPoint(x: rect.maxX + rect.width * 0.05, y: rect.minY - rect.height * 0.15)
    )

    NSColor.white.withAlphaComponent(0.96).setStroke()
    path.stroke()
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
    try! data.write(to: url)
}

let master = render(size: 1024)
let masterURL = URL(fileURLWithPath: outDir).appendingPathComponent("icon_1024.png")
writePNG(master, to: masterURL)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let rep = render(size: px)
    writePNG(rep, to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}

print("Wrote icons to \(outDir)")
