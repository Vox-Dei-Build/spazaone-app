#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("scripts/assets/spazaone-cart-mark.png")
let launcherURL = root.appendingPathComponent("assets/images/ic_launcher.png")
let foregroundURL = root.appendingPathComponent("assets/images/ic_launcher_foreground.png")
let monochromeURL = root.appendingPathComponent("assets/images/ic_launcher_monochrome.png")
let previewURL = root.appendingPathComponent("artifacts/aso/app-icon-platform-preview.png")

guard let cart = NSImage(contentsOf: sourceURL) else {
  fputs("Could not load \(sourceURL.path)\n", stderr)
  exit(1)
}

let canvas = 1024
let paper = NSColor(calibratedRed: 0.984, green: 0.980, blue: 0.965, alpha: 1)
let ink = NSColor(calibratedRed: 0.129, green: 0.118, blue: 0.184, alpha: 1)
let mutedInk = NSColor(calibratedRed: 0.34, green: 0.32, blue: 0.40, alpha: 1)
let yellow = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.0, alpha: 1)

func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    fatalError("Could not create bitmap")
  }
  rep.size = NSSize(width: width, height: height)
  return rep
}

func withContext(_ rep: NSBitmapImageRep, draw: () -> Void) {
  guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create graphics context")
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  draw()
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
  guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
  }
  try! data.write(to: url)
}

func drawCart(in rect: NSRect, shadow: Bool) {
  if shadow {
    let dropShadow = NSShadow()
    dropShadow.shadowColor = ink.withAlphaComponent(0.23)
    dropShadow.shadowBlurRadius = 22
    dropShadow.shadowOffset = NSSize(width: 0, height: -13)
    dropShadow.set()
  }
  cart.draw(
    in: rect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
  )
  NSShadow().set()
}

// Opaque master for iOS and Android legacy launchers. The light field and
// subtle depth preserve the previous Pasella icon treatment users liked.
let launcher = bitmap(width: canvas, height: canvas)
withContext(launcher) {
  paper.setFill()
  NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
  drawCart(in: NSRect(x: -42, y: -30, width: 1108, height: 1108), shadow: true)
}
writePNG(launcher, to: launcherURL)

// Android adaptive foreground: keep the complete mark inside the safe zone so
// circles, squircles and rounded-square launchers all retain both wheels.
let foreground = bitmap(width: canvas, height: canvas)
withContext(foreground) {
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
  drawCart(in: NSRect(x: -24, y: -18, width: 1072, height: 1072), shadow: true)
}
writePNG(foreground, to: foregroundURL)

// Android 13 themed icon mask.
let monochrome = bitmap(width: canvas, height: canvas)
withContext(monochrome) {
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
  cart.draw(
    in: NSRect(x: -24, y: -18, width: 1072, height: 1072),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
  )
  ink.setFill()
  NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceIn)
}
writePNG(monochrome, to: monochromeURL)

func drawLabel(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: color,
  ]
  text.draw(at: point, withAttributes: attributes)
}

func drawMaskedIcon(_ image: NSBitmapImageRep, in rect: NSRect, radius: CGFloat, circle: Bool) {
  NSGraphicsContext.saveGraphicsState()
  let path = circle ? NSBezierPath(ovalIn: rect) : NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  path.addClip()
  image.draw(in: rect)
  NSGraphicsContext.restoreGraphicsState()

  ink.withAlphaComponent(0.10).setStroke()
  path.lineWidth = 2
  path.stroke()
}

// Review sheet makes platform mask and small-size problems visible before a
// release is tagged.
let preview = bitmap(width: 1600, height: 760)
withContext(preview) {
  ink.setFill()
  NSRect(x: 0, y: 0, width: 1600, height: 760).fill()
  drawLabel("SpazaOne app icon", at: NSPoint(x: 90, y: 664), size: 54, color: .white, weight: .bold)
  drawLabel("Platform-safe preview", at: NSPoint(x: 92, y: 620), size: 25, color: yellow, weight: .semibold)

  let iconSize: CGFloat = 310
  let y: CGFloat = 214
  let positions: [(CGFloat, String, CGFloat, Bool)] = [
    (110, "Android · circle", iconSize / 2, true),
    (645, "Android · rounded", 92, false),
    (1180, "iOS", 72, false),
  ]

  for (x, label, radius, circle) in positions {
    let rect = NSRect(x: x, y: y, width: iconSize, height: iconSize)
    drawMaskedIcon(launcher, in: rect, radius: radius, circle: circle)
    drawLabel(label, at: NSPoint(x: x, y: 150), size: 24, color: .white, weight: .semibold)
  }

  drawLabel("Light field · complete cart · safe margins", at: NSPoint(x: 90, y: 64), size: 23, color: mutedInk.blended(withFraction: 0.72, of: .white) ?? .lightGray, weight: .regular)
}
writePNG(preview, to: previewURL)

print("Generated launcher masters and \(previewURL.path)")
