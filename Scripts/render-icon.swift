// Generates the Focus app icon as a 1024×1024 PNG. Called from build-app.sh,
// which downsamples through sips/iconutil into the bundle's AppIcon.icns.
//
// Design: red rounded-square (pomodoro hue), white dial face inside it. The
// outer ring is split into a 25-minute red arc (work) and a 5-minute green
// arc (break) — exactly the proportions of one pomodoro session. Charcoal
// hour ticks and a hand sitting just past 12 imply "in progress".

import AppKit

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// ---------- Background: red rounded square ----------

let cornerRadius = size * 0.2237  // Apple-style superellipse-ish proportion
let bg = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: cornerRadius, yRadius: cornerRadius
)
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.30, blue: 0.27, alpha: 1.0),
    NSColor(calibratedRed: 0.62, green: 0.10, blue: 0.13, alpha: 1.0),
])!
bgGradient.draw(in: bg, angle: 90)

// Subtle top-edge sheen for depth.
let sheen = NSBezierPath(
    roundedRect: NSRect(x: size * 0.02, y: size * 0.55, width: size * 0.96, height: size * 0.43),
    xRadius: cornerRadius * 0.95, yRadius: cornerRadius * 0.95
)
NSGraphicsContext.saveGraphicsState()
sheen.addClip()
let sheenGradient = NSGradient(colors: [
    NSColor(white: 1.0, alpha: 0.10),
    NSColor(white: 1.0, alpha: 0.0),
])!
sheenGradient.draw(in: bg, angle: 90)
NSGraphicsContext.restoreGraphicsState()

// ---------- Dial face: white filled disc ----------

let center = NSPoint(x: size / 2, y: size / 2)
let dialRadius: CGFloat = size * 0.395
let face = NSBezierPath(ovalIn: NSRect(
    x: center.x - dialRadius, y: center.y - dialRadius,
    width: dialRadius * 2, height: dialRadius * 2
))
NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1.0).setFill()
face.fill()

// ---------- 25/5 work-break ring on a 60-minute dial face ----------
//
// Treat the dial as a real 60-minute clock face: each minute = 6°. The
// pomodoro is the first 30 minutes (top half of the dial):
//   • 0 → 25 min red work, sweeping 12 → 5 o'clock (150°)
//   • 25 → 30 min green break, sweeping 5 → 6 o'clock (30°)
// AppKit angles are math-style (0° at 3 o'clock, CCW positive). 12 o'clock
// is 90°; CW sweeps reduce the angle.

let ringRadius: CGFloat = dialRadius - size * 0.045
let ringWidth: CGFloat = size * 0.060

let degreesPerMinute: CGFloat = 6
let topAngle: CGFloat = 90                              // 0 min, 12 o'clock
let work25Angle: CGFloat = topAngle - 25 * degreesPerMinute  // -60° (5 o'clock)
let break30Angle: CGFloat = topAngle - 30 * degreesPerMinute // -90° (6 o'clock)

let workArc = NSBezierPath()
workArc.appendArc(
    withCenter: center,
    radius: ringRadius,
    startAngle: topAngle,
    endAngle: work25Angle,
    clockwise: true
)
workArc.lineWidth = ringWidth
workArc.lineCapStyle = .butt
NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.20, alpha: 1.0).setStroke()
workArc.stroke()

let breakArc = NSBezierPath()
breakArc.appendArc(
    withCenter: center,
    radius: ringRadius,
    startAngle: work25Angle,
    endAngle: break30Angle,
    clockwise: true
)
breakArc.lineWidth = ringWidth
breakArc.lineCapStyle = .butt
NSColor(calibratedRed: 0.27, green: 0.70, blue: 0.42, alpha: 1.0).setStroke()
breakArc.stroke()

// ---------- Hour ticks: charcoal, every 30°, longer at quarters ----------

let charcoal = NSColor(calibratedRed: 0.16, green: 0.13, blue: 0.13, alpha: 1.0)
let tickInner: CGFloat = ringRadius - ringWidth * 1.45
let tickOuterMajor: CGFloat = ringRadius - ringWidth * 0.65
let tickOuterMinor: CGFloat = ringRadius - ringWidth * 0.95
for i in 0..<12 {
    let angle = CGFloat(i) * .pi / 6 + .pi / 2  // start at 12
    let isMajor = (i % 3 == 0)
    let outerR = isMajor ? tickOuterMajor : tickOuterMinor
    let p = NSBezierPath()
    p.move(to: NSPoint(
        x: center.x + cos(angle) * tickInner,
        y: center.y + sin(angle) * tickInner
    ))
    p.line(to: NSPoint(
        x: center.x + cos(angle) * outerR,
        y: center.y + sin(angle) * outerR
    ))
    p.lineWidth = isMajor ? size * 0.020 : size * 0.012
    p.lineCapStyle = .round
    charcoal.setStroke()
    p.stroke()
}

// ---------- Hand: charcoal, pointing at the 25-minute mark (5 o'clock) ----------

let handAngle: CGFloat = work25Angle * .pi / 180
let handLength: CGFloat = ringRadius - ringWidth * 1.2
let handBaseOffset: CGFloat = size * 0.022
let hand = NSBezierPath()
hand.move(to: NSPoint(
    x: center.x - cos(handAngle) * handBaseOffset,
    y: center.y - sin(handAngle) * handBaseOffset
))
hand.line(to: NSPoint(
    x: center.x + cos(handAngle) * handLength,
    y: center.y + sin(handAngle) * handLength
))
hand.lineWidth = size * 0.028
hand.lineCapStyle = .round
charcoal.setStroke()
hand.stroke()

// ---------- Center pivot ----------

let pivotRadius: CGFloat = size * 0.030
let pivot = NSBezierPath(ovalIn: NSRect(
    x: center.x - pivotRadius, y: center.y - pivotRadius,
    width: pivotRadius * 2, height: pivotRadius * 2
))
charcoal.setFill()
pivot.fill()

canvas.unlockFocus()

// ---------- Encode and write ----------

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("render-icon: failed to encode PNG\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
try png.write(to: URL(fileURLWithPath: outPath))
