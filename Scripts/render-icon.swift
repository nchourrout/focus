// Generates a simple app icon PNG. Called from build-app.sh, which then
// runs sips/iconutil to produce AppIcon.icns inside the bundle.

import AppKit

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// Apple-style rounded square background (radius ≈ 22.37% of the side).
let radius = size * 0.2237
let bg = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: radius, yRadius: radius
)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.96, green: 0.34, blue: 0.32, alpha: 1.0),
    NSColor(calibratedRed: 0.78, green: 0.18, blue: 0.16, alpha: 1.0),
])!
gradient.draw(in: bg, angle: 90)

// Centered glyph. ⏱ keeps emoji color rendering across macOS versions.
let glyph = "⏱"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 660, weight: .regular),
    .foregroundColor: NSColor.white,
]
let str = NSAttributedString(string: glyph, attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2 - 50))

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("render-icon: failed to encode PNG\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
try png.write(to: URL(fileURLWithPath: outPath))
