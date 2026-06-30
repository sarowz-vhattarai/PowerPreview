#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/icon"
ICONSET="$BUILD_DIR/PowerPreview.iconset"
ICNS_PATH="$BUILD_DIR/PowerPreview.icns"
GENERATOR="$BUILD_DIR/IconGenerator.swift"

rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET"

cat > "$GENERATOR" <<'SWIFT'
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconFiles: [(String, Int)] = [
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

func drawIcon(size: Int, at url: URL) throws {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "PowerPreviewIcon", code: 1)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let background = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.20, alpha: 1).setFill()
    background.fill()

    let glowRect = rect.insetBy(dx: CGFloat(size) * 0.08, dy: CGFloat(size) * 0.08)
    let glow = NSBezierPath(ovalIn: glowRect)
    NSColor(calibratedRed: 0.15, green: 0.55, blue: 1.0, alpha: 0.28).setFill()
    glow.fill()

    let frameRect = rect.insetBy(dx: CGFloat(size) * 0.18, dy: CGFloat(size) * 0.24)
    let frame = NSBezierPath(roundedRect: frameRect, xRadius: CGFloat(size) * 0.06, yRadius: CGFloat(size) * 0.06)
    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    frame.fill()

    let screenRect = frameRect.insetBy(dx: CGFloat(size) * 0.035, dy: CGFloat(size) * 0.035)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: CGFloat(size) * 0.035, yRadius: CGFloat(size) * 0.035)
    NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.08, alpha: 1).setFill()
    screen.fill()

    let playSize = CGFloat(size) * 0.18
    let center = CGPoint(x: rect.midX + CGFloat(size) * 0.025, y: rect.midY)
    let play = NSBezierPath()
    play.move(to: CGPoint(x: center.x - playSize * 0.45, y: center.y - playSize * 0.62))
    play.line(to: CGPoint(x: center.x - playSize * 0.45, y: center.y + playSize * 0.62))
    play.line(to: CGPoint(x: center.x + playSize * 0.68, y: center.y))
    play.close()
    NSColor(calibratedRed: 0.13, green: 0.62, blue: 1.0, alpha: 1).setFill()
    play.fill()

    let photoCircleRect = CGRect(
        x: screenRect.minX + CGFloat(size) * 0.08,
        y: screenRect.maxY - CGFloat(size) * 0.18,
        width: CGFloat(size) * 0.075,
        height: CGFloat(size) * 0.075
    )
    NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: photoCircleRect).fill()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PowerPreviewIcon", code: 2)
    }

    try png.write(to: url)
}

for (name, size) in iconFiles {
    try drawIcon(size: size, at: outputDirectory.appendingPathComponent(name))
}
SWIFT

swift "$GENERATOR" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS_PATH"
echo "$ICNS_PATH"
