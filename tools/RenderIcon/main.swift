import AppKit
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   RenderIcon preview <out-dir>     renders the icon and menu bar icon for review
//   RenderIcon appiconset <dir>      writes every app icon size and Contents.json

enum AppIconArt {
    static let canvas: CGFloat = 1024

    static func render(pixels: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let scale = CGFloat(pixels) / canvas
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        draw(in: context, pixelScale: scale)
        return context.makeImage()!
    }

    static func draw(in context: CGContext, pixelScale: CGFloat) {
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(bodyPath)
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.12, blue: 0.25, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(bodyPath)
        context.clip()
        drawSky(in: context, body: body, pixelScale: pixelScale)

        let center = CGPoint(x: 512, y: 500)
        let ringWidth = max(16, 1.4 / pixelScale)
        drawSystem(in: context, center: center, ringWidth: ringWidth)
        context.restoreGState()

        context.addPath(bodyPath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.1))
        context.setLineWidth(max(2, 0.8 / pixelScale))
        context.strokePath()
    }

    static func drawSky(in context: CGContext, body: CGRect, pixelScale: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let sky = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.16, green: 0.10, blue: 0.27, alpha: 1),
            CGColor(srgbRed: 0.08, green: 0.12, blue: 0.27, alpha: 1),
            CGColor(srgbRed: 0.04, green: 0.05, blue: 0.13, alpha: 1),
        ] as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(sky, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.95, green: 0.55, blue: 0.3, alpha: 0.22),
            CGColor(srgbRed: 0.95, green: 0.55, blue: 0.3, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                                   endCenter: CGPoint(x: 512, y: 500), endRadius: 330, options: [])

        guard pixelScale * canvas >= 64 else { return }
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (230, 800, 5), (330, 860, 3.5), (720, 840, 4.5), (820, 720, 3), (190, 600, 3),
            (860, 420, 4), (250, 300, 3.5), (760, 230, 3), (420, 190, 4), (600, 860, 3),
        ]
        context.setFillColor(CGColor(gray: 1, alpha: 0.75))
        for (x, y, r) in stars {
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    static func drawPlanet(in context: CGContext, center: CGPoint, radius: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        context.saveGState()
        context.addEllipse(in: circle(center, radius))
        context.clip()
        let surface = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1.0, green: 0.82, blue: 0.6, alpha: 1),
            CGColor(srgbRed: 0.93, green: 0.55, blue: 0.27, alpha: 1),
            CGColor(srgbRed: 0.55, green: 0.22, blue: 0.13, alpha: 1),
        ] as CFArray, locations: [0, 0.5, 1])!
        let highlight = CGPoint(x: center.x - radius * 0.45, y: center.y + radius * 0.45)
        context.drawRadialGradient(surface, startCenter: highlight, startRadius: 0,
                                   endCenter: center, endRadius: radius * 1.15, options: [.drawsAfterEndLocation])

        let band = CGColor(srgbRed: 0.75, green: 0.36, blue: 0.18, alpha: 0.35)
        context.setFillColor(band)
        context.fill(CGRect(x: center.x - radius, y: center.y - radius * 0.18, width: radius * 2, height: radius * 0.16))
        context.fill(CGRect(x: center.x - radius, y: center.y + radius * 0.28, width: radius * 2, height: radius * 0.08))
        context.restoreGState()
    }

    static func drawMoon(in context: CGContext, center: CGPoint, radius: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        context.saveGState()
        context.setShadow(offset: .zero, blur: radius * 0.8, color: CGColor(gray: 1, alpha: 0.35))
        context.addEllipse(in: circle(center, radius))
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: circle(center, radius))
        context.clip()
        let surface = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.97, green: 0.97, blue: 1, alpha: 1),
            CGColor(srgbRed: 0.6, green: 0.64, blue: 0.75, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(surface, startCenter: CGPoint(x: center.x - radius * 0.4, y: center.y + radius * 0.4),
                                   startRadius: 0, endCenter: center, endRadius: radius * 1.1, options: [.drawsAfterEndLocation])
        context.restoreGState()
    }

    static func drawSystem(in context: CGContext, center: CGPoint, ringWidth: CGFloat) {
        let ringRadius: CGFloat = 300
        context.addEllipse(in: circle(center, ringRadius))
        context.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.87, blue: 1, alpha: 0.55))
        context.setLineWidth(ringWidth)
        context.strokePath()

        drawPlanet(in: context, center: center, radius: 165)

        let angle = CGFloat.pi / 4.5
        let moon = CGPoint(x: center.x + cos(angle) * ringRadius, y: center.y + sin(angle) * ringRadius)
        drawMoon(in: context, center: moon, radius: 52)
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

func save(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func renderMenuBar(background: CGColor, pixelsPerPoint: Int) -> CGImage {
    let side = Int(MenuBarIcon.size.width) * pixelsPerPoint
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let tile = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    MenuBarIcon.draw(in: tile, rect: CGRect(x: 0, y: 0, width: side, height: side))
    let mask = tile.makeImage()!

    let output = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    output.setFillColor(background)
    output.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let isDark = (background.components?.first ?? 0) < 0.5
    output.saveGState()
    output.clip(to: CGRect(x: 0, y: 0, width: side, height: side), mask: mask)
    output.setFillColor(CGColor(gray: isDark ? 0.95 : 0.1, alpha: 0.9))
    output.fill(CGRect(x: 0, y: 0, width: side, height: side))
    output.restoreGState()
    return output.makeImage()!
}

let arguments = CommandLine.arguments
switch arguments.dropFirst().first {
case "preview":
    let out = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    save(AppIconArt.render(pixels: 512), to: out.appending(path: "icon-512.png"))
    save(AppIconArt.render(pixels: 32), to: out.appending(path: "icon-32.png"))
    save(renderMenuBar(background: CGColor(gray: 0.92, alpha: 1), pixelsPerPoint: 2), to: out.appending(path: "bar-light.png"))
    save(renderMenuBar(background: CGColor(gray: 0.17, alpha: 1), pixelsPerPoint: 2), to: out.appending(path: "bar-dark.png"))
case "appiconset":
    let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for factor in [1, 2] {
            let pixels = points * factor
            let file = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
            save(AppIconArt.render(pixels: pixels), to: folder.appending(path: file))
            images.append(["filename": file, "idiom": "mac", "scale": "\(factor)x", "size": "\(points)x\(points)"])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: folder.appending(path: "Contents.json"))
    print("Wrote \(images.count) icons to \(folder.path)")
default:
    print("Usage: RenderIcon preview <out-dir> | RenderIcon appiconset <dir>")
    exit(1)
}
