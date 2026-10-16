import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        let rect = NSRect(x: 0, y: 0, width: s, height: s)
        NSColor(red: 0.055, green: 0.075, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.04, dy: s * 0.04), xRadius: s * 0.22, yRadius: s * 0.22).fill()
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: s * 0.15, y: s * 0.28))
        mountain.line(to: NSPoint(x: s * 0.46, y: s * 0.77))
        mountain.line(to: NSPoint(x: s * 0.64, y: s * 0.49))
        mountain.line(to: NSPoint(x: s * 0.73, y: s * 0.61))
        mountain.line(to: NSPoint(x: s * 0.89, y: s * 0.28))
        mountain.close()
        NSColor(red: 0.52, green: 0.94, blue: 0.77, alpha: 1).setFill()
        mountain.fill()
        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: s * 0.36, y: s * 0.61))
        cap.line(to: NSPoint(x: s * 0.46, y: s * 0.77))
        cap.line(to: NSPoint(x: s * 0.56, y: s * 0.61))
        cap.line(to: NSPoint(x: s * 0.46, y: s * 0.65))
        cap.close()
        NSColor.white.setFill()
        cap.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
