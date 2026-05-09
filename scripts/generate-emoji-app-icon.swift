#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("usage: \(CommandLine.arguments[0]) <output.png>\n", stderr)
    exit(1)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: false)
let w = 1024
let h = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: w,
    pixelsHigh: h,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create bitmap.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = NSSize(width: w, height: h)
let corner: CGFloat = 220
let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: corner, yRadius: corner)
NSColor(red: 0.10, green: 0.08, blue: 0.18, alpha: 1).setFill()
bgPath.fill()

let emoji = "🚀"
let fontSize: CGFloat = 560
let font = NSFont(name: "Apple Color Emoji", size: fontSize)
    ?? NSFont(name: "AppleColorEmoji", size: fontSize)
    ?? NSFont.systemFont(ofSize: fontSize)
let attributed = NSAttributedString(string: emoji, attributes: [.font: font])
let textSize = attributed.size()
let x = (CGFloat(w) - textSize.width) / 2
let y = (CGFloat(h) - textSize.height) / 2 - 36
attributed.draw(in: NSRect(x: x, y: y, width: textSize.width, height: textSize.height))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG.\n", stderr)
    exit(1)
}

do {
    try png.write(to: outURL)
} catch {
    fputs("Write failed: \(error)\n", stderr)
    exit(1)
}

print("Wrote \(outURL.path)")
