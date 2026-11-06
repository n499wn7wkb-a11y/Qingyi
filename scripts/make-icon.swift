import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let rect = NSRect(x: 62 * scale, y: 62 * scale, width: 900 * scale, height: 900 * scale)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 205 * scale, yRadius: 205 * scale)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.52, blue: 0.94, alpha: 1), ending: NSColor(srgbRed: 0.14, green: 0.31, blue: 0.70, alpha: 1))!
    gradient.draw(in: shape, angle: -80)
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 525 * scale, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
    ("译" as NSString).draw(in: NSRect(x: 100 * scale, y: 175 * scale, width: 824 * scale, height: 650 * scale), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
