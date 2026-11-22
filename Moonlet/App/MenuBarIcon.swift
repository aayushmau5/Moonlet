import AppKit

enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static let image: NSImage = {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Moonlet"
        return image
    }()

    static func draw(in context: CGContext, rect: CGRect) {
        let scale = rect.width / size.width
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let ringRadius = 7.2 * scale
        let moonAngle = CGFloat.pi / 4.5
        let moon = CGPoint(x: center.x + cos(moonAngle) * ringRadius, y: center.y + sin(moonAngle) * ringRadius)

        context.saveGState()
        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.3 * scale)

        context.addEllipse(in: circle(center, ringRadius))
        context.strokePath()
        context.fillEllipse(in: circle(center, 3.8 * scale))

        context.setBlendMode(.clear)
        context.fillEllipse(in: circle(moon, 3.1 * scale))
        context.setBlendMode(.normal)
        context.fillEllipse(in: circle(moon, 2.0 * scale))
        context.restoreGState()
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
