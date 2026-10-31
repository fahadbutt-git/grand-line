#if canImport(AppKit)
import AppKit

/// Draws a glyph on its tile with CoreGraphics, the same shapes
/// tools/make-icons.py draws into the bundled AppIcon.icns.
public enum IconRenderer {
    /// The sizes an icon image holds, in pixels.
    public static let sizes = [16, 32, 64, 128, 256, 512, 1024]

    /// One square bitmap of `pixels` across, or nil if CoreGraphics refuses.
    public static func cgImage(_ glyph: IconGlyph, palette: IconPalette, pixels: Int) -> CGImage? {
        cgImage(marks: IconGlyphs.tile + glyph.marks(pixels: Double(pixels)), pixels: pixels) { palette.color($0) }
    }

    /// The app icon with every size, for NSApp and Finder.
    public static func image(_ glyph: IconGlyph, palette: IconPalette) -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        for pixels in sizes {
            guard let cg = cgImage(glyph, palette: palette, pixels: pixels) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: pixels, height: pixels)
            image.addRepresentation(rep)
        }
        return image
    }

    public static func image(_ glyph: IconGlyph, theme: IconTheme) -> NSImage {
        image(glyph, palette: theme.palette(for: glyph))
    }

    /// The glyph alone in black, as a template image for the menu bar:
    /// quiet fills at a third, everything else solid, no tile.
    public static func templateImage(_ glyph: IconGlyph, points: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points))
        for scale in [1, 2] {
            let pixels = Int(points) * scale
            // The glyph fills more of a menu bar icon than of an app icon.
            let marks = glyph.marks(pixels: Double(pixels))
            guard let cg = cgImage(marks: marks, pixels: pixels, zoom: 1.45, color: { _ in .black },
                                   alpha: { $0 == .soft ? 0.35 : 1 }) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: points, height: points)
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    static func cgImage(marks: [IconMark], pixels: Int, zoom: CGFloat = 1,
                        color: (IconRole) -> IconColor,
                        alpha: (IconRole) -> CGFloat = { _ in 1 }) -> CGImage? {
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let side = CGFloat(pixels)
        let scale = side / CGFloat(IconGlyphs.canvas) * zoom
        // The table's y points down.
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: side / 2, y: side / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -CGFloat(IconGlyphs.canvas) / 2, y: -CGFloat(IconGlyphs.canvas) / 2)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        for mark in marks {
            let c = color(mark.role)
            let cg = CGColor(srgbRed: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: alpha(mark.role))
            draw(mark, in: ctx, color: cg)
        }
        return ctx.makeImage()
    }

    static func draw(_ mark: IconMark, in ctx: CGContext, color: CGColor) {
        let v = mark.values.map { CGFloat($0) }
        func value(_ i: Int) -> CGFloat { i < v.count ? v[i] : 0 }
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let path = CGMutablePath()
        var stroke: CGFloat = 0
        switch mark.kind {
        case .rrect:
            let rect = CGRect(x: value(0), y: value(1), width: value(2), height: value(3))
            let r = min(value(4), rect.width / 2, rect.height / 2)
            path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
        case .disc:
            path.addEllipse(in: CGRect(x: value(0) - value(2), y: value(1) - value(2), width: 2 * value(2), height: 2 * value(2)))
        case .ellipse:
            path.addEllipse(in: CGRect(x: value(0) - value(2), y: value(1) - value(3), width: 2 * value(2), height: 2 * value(3)))
        case .ring:
            path.addEllipse(in: CGRect(x: value(0) - value(2), y: value(1) - value(2), width: 2 * value(2), height: 2 * value(2)))
            stroke = value(3)
        case .arc:
            var end = value(5)
            while end <= value(4) { end += 360 }
            path.addArc(center: CGPoint(x: value(0), y: value(1)), radius: value(2),
                        startAngle: value(4) * .pi / 180, endAngle: end * .pi / 180, clockwise: false)
            stroke = value(3)
        case .segment:
            path.move(to: CGPoint(x: value(0), y: value(1)))
            path.addLine(to: CGPoint(x: value(2), y: value(3)))
            stroke = value(4)
        case .polygon:
            let points = stride(from: 0, to: v.count - 1, by: 2).map { CGPoint(x: v[$0], y: v[$0 + 1]) }
            guard points.count >= 3 else { return }
            path.addLines(between: points)
            path.closeSubpath()
        case .lens:
            let (cx, cy, a, h) = (value(0), value(1), value(2), value(3))
            guard a > 0, h > 0 else { return }
            let r = (a * a + h * h) / (2 * h)
            let upper = CGPoint(x: cx, y: cy - h + r)
            let lower = CGPoint(x: cx, y: cy + h - r)
            path.addArc(center: upper, radius: r, startAngle: atan2(h - r, -a), endAngle: atan2(h - r, a), clockwise: false)
            path.addArc(center: lower, radius: r, startAngle: atan2(r - h, a), endAngle: atan2(r - h, -a), clockwise: false)
            path.closeSubpath()
            stroke = value(4)
        }
        ctx.addPath(path)
        if stroke > 0 {
            ctx.setLineWidth(stroke)
            ctx.strokePath()
        } else {
            ctx.fillPath()
        }
    }
}
#endif
