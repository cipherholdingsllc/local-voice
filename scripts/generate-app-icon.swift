#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output.png>\n", stderr)
    exit(64)
}

let pixels = 1_024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to allocate Local Voice icon canvas\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))
let canvas = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.027, green: 0.047, blue: 0.043, alpha: 1).setFill()
canvas.fill()

let tileRect = NSRect(x: 108, y: 108, width: 808, height: 808)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 206, yRadius: 206)
NSColor(calibratedRed: 0.345, green: 0.910, blue: 0.698, alpha: 1).setFill()
tile.fill()

let inset = NSBezierPath(
    roundedRect: tileRect.insetBy(dx: 15, dy: 15),
    xRadius: 191,
    yRadius: 191
)
NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
inset.lineWidth = 5
inset.stroke()

let graphite = NSColor(calibratedRed: 0.027, green: 0.047, blue: 0.043, alpha: 1)
let barWidth: CGFloat = 66
let barSpacing: CGFloat = 38
let barHeights: [CGFloat] = [190, 330, 468, 330, 190]
let totalWidth = CGFloat(barHeights.count) * barWidth
    + CGFloat(barHeights.count - 1) * barSpacing
let startX = (size.width - totalWidth) / 2

graphite.setFill()
for (index, height) in barHeights.enumerated() {
    let x = startX + CGFloat(index) * (barWidth + barSpacing)
    let rect = NSRect(
        x: x,
        y: (size.height - height) / 2,
        width: barWidth,
        height: height
    )
    NSBezierPath(
        roundedRect: rect,
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
    ).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(
    using: .png,
    properties: [.compressionFactor: 1]
) else {
    fputs("Failed to render Local Voice icon\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outputURL, options: .atomic)
