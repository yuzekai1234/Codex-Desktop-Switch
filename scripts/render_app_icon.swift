#!/usr/bin/env swift
import AppKit

/// Transparent margin so Dock squircle matches system icon scale (~88% plate).
let canvas: CGFloat = 1024
let plateInset: CGFloat = 96
let plateSize = canvas - plateInset * 2
let plateCorner = plateSize * 0.2237

let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    outputPath = root.appendingPathComponent("Resources/AppIcon-1024.png").path
}

let symbolPointSize = plateSize * 0.34
let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
guard let symbol = NSImage(
    systemSymbolName: "arrow.left.arrow.right",
    accessibilityDescription: nil
)?.withSymbolConfiguration(symbolConfig) else {
    fputs("SF Symbol not found\n", stderr)
    exit(1)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let plateRect = NSRect(x: plateInset, y: plateInset, width: plateSize, height: plateSize)
let platePath = NSBezierPath(roundedRect: plateRect, xRadius: plateCorner, yRadius: plateCorner)

if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -plateSize * 0.018),
        blur: plateSize * 0.05,
        color: NSColor.black.withAlphaComponent(0.18).cgColor
    )
    NSColor.white.setFill()
    platePath.fill()
    ctx.restoreGState()
}

platePath.addClip()

guard let plateGradient = NSGradient(colors: [
    NSColor(white: 1.0, alpha: 1),
    NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1),
]) else {
    fputs("Gradient failed\n", stderr)
    exit(1)
}
plateGradient.draw(in: plateRect, angle: 90)

let rim = NSBezierPath(roundedRect: plateRect.insetBy(dx: 1.5, dy: 1.5), xRadius: plateCorner, yRadius: plateCorner)
NSColor.black.withAlphaComponent(0.06).setStroke()
rim.lineWidth = plateSize * 0.006
rim.stroke()

symbol.isTemplate = true
let symbolSize = symbol.size
let symbolRect = NSRect(
    x: plateRect.midX - symbolSize.width / 2,
    y: plateRect.midY - symbolSize.height / 2,
    width: symbolSize.width,
    height: symbolSize.height
)
NSColor(red: 0.12, green: 0.44, blue: 0.92, alpha: 1).set()
symbol.draw(in: symbolRect)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("PNG export failed\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Rendered \(outputPath)")
} catch {
    fputs("Write failed: \(error)\n", stderr)
    exit(1)
}
