// Renders the app icon variants and image assets from branding/lemon.png.
// Usage: swift scripts/make_assets.swift
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let lemonURL = root.appending(path: "branding/lemon.png")
guard let src = NSImage(contentsOf: lemonURL), let lemon = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("lemon.png missing") }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Lemon line art recoloured to `tint` (uses the PNG alpha as a mask).
func tinted(_ tint: CGColor) -> CGImage {
    let w = lemon.width, h = lemon.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: lemon)
    ctx.setFillColor(tint)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func render(size: Int, background: ((CGContext, CGRect) -> Void)?, lemonColor: CGColor, fill: CGColor? = nil, scale: CGFloat = 0.56, to path: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    background?(ctx, rect)
    let art = tinted(lemonColor)
    let h = CGFloat(size) * scale
    let w = h * CGFloat(lemon.width) / CGFloat(lemon.height)
    let r = CGRect(x: (CGFloat(size) - w) / 2 + CGFloat(size) * 0.01, y: (CGFloat(size) - h) / 2 - CGFloat(size) * 0.01, width: w, height: h)
    if let fill {
        // Soft lemon fill behind the line art (an ellipse matching the fruit body).
        ctx.saveGState()
        ctx.setFillColor(fill)
        let body = CGRect(x: r.minX + w * 0.075, y: r.minY + h * 0.075, width: w * 0.70, height: h * 0.70)
        ctx.fillEllipse(in: body)
        ctx.restoreGState()
    }
    ctx.draw(art, in: r)
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! out.representation(using: .png, properties: [:])!.write(to: root.appending(path: path))
}

func gradient(_ a: UInt32, _ b: UInt32) -> (CGContext, CGRect) -> Void {
    { ctx, rect in
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(a), color(b)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: rect.maxX, y: 0), options: [])
    }
}

let icon = "Popote/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(at: root.appending(path: icon), withIntermediateDirectories: true)
render(size: 1024, background: gradient(0xFBF4E4, 0xF1E3C4), lemonColor: color(0x1F3157), fill: color(0xF3DC7A), to: "\(icon)/icon-light.png")
render(size: 1024, background: nil, lemonColor: color(0xE8CF6E), fill: color(0xE8CF6E, 0.18), to: "\(icon)/icon-dark.png")
render(size: 1024, background: nil, lemonColor: color(0xFFFFFF), fill: color(0xFFFFFF, 0.22), to: "\(icon)/icon-tinted.png")

let lemonSet = "Popote/Resources/Assets.xcassets/Lemon.imageset"
try? FileManager.default.createDirectory(at: root.appending(path: lemonSet), withIntermediateDirectories: true)
try! FileManager.default.copyItem(at: lemonURL, to: root.appending(path: "\(lemonSet)/lemon.png"))
let launchSet = "Popote/Resources/Assets.xcassets/LaunchLemon.imageset"
try? FileManager.default.createDirectory(at: root.appending(path: launchSet), withIntermediateDirectories: true)
render(size: 300, background: nil, lemonColor: color(0x1F3157), to: "\(launchSet)/launch-light.png")
render(size: 300, background: nil, lemonColor: color(0xE8CF6E), to: "\(launchSet)/launch-dark.png")
// Small website/Pages icon
render(size: 512, background: gradient(0xFBF4E4, 0xF1E3C4), lemonColor: color(0x1F3157), fill: color(0xF3DC7A), to: "branding/icon-512.png")
print("ok")
