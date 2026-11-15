#if canImport(AppKit)
import AppKit
import CoreText
import WebGraphics

/// Paints a `DisplayList` into a CoreGraphics context whose coordinate system is the display
/// list's: points, origin at the top left, y down (a flipped `NSView`, or a bitmap context the
/// caller flipped). Text is drawn with CoreText, images from the asset base directory.
@MainActor
public final class CoreGraphicsPainter {
    public let textEngine: CoreTextEngine
    /// The directory the asset manifest's files are relative to.
    public var assetBase: URL?
    private var images: [String: CGImage] = [:]
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init(textEngine: CoreTextEngine, assetBase: URL? = nil) {
        self.textEngine = textEngine
        self.assetBase = assetBase
    }

    /// An open group: a transparency layer, or a bitmap the parent composites after filtering.
    private enum Group {
        case layer
        case bitmap(parent: CGContext, filter: DisplayFilter, device: CGRect, sigma: CGFloat)
        /// The mask draws into a bitmap; `beginMasked` turns it into a clip on the parent.
        case mask(parent: CGContext, device: CGRect)
        case masked
    }

    public func paint(_ list: DisplayList, into root: CGContext) {
        var ctx = root
        var groups: [Group] = []
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        for command in list.commands {
            switch command {
            case .beginFilter(let filter, let bounds):
                // The group paints into a bitmap covering the content's device-space box (a
                // soft blur reaches three sigma further); `endGroup` filters it and draws it back.
                let ctm = ctx.ctm
                let scale = (ctm.a * ctm.a + ctm.b * ctm.b).squareRoot()
                var sigma: CGFloat = 0, pad: CGFloat = 0
                if case .blur(let radius, let opaque) = filter {
                    sigma = radius * scale
                    pad = opaque ? 0 : (sigma * 3).rounded(.up)
                }
                let device = bounds.applying(ctm).insetBy(dx: -pad, dy: -pad).integral
                guard device.width >= 1, device.height >= 1,
                      let bitmap = CGContext(data: nil, width: Int(device.width), height: Int(device.height), bitsPerComponent: 8, bytesPerRow: 0,
                                             space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else {
                    ctx.saveGState()
                    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                    groups.append(.layer)
                    continue
                }
                bitmap.setAllowsAntialiasing(true)
                bitmap.setShouldAntialias(true)
                bitmap.translateBy(x: -device.minX, y: -device.minY)
                bitmap.concatenate(ctm)
                groups.append(.bitmap(parent: ctx, filter: filter, device: device, sigma: sigma))
                ctx = bitmap
            case .backdropBlur(let path, let bounds, let radius, let saturation):
                // Snapshot the device box under the path (three sigma around it), blur the
                // copy keeping its alpha, and draw it back clipped to the path.
                let ctm = ctx.ctm
                let scale = (ctm.a * ctm.a + ctm.b * ctm.b).squareRoot()
                let sigma = radius * scale
                let pad = (sigma * 3).rounded(.up)
                let device = bounds.applying(ctm).insetBy(dx: -pad, dy: -pad).integral.intersection(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
                // A wide blur works on a copy shrunk so its sigma is about four pixels, drawn
                // back smoothly: the same look at a fraction of the taps.
                let shrink = max(1, (sigma / 4).rounded(.down))
                let size = CGSize(width: max(1, (device.width / shrink).rounded()), height: max(1, (device.height / shrink).rounded()))
                guard sigma > 0, device.width >= 1, device.height >= 1, let snapshot = ctx.makeImage(),
                      let crop = snapshot.cropping(to: CGRect(x: device.minX, y: CGFloat(ctx.height) - device.maxY, width: device.width, height: device.height)),
                      let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                             space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                bitmap.interpolationQuality = .default
                bitmap.draw(crop, in: CGRect(origin: .zero, size: size))
                Self.apply(.blur(radius: radius, opaque: true), to: bitmap, sigma: sigma / shrink)
                if saturation != 1 { Self.apply(.colorMatrix(.saturation(saturation)), to: bitmap, sigma: 0) }
                guard let blurred = bitmap.makeImage() else { continue }
                ctx.saveGState()
                ctx.addPath(Self.cgPath(path))
                ctx.clip()
                ctx.concatenate(ctm.inverted())
                ctx.interpolationQuality = shrink > 1 ? .default : .none
                ctx.draw(blurred, in: device)
                ctx.restoreGState()
            case .beginMask(let bounds):
                let ctm = ctx.ctm
                let device = bounds.applying(ctm).integral
                guard device.width >= 1, device.height >= 1,
                      let bitmap = CGContext(data: nil, width: Int(device.width), height: Int(device.height), bitsPerComponent: 8, bytesPerRow: 0,
                                             space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else {
                    // Nothing can show: clip everything away until the group ends.
                    ctx.saveGState()
                    ctx.clip(to: .null)
                    groups.append(.mask(parent: ctx, device: .null))
                    continue
                }
                bitmap.setAllowsAntialiasing(true)
                bitmap.setShouldAntialias(true)
                bitmap.translateBy(x: -device.minX, y: -device.minY)
                bitmap.concatenate(ctm)
                groups.append(.mask(parent: ctx, device: device))
                ctx = bitmap
            case .beginMasked:
                guard case .mask(let parent, let device)? = groups.popLast() else { continue }
                if device.isNull {
                    groups.append(.masked)
                    continue
                }
                let image = ctx.makeImage()
                ctx = parent
                ctx.saveGState()
                if let image {
                    // The clip is set in base space, where the mask bitmap was drawn.
                    let ctm = ctx.ctm
                    ctx.concatenate(ctm.inverted())
                    ctx.clip(to: device, mask: image)
                    ctx.concatenate(ctm)
                } else {
                    ctx.clip(to: .null)
                }
                groups.append(.masked)
            case .beginBlend(let mode, _):
                ctx.saveGState()
                ctx.setBlendMode(Self.cgBlendMode(mode))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                groups.append(.layer)
            case .endGroup:
                switch groups.popLast() {
                case .bitmap(let parent, let filter, let device, let sigma):
                    Self.apply(filter, to: ctx, sigma: sigma)
                    if let image = ctx.makeImage() {
                        parent.saveGState()
                        parent.concatenate(parent.ctm.inverted())
                        parent.interpolationQuality = .none
                        parent.draw(image, in: device)
                        parent.restoreGState()
                    }
                    ctx = parent
                case .masked:
                    ctx.restoreGState()
                case .mask(let parent, let device):
                    // A mask without content: drop the bitmap (or the empty clip).
                    ctx = parent
                    if device.isNull { ctx.restoreGState() }
                default:
                    ctx.endTransparencyLayer()
                    ctx.restoreGState()
                }
            case .save: ctx.saveGState()
            case .restore: ctx.restoreGState()
            case .clipRect(let rect): ctx.clip(to: rect)
            case .clipRRect(let rect, let radius):
                ctx.addPath(Self.roundedPath(rect, radius: radius))
                ctx.clip()
            case .clipPath(let path, let eo):
                ctx.addPath(Self.cgPath(path))
                ctx.clip(using: eo ? .evenOdd : .winding)
            case .beginGroup(let opacity):
                ctx.saveGState()
                ctx.setAlpha(CGFloat(opacity))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                groups.append(.layer)
            case .beginShadow(let color, let radius, let offset):
                ctx.saveGState()
                // CoreGraphics takes the offset and blur in base (device) space, y up; the blur
                // is twice the Gaussian sigma, and SwiftUI's radius is the sigma in points.
                let ctm = ctx.ctm
                let sx = (ctm.a * ctm.a + ctm.b * ctm.b).squareRoot(), sy = (ctm.c * ctm.c + ctm.d * ctm.d).squareRoot()
                let flipped = ctm.d < 0
                ctx.setShadow(offset: CGSize(width: offset.width * sx, height: (flipped ? -offset.height : offset.height) * sy),
                              blur: radius * 2 * max(sx, sy), color: Self.cgColor(color))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                groups.append(.layer)
            case .concat(let transform): ctx.concatenate(transform)
            case .fillRect(let rect, let color):
                ctx.setFillColor(Self.cgColor(color))
                ctx.fill(rect)
            case .fillRRect(let rect, let radius, let color):
                ctx.setFillColor(Self.cgColor(color))
                ctx.addPath(Self.roundedPath(rect, radius: radius))
                ctx.fillPath()
            case .fillPath(let path, let color, let eo):
                ctx.setFillColor(Self.cgColor(color))
                ctx.addPath(Self.cgPath(path))
                ctx.fillPath(using: eo ? .evenOdd : .winding)
            case .strokePath(let path, let style, let color):
                ctx.setStrokeColor(Self.cgColor(color))
                Self.apply(style, to: ctx)
                ctx.addPath(Self.cgPath(path))
                ctx.strokePath()
            case .fillGradient(let path, let gradient, let eo):
                ctx.saveGState()
                ctx.addPath(Self.cgPath(path))
                ctx.clip(using: eo ? .evenOdd : .winding)
                Self.draw(gradient, in: ctx)
                ctx.restoreGState()
            case .strokeGradient(let path, let style, let gradient):
                ctx.saveGState()
                Self.apply(style, to: ctx)
                ctx.addPath(Self.cgPath(path))
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                Self.draw(gradient, in: ctx)
                ctx.restoreGState()
            case .drawText(let text, let font, let origin, let color):
                drawText(text, font: font, at: origin, color: color, gradient: nil, in: ctx)
            case .drawTextGradient(let text, let font, let origin, let gradient):
                drawText(text, font: font, at: origin, color: .black, gradient: gradient, in: ctx)
            case .drawImage(let draw):
                drawImage(draw, in: ctx)
            case .drawBitmap(let bitmap, let rect):
                if let image = Self.image(bitmap) { draw(image, in: rect, ctx: ctx) }
            // Segments and cull blocks only mark the commands: this painter draws every frame's
            // whole list (only a host that keeps segments is sent `reuseSegment`).
            case .beginSegment, .endSegment, .reuseSegment, .beginCullBlock, .endCullBlock: break
            }
        }
        ctx.restoreGState()
    }

    // MARK: Filters and blending

    /// Filters a bitmap context's premultiplied pixels in place.
    private static func apply(_ filter: DisplayFilter, to bitmap: CGContext, sigma: CGFloat) {
        guard let data = bitmap.data else { return }
        let pixels = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bitmap.bytesPerRow * bitmap.height)
        switch filter {
        case .colorMatrix(let matrix):
            matrix.apply(toPremultiplied: pixels)
        case .blur(_, let opaque):
            // Rows may be padded: blur row by row into a packed copy when they are.
            let width = bitmap.width, height = bitmap.height
            if bitmap.bytesPerRow == width * 4 {
                PixelFilters.gaussianBlur(pixels, width: width, height: height, sigma: Double(sigma), keepAlpha: opaque)
            } else {
                var packed = [UInt8](repeating: 0, count: width * height * 4)
                for y in 0..<height { for i in 0..<(width * 4) { packed[y * width * 4 + i] = pixels[y * bitmap.bytesPerRow + i] } }
                packed.withUnsafeMutableBufferPointer { PixelFilters.gaussianBlur($0, width: width, height: height, sigma: Double(sigma), keepAlpha: opaque) }
                for y in 0..<height { for i in 0..<(width * 4) { pixels[y * bitmap.bytesPerRow + i] = packed[y * width * 4 + i] } }
            }
        }
    }

    static func cgBlendMode(_ mode: BlendMode) -> CGBlendMode {
        switch mode {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        case .sourceAtop: return .sourceAtop
        case .destinationOver: return .destinationOver
        case .destinationOut: return .destinationOut
        case .plusDarker: return .plusDarker
        case .plusLighter: return .plusLighter
        }
    }

    // MARK: Geometry and colour

    static func cgColor(_ color: RGBA) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [CGFloat(color.red), CGFloat(color.green), CGFloat(color.blue), CGFloat(color.alpha)])!
    }

    static func cgPath(_ path: Path) -> CGPath {
        let result = CGMutablePath()
        for element in path.elements {
            switch element {
            case .move(let to): result.move(to: to)
            case .line(let to): result.addLine(to: to)
            case .quadCurve(let to, let control): result.addQuadCurve(to: to, control: control)
            case .curve(let to, let c1, let c2): result.addCurve(to: to, control1: c1, control2: c2)
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
    }

    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: rect, transform: nil)
    }

    static func apply(_ style: StrokeStyle, to ctx: CGContext) {
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(style.lineCap)
        ctx.setLineJoin(style.lineJoin)
        ctx.setMiterLimit(style.miterLimit)
        ctx.setLineDash(phase: style.dashPhase, lengths: style.dash)
    }

    /// Draws a gradient over the current clip. Linear and radial map to CoreGraphics; an angular
    /// gradient is painted as 256 wedges of the interpolated stop colours.
    static func draw(_ gradient: DisplayGradient, in ctx: CGContext) {
        let stops = gradient.stops
        guard !stops.isEmpty else { return }
        let colors = stops.map { cgColor($0.color) } as CFArray
        let locations = stops.map { CGFloat($0.location) }
        guard let cgGradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch gradient.kind {
        case .linear(let start, let end):
            ctx.drawLinearGradient(cgGradient, start: start, end: end, options: options)
        case .radial(let center, let r0, let r1):
            ctx.drawRadialGradient(cgGradient, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1, options: options)
        case .focalRadial(let start, let r0, let end, let r1):
            ctx.drawRadialGradient(cgGradient, startCenter: start, startRadius: r0, endCenter: end, endRadius: r1, options: options)
        case .elliptical(let center, let r0, let r1, let aspect):
            // A circle in a space squashed about the centre.
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: 1, y: max(aspect, 1e-6))
            ctx.drawRadialGradient(cgGradient, startCenter: .zero, startRadius: r0, endCenter: .zero, endRadius: r1, options: options)
            ctx.restoreGState()
        case .angular(let center, let startAngle):
            let box = ctx.boundingBoxOfClipPath
            let corners = [box.origin, CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
            let radius = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
            guard radius > 0 else { return }
            let wedges = 256
            func color(at t: Double) -> RGBA {
                guard let after = stops.firstIndex(where: { $0.location >= t }) else { return stops.last!.color }
                guard after > 0 else { return stops[0].color }
                let a = stops[after - 1], b = stops[after]
                let span = b.location - a.location
                let f = span > 0 ? (t - a.location) / span : 0
                return RGBA(red: a.color.red + (b.color.red - a.color.red) * f, green: a.color.green + (b.color.green - a.color.green) * f,
                            blue: a.color.blue + (b.color.blue - a.color.blue) * f, alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * f)
            }
            for index in 0..<wedges {
                let a0 = startAngle + Double(index) / Double(wedges) * 2 * .pi
                let a1 = startAngle + Double(index + 1) / Double(wedges) * 2 * .pi + 0.004
                ctx.setFillColor(cgColor(color(at: (Double(index) + 0.5) / Double(wedges))))
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a0)), y: center.y + radius * CGFloat(sin(a0))))
                ctx.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a1)), y: center.y + radius * CGFloat(sin(a1))))
                ctx.closePath()
                ctx.fillPath()
            }
        }
    }

    // MARK: Text

    private func drawText(_ text: String, font: DisplayFont, at origin: CGPoint, color: RGBA, gradient: DisplayGradient?, in ctx: CGContext) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: textEngine.nsFont(font),
            kCTForegroundColorAttributeName as NSAttributedString.Key: Self.cgColor(color),
        ]
        if font.letterSpacing != 0 { attributes[kCTKernAttributeName as NSAttributedString.Key] = font.letterSpacing }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.saveGState()
        // CoreText draws y-up: flip the glyphs about the baseline.
        ctx.textMatrix = .identity
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: 1, y: -1)
        if let gradient {
            ctx.setTextDrawingMode(.clip)
            CTLineDraw(line, ctx)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -origin.x, y: -origin.y)
            Self.draw(gradient, in: ctx)
        } else {
            ctx.setTextDrawingMode(.fill)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    // MARK: Images

    /// Keeps a decoded image for a URL (`AsyncImage` loads).
    public func register(_ image: CGImage, for url: String) {
        images[url] = image
    }

    private func image(for file: String, pixelSize: CGSize? = nil) -> CGImage? {
        if let cached = images[file] { return cached }
        let source: CGImageSource?
        #if canImport(AppKit)
        if file.lowercased().hasSuffix(".svg"), let base = assetBase, let pixelSize, pixelSize.width > 0, pixelSize.height > 0 {
            // A vector file: AppKit rasterises it at the pixel size of this draw (not cached).
            guard let vector = NSImage(contentsOf: base.appendingPathComponent(file)) else { return nil }
            let rect = CGRect(origin: .zero, size: pixelSize)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height), bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            guard let bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            vector.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.cgImage
        }
        #endif
        if file.hasPrefix("data:") {
            // A data URL (an image made from bytes): the base64 payload after the comma.
            guard let comma = file.firstIndex(of: ","), let data = Data(base64Encoded: String(file[file.index(after: comma)...])) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            guard let base = assetBase else { return nil }
            source = CGImageSourceCreateWithURL(base.appendingPathComponent(file) as CFURL, nil)
        }
        guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[file] = image
        return image
    }

    /// Draws `image` (or its `part`) into `destination` in the y-down space; when tiling, the
    /// part repeats at `tile` size from the destination's top-left corner (the last column and
    /// row cut at its edge).
    private func draw(_ image: CGImage, part: CGRect? = nil, in destination: CGRect, tile: CGSize? = nil, ctx: CGContext) {
        guard destination.width > 0, destination.height > 0 else { return }
        let piece = part.flatMap { image.cropping(to: $0) } ?? image
        ctx.saveGState()
        ctx.clip(to: destination)
        // Flip about the destination so the image draws upright in this y-down space.
        ctx.translateBy(x: 0, y: destination.maxY)
        ctx.scaleBy(x: 1, y: -1)
        if let tile, tile.width > 0, tile.height > 0 {
            // In the flipped space the destination spans y 0…height; a tile whose top edge is at
            // the top of the destination anchors the pattern there.
            ctx.draw(piece, in: CGRect(x: destination.minX, y: destination.height - tile.height, width: tile.width, height: tile.height), byTiling: true)
        } else {
            ctx.draw(piece, in: CGRect(x: destination.minX, y: 0, width: destination.width, height: destination.height))
        }
        ctx.restoreGState()
    }

    /// A CGImage over a bitmap's straight-alpha RGBA pixels.
    static func image(_ bitmap: DisplayBitmap) -> CGImage? {
        guard bitmap.width > 0, bitmap.height > 0, bitmap.pixels.count == bitmap.width * bitmap.height * 4,
              let provider = CGDataProvider(data: Data(bitmap.pixels) as CFData) else { return nil }
        return CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bitmap.width * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func drawImage(_ draw: ImageDraw, in ctx: CGContext) {
        let pixels = CGSize(width: (draw.rect.width * ctx.ctm.a).rounded(.up), height: (draw.rect.height * abs(ctx.ctm.d)).rounded(.up))
        guard let image = image(for: draw.file, pixelSize: pixels) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = draw.smoothing ? .default : .none
        if draw.tint != nil {
            // Template images: the image masks a fill of the tint.
            ctx.clip(to: draw.rect)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let insets = draw.capInsets
        let rect = draw.rect
        let scale = draw.scale
        let pointSize = CGSize(width: draw.pixelSize.width / scale, height: draw.pixelSize.height / scale)
        if insets == EdgeInsets() {
            self.draw(image, in: rect, tile: draw.tiles ? pointSize : nil, ctx: ctx)
        } else {
            // Nine parts: corners rigid, edges stretched or tiled one way, the centre both ways.
            let sx = [0, insets.leading * scale, draw.pixelSize.width - insets.trailing * scale, draw.pixelSize.width]
            let sy = [0, insets.top * scale, draw.pixelSize.height - insets.bottom * scale, draw.pixelSize.height]
            let dx = [rect.minX, rect.minX + insets.leading, rect.maxX - insets.trailing, rect.maxX]
            let dy = [rect.minY, rect.minY + insets.top, rect.maxY - insets.bottom, rect.maxY]
            for i in 0..<3 {
                for j in 0..<3 {
                    let source = CGRect(x: sx[i], y: sy[j], width: sx[i + 1] - sx[i], height: sy[j + 1] - sy[j])
                    let destination = CGRect(x: dx[i], y: dy[j], width: dx[i + 1] - dx[i], height: dy[j + 1] - dy[j])
                    guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else { continue }
                    let rigid = i != 1 && j != 1
                    let tile = draw.tiles && !rigid ? CGSize(width: source.width / scale, height: source.height / scale) : nil
                    self.draw(image, part: source, in: destination, tile: tile, ctx: ctx)
                }
            }
        }
        if let tint = draw.tint {
            ctx.setBlendMode(.sourceIn)
            if let gradient = draw.tintGradient {
                ctx.clip(to: draw.rect)
                Self.draw(gradient, in: ctx)
            } else {
                ctx.setFillColor(Self.cgColor(tint))
                ctx.fill(draw.rect)
            }
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
    }
}
#endif
