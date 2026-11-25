/// A resolved colour in sRGB with straight alpha, components 0…1.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 8-bit components, as in a PNG or a CSS `rgb()`.
    public init(r: Int, g: Int, b: Int, a: Double = 1) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
    }

    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)

    public func multiplyingAlpha(by factor: Double) -> RGBA {
        var copy = self
        copy.alpha *= factor
        return copy
    }
}

/// Font description a painter needs (no environment left to resolve).
public struct DisplayFont: Hashable, Sendable {
    public var family: String
    public var size: CGFloat
    public var weight: Int
    public var italic: Bool
    /// Extra advance after every character, in points (`kerning`/`tracking`).
    public var letterSpacing: CGFloat = 0
    /// Tabular figures: digits on one fixed advance.
    public var tabularDigits = false

    public init(_ font: ResolvedFont, letterSpacing: CGFloat = 0) {
        family = font.family
        size = font.size
        weight = font.weight.value
        italic = font.italic
        self.letterSpacing = letterSpacing
        tabularDigits = font.tabularDigits
    }
}

/// A bitmap drawn by value: `width × height` straight-alpha RGBA pixels, row-major (a mesh
/// gradient rasterised at the paint scale). Equality compares the pixels.
public struct DisplayBitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// How a surface's picture fits its rect (a player layer's `videoGravity`).
public enum SurfaceFit: Int, Equatable, Sendable {
    /// Stretched to the rect.
    case fill = 0
    /// Its whole picture inside the rect, keeping its shape.
    case aspect = 1
    /// The rect covered, keeping its shape (the picture cropped).
    case aspectFill = 2
}

/// One image draw: a catalog file scaled (or tiled, or nine-part stretched) into `rect`.
public struct ImageDraw: Equatable, Sendable {
    /// Path of the variant, relative to the manifest base.
    public var file: String
    /// Pixels per point of the file, and its pixel size.
    public var scale: CGFloat
    public var pixelSize: CGSize
    public var rect: CGRect
    /// Rigid border of a nine-part draw, in points; zero draws the whole image at once.
    public var capInsets = EdgeInsets()
    /// Tile the stretched parts (edges and centre of a nine-part draw, or the whole image).
    public var tiles = false
    /// Resample smoothly (`false` is nearest neighbour).
    public var smoothing = true
    /// Fill the image's alpha with this colour (template rendering).
    public var tint: RGBA?
    /// Fill the image's alpha with this gradient instead (a template image under a gradient
    /// foreground style); `tint` must be set too.
    public var tintGradient: DisplayGradient?

    public init(file: String, scale: CGFloat, pixelSize: CGSize, rect: CGRect) {
        self.file = file
        self.scale = scale
        self.pixelSize = pixelSize
        self.rect = rect
    }
}

/// One drawing command. Coordinates are absolute points in the window, already rounded to the
/// pixel grid where SwiftUI rounds (frame edges).
public enum DisplayCommand: Equatable, Sendable {
    case save
    case restore
    case clipRect(CGRect)
    case clipRRect(CGRect, cornerRadius: CGFloat)
    case clipPath(Path, eoFill: Bool = false)
    case beginGroup(opacity: Double)
    /// Starts a group (ended by `endGroup`) whose composite casts a shadow: `radius` is
    /// SwiftUI's blur radius (the Gaussian sigma in points), `offset` in points.
    case beginShadow(RGBA, radius: CGFloat, offset: CGSize)
    /// Starts a group (ended by `endGroup`) whose composite is filtered before it is drawn:
    /// `bounds` is the absolute frame of the filtered content, the area the painters process.
    case beginFilter(DisplayFilter, bounds: CGRect)
    /// Starts a group (ended by `endGroup`) composited with a blend mode; `bounds` as above.
    case beginBlend(BlendMode, bounds: CGRect)
    /// Starts a mask: the commands up to `beginMasked` draw the mask, those up to `endGroup`
    /// the content, which shows through the mask's alpha within `bounds`.
    case beginMask(bounds: CGRect)
    case beginMasked
    case endGroup
    /// Blurs what has been painted so far within `path` (a Gaussian whose sigma is `radius`
    /// points; the content keeps its alpha) and saturates it by `saturation` (1 leaves it), in
    /// place: a material's ground, which the tint drawn after it sits on. `bounds` is the
    /// path's frame, the area the painters process.
    case backdropBlur(Path, bounds: CGRect, radius: CGFloat, saturation: Double = 1)
    /// Like `backdropBlur`, seen through thick glass: what lies beneath is blurred and bends
    /// toward the path's rim, as an iOS 27 menu's glass does while it grows (new-website#649).
    /// `bend` is how far, in points, content from outside the shape is pulled in at its rim.
    /// `cornerRadius` is the shape's (a rounded rectangle's), which the rim follows. Painters
    /// without a lens draw the blur alone (`asBackdropBlur`).
    case backdropLens(Path, bounds: CGRect, radius: CGFloat, bend: CGFloat, cornerRadius: CGFloat)
    /// Multiplies the current transform (inside save/restore) for Canvas drawing and effects.
    case concat(CGAffineTransform)
    case fillRect(CGRect, RGBA)
    case fillRRect(CGRect, cornerRadius: CGFloat, RGBA)
    case fillPath(Path, RGBA, eoFill: Bool = false)
    case strokePath(Path, style: StrokeStyle, RGBA)
    /// Fills and strokes with a gradient (absolute coordinates).
    case fillGradient(Path, DisplayGradient, eoFill: Bool = false)
    case strokeGradient(Path, style: StrokeStyle, DisplayGradient)
    /// Draws one line of text with its baseline at `origin.y`.
    case drawText(String, DisplayFont, origin: CGPoint, RGBA)
    /// Draws one line of text filled with a gradient (absolute coordinates).
    case drawTextGradient(String, DisplayFont, origin: CGPoint, DisplayGradient)
    case drawImage(ImageDraw)
    /// Draws a bitmap by value stretched into `rect` (absolute coordinates).
    case drawBitmap(DisplayBitmap, rect: CGRect)
    /// Draws what the browser itself draws for surface `id` (a playing video's current frame, a
    /// GPU canvas) into `rect`, fitted as `fit` says (new-website#746). A painter without such
    /// surfaces (Cairo, Core Graphics, goldens) draws nothing for it.
    case drawSurface(Int, rect: CGRect, fit: SurfaceFit)
    /// Opens the stored content of scroll view `id` (closed by `endSegment`): a painter that
    /// keeps segments stores the commands up to `endSegment` and paints them as it reads them.
    /// `cull` is the area that shows (in the segment's coordinates, the viewport with the cull
    /// margin): a `beginCullBlock` outside it is skipped whole.
    case beginSegment(Int, cull: CGRect)
    case endSegment
    /// Paints stored segment `id` again moved by `offset` points: a frame in which its content
    /// only scrolled (new-website#286). `shown` is the area the viewport shows and `cull` that
    /// area with the cull margin, both in the segment's recorded coordinates. Only a host that
    /// renders with segments (`renderKeepingSegments`) is sent this.
    case reuseSegment(Int, offset: CGSize, shown: CGRect, cull: CGRect)
    /// Opens commands that paint inside `bounds` (a subtree's frame), closed by `endCullBlock`:
    /// inside a segment, a painter may skip the block when `bounds` misses the segment's cull area.
    case beginCullBlock(CGRect)
    case endCullBlock
}

/// The flat command list a painter consumes for one frame (decision 0002).
public struct DisplayList: Equatable, Sendable {
    public var commands: [DisplayCommand] = []

    public init() {}

    public mutating func append(_ command: DisplayCommand) {
        commands.append(command)
    }

    /// The box the commands from `start` on paint into: fills and clips by their geometry,
    /// strokes padded by their width, images and bitmaps by their rects; text is left to the
    /// caller's frame (its ink is not known here). `CGRect.null` when nothing paints geometry.
    public func paintedExtent(from start: Int = 0) -> CGRect {
        var extent = CGRect.null
        func add(_ rect: CGRect) { if !rect.isNull, !rect.isEmpty || !extent.isNull { extent = extent.union(rect) } }
        for command in commands[min(start, commands.count)...] {
            switch command {
            case .fillRect(let rect, _), .fillRRect(let rect, _, _): add(rect)
            case .fillPath(let path, _, _), .fillGradient(let path, _, _): add(path.boundingRect)
            case .strokePath(let path, let style, _), .strokeGradient(let path, let style, _):
                add(path.strokedPath(style).boundingRect)
            case .drawImage(let draw): add(draw.rect)
            case .drawBitmap(_, let rect): add(rect)
            case .drawSurface(_, let rect, _): add(rect)
            case .backdropBlur(_, let bounds, _, _): add(bounds)
            case .backdropLens(_, let bounds, _, _, _): add(bounds)
            default: break
            }
        }
        return extent
    }

    /// Runs `body` between `save` and `restore`.
    public mutating func withSavedState(_ body: (inout DisplayList) -> Void) {
        commands.append(.save)
        body(&self)
        commands.append(.restore)
    }

    public var isEmpty: Bool { commands.isEmpty }
}

/// Formats a number for display-list descriptions: integers without a fraction.
public func _displayFormat(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }

extension DisplayCommand: CustomStringConvertible {
    public var description: String {
        func f(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }
        func r(_ rect: CGRect) -> String { "(\(f(rect.minX)), \(f(rect.minY)), \(f(rect.width)), \(f(rect.height)))" }
        func c(_ color: RGBA) -> String {
            let hex = String(Int((color.red * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.green * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.blue * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
            return color.alpha == 1 ? "#\(hex)" : "#\(hex)@\(color.alpha)"
        }
        switch self {
        case .save: return "save"
        case .restore: return "restore"
        case .clipRect(let rect): return "clipRect\(r(rect))"
        case .clipRRect(let rect, let radius): return "clipRRect\(r(rect)) r=\(f(radius))"
        case .clipPath(let path, let eo): return "clipPath(\(path.elements.count) elements)\(eo ? " eo" : "")"
        case .beginGroup(let opacity): return "beginGroup(opacity: \(opacity))"
        case .beginShadow(let color, let radius, let offset): return "beginShadow(\(c(color)) r=\(f(radius)) dx=\(f(offset.width)) dy=\(f(offset.height)))"
        case .beginFilter(let filter, let bounds): return "beginFilter(\(filter)\(r(bounds)))"
        case .beginBlend(let mode, let bounds): return "beginBlend(\(mode)\(r(bounds)))"
        case .beginMask(let bounds): return "beginMask\(r(bounds))"
        case .beginMasked: return "beginMasked"
        case .endGroup: return "endGroup"
        case .backdropBlur(let path, let bounds, let radius, let saturation): return "backdropBlur(\(path.elements.count) elements\(r(bounds)) r=\(f(radius))\(saturation == 1 ? "" : " sat=\(f(saturation))"))"
        case .backdropLens(let path, let bounds, let radius, let bend, let corner): return "backdropLens(\(path.elements.count) elements\(r(bounds)) r=\(f(radius)) bend=\(f(bend)) corner=\(f(corner)))"
        case .concat(let t): return "concat(\(f(t.a)), \(f(t.b)), \(f(t.c)), \(f(t.d)), \(f(t.tx)), \(f(t.ty)))"
        case .fillRect(let rect, let color): return "fillRect\(r(rect)) \(c(color))"
        case .fillRRect(let rect, let radius, let color): return "fillRRect\(r(rect)) r=\(f(radius)) \(c(color))"
        case .fillPath(let path, let color, let eo): return "fillPath(\(path.elements.count) elements)\(eo ? " eo" : "") \(c(color))"
        case .fillGradient(let path, let gradient, let eo): return "fillGradient(\(path.elements.count) elements)\(eo ? " eo" : "") \(gradient.summary)"
        case .strokeGradient(let path, let style, let gradient): return "strokeGradient(\(path.elements.count) elements) w=\(f(style.lineWidth)) \(gradient.summary)"
        case .strokePath(let path, let style, let color):
            var text = "strokePath(\(path.elements.count) elements) w=\(f(style.lineWidth))"
            if style.lineCap != .butt { text += " cap=\(style.lineCap == .round ? "round" : "square")" }
            if style.lineJoin != .miter { text += " join=\(style.lineJoin == .round ? "round" : "bevel")" }
            if style.miterLimit != 10 { text += " miter=\(f(style.miterLimit))" }
            if !style.dash.isEmpty { text += " dash=[\(style.dash.map(f).joined(separator: ","))]" + (style.dashPhase != 0 ? " phase=\(f(style.dashPhase))" : "") }
            return text + " \(c(color))"
        case .drawText(let text, let font, let origin, let color):
            return "drawText(\"\(text)\" \(font.family) \(f(font.size)) w\(font.weight) at \(f(origin.x)),\(f(origin.y)) \(c(color)))"
        case .drawTextGradient(let text, let font, let origin, let gradient):
            return "drawText(\"\(text)\" \(font.family) \(f(font.size)) w\(font.weight) at \(f(origin.x)),\(f(origin.y)) \(gradient.summary))"
        case .drawImage(let draw):
            var text = "drawImage(\(draw.file) @\(f(draw.scale))x \(r(draw.rect))"
            if draw.capInsets != EdgeInsets() { text += " insets=\(f(draw.capInsets.top)),\(f(draw.capInsets.leading)),\(f(draw.capInsets.bottom)),\(f(draw.capInsets.trailing))" }
            if draw.tiles { text += " tile" }
            if !draw.smoothing { text += " nearest" }
            if let tint = draw.tint { text += " tint=\(c(tint))" }
            if let gradient = draw.tintGradient { text += " tint=\(gradient.summary)" }
            return text + ")"
        case .drawBitmap(let bitmap, let rect):
            return "drawBitmap(\(bitmap.width)x\(bitmap.height) \(r(rect)))"
        case .drawSurface(let id, let rect, let fit): return "drawSurface(\(id) \(r(rect)) fit=\(fit))"
        case .beginSegment(let id, let cull): return "beginSegment(\(id) cull=\(r(cull)))"
        case .endSegment: return "endSegment"
        case .reuseSegment(let id, let offset, let shown, let cull): return "reuseSegment(\(id) dx=\(f(offset.width)) dy=\(f(offset.height)) shown=\(r(shown)) cull=\(r(cull)))"
        case .beginCullBlock(let bounds): return "beginCullBlock\(r(bounds))"
        case .endCullBlock: return "endCullBlock"
        }
    }
}

extension String {
    fileprivate func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

extension DisplayGradient {
    /// A short description for logs and tests.
    public var summary: String {
        func p(_ point: CGPoint) -> String { "\(point.x),\(point.y)" }
        let kindText: String
        switch kind {
        case .linear(let start, let end): kindText = "linear \(p(start))→\(p(end))"
        case .radial(let center, let r0, let r1): kindText = "radial \(p(center)) r\(r0)→\(r1)"
        case .focalRadial(let start, let r0, let end, let r1): kindText = "radial \(p(start)) r\(r0)→\(p(end)) r\(r1)"
        case .angular(let center, let angle): kindText = "angular \(p(center)) a\(angle)"
        case .elliptical(let center, let r0, let r1, let aspect): kindText = "elliptical \(p(center)) r\(r0)→\(r1) ×\(aspect)"
        }
        func hex(_ value: Double) -> String {
            let byte = Int((value * 255).rounded())
            let digits = String(byte, radix: 16, uppercase: true)
            return byte < 16 ? "0" + digits : digits
        }
        let stopsText = stops.map { "\($0.location):\(hex($0.color.red))\(hex($0.color.green))\(hex($0.color.blue))" }.joined(separator: " ")
        return "\(kindText) [\(stopsText)]"
    }
}

/// A filter a painter applies to a group's composite before drawing it.
public enum DisplayFilter: Equatable, Sendable {
    /// A 4 × 5 colour matrix over straight-alpha sRGB components in 0…1, row-major: each of
    /// the red, green, blue and alpha rows holds the red, green, blue and alpha factors and an
    /// offset (the SVG `feColorMatrix` convention). Results are clamped to 0…1.
    case colorMatrix(ColorMatrix)
    /// A Gaussian blur whose sigma is `radius` points. `opaque` keeps the content's own alpha
    /// (hard edges) and blurs only the colours inside it.
    case blur(radius: CGFloat, opaque: Bool)
}

extension DisplayFilter: CustomStringConvertible {
    public var description: String {
        switch self {
        case .colorMatrix(let matrix): return matrix.description
        case .blur(let radius, let opaque): return "blur(\(_displayFormat(radius))\(opaque ? " opaque" : ""))"
        }
    }
}

/// A colour matrix (see `DisplayFilter.colorMatrix`): 20 values, rows red, green, blue, alpha.
public struct ColorMatrix: Equatable, Sendable {
    public var values: [Double]

    public init(_ values: [Double]) {
        precondition(values.count == 20, "a colour matrix has 4 rows of 5")
        self.values = values
    }

    public static let identity = ColorMatrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])

    /// The luminance weights SwiftUI's filters share (Rec. 709 primaries).
    public static let luminance = (red: 0.2126, green: 0.7152, blue: 0.0722)

    /// Adds `amount` to every colour component (`brightness`).
    public static func brightness(_ amount: Double) -> ColorMatrix {
        ColorMatrix([1, 0, 0, 0, amount, 0, 1, 0, 0, amount, 0, 0, 1, 0, amount, 0, 0, 0, 1, 0])
    }

    /// Scales the colour components about mid grey (`contrast`).
    public static func contrast(_ amount: Double) -> ColorMatrix {
        let offset = 0.5 - 0.5 * amount
        return ColorMatrix([amount, 0, 0, 0, offset, 0, amount, 0, 0, offset, 0, 0, amount, 0, offset, 0, 0, 0, 1, 0])
    }

    /// Interpolates between luminance grey (0) and the colour itself (1), or beyond (`saturation`;
    /// `grayscale(x)` is `saturation(1 - x)`).
    public static func saturation(_ amount: Double) -> ColorMatrix {
        let (r, g, b) = luminance
        let s = amount
        return ColorMatrix([
            r + (1 - r) * s, g - g * s, b - b * s, 0, 0,
            r - r * s, g + (1 - g) * s, b - b * s, 0, 0,
            r - r * s, g - g * s, b + (1 - b) * s, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }

    /// Rotates hues by `angle` (`hueRotation`), the SVG `hueRotate` matrix.
    public static func hueRotation(_ angle: Angle) -> ColorMatrix {
        let (r, g, b) = luminance
        let c = _cos(angle.radians), s = _sin(angle.radians)
        return ColorMatrix([
            r + c * (1 - r) - s * r, g - c * g - s * g, b - c * b + s * (1 - b), 0, 0,
            r - c * r + s * 0.143, g + c * (1 - g) + s * 0.140, b - c * b - s * 0.283, 0, 0,
            r - c * r - s * (1 - r), g - c * g + s * g, b + c * (1 - b) + s * b, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }

    /// Complements every colour component (`colorInvert`).
    public static let invert = ColorMatrix([-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0])

    /// Multiplies the components by a colour's, alpha included (`colorMultiply`).
    public static func multiply(_ color: RGBA) -> ColorMatrix {
        ColorMatrix([color.red, 0, 0, 0, 0, 0, color.green, 0, 0, 0, 0, 0, color.blue, 0, 0, 0, 0, 0, color.alpha, 0])
    }

    /// Black whose alpha is the colour's luminance (`luminanceToAlpha`): the content's own
    /// alpha is replaced, as SwiftUI does.
    public static let luminanceToAlpha = ColorMatrix([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, luminance.red, luminance.green, luminance.blue, 0, 0])

    /// Applies the matrix to one straight-alpha colour, clamping to 0…1.
    public func apply(_ color: RGBA) -> RGBA {
        let input = [color.red, color.green, color.blue, color.alpha]
        var out = [0.0, 0.0, 0.0, 0.0]
        for row in 0..<4 {
            var value = values[row * 5 + 4]
            for column in 0..<4 { value += values[row * 5 + column] * input[column] }
            out[row] = min(1, max(0, value))
        }
        return RGBA(red: out[0], green: out[1], blue: out[2], alpha: out[3])
    }

    /// Applies the matrix in place to premultiplied 8-bit RGBA pixels: each pixel is
    /// un-premultiplied, transformed, clamped, rounded and premultiplied again.
    public func apply(toPremultiplied pixels: UnsafeMutableBufferPointer<UInt8>) {
        let m = values
        var i = 0
        while i + 3 < pixels.count {
            let a8 = pixels[i + 3]
            var r = 0.0, g = 0.0, b = 0.0, a = Double(a8) / 255
            if a8 != 0 {
                r = Double(pixels[i]) / 255 / a
                g = Double(pixels[i + 1]) / 255 / a
                b = Double(pixels[i + 2]) / 255 / a
            }
            let nr = min(1, max(0, m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]))
            let ng = min(1, max(0, m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]))
            let nb = min(1, max(0, m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]))
            let na = min(1, max(0, m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]))
            pixels[i] = UInt8((nr * na * 255).rounded())
            pixels[i + 1] = UInt8((ng * na * 255).rounded())
            pixels[i + 2] = UInt8((nb * na * 255).rounded())
            pixels[i + 3] = UInt8((na * 255).rounded())
            i += 4
        }
    }
}

extension ColorMatrix: CustomStringConvertible {
    public var description: String { "colorMatrix(" + values.map { _displayFormat($0) }.joined(separator: " ") + ")" }
}

extension DisplayList {
    /// The commands moved by `offset`: every top-level command's geometry, and the transform of
    /// a top-level `concat` (what follows it up to its `restore` is in that transform's space
    /// and stays as recorded).
    public static func translated(_ commands: [DisplayCommand], by offset: CGPoint) -> [DisplayCommand] {
        guard offset != .zero else { return commands }
        let shift = CGAffineTransform(translationX: offset.x, y: offset.y)
        var depth = 0
        var result: [DisplayCommand] = []
        result.reserveCapacity(commands.count)
        for command in commands {
            if depth > 0 {
                if case .save = command { depth += 1 } else if case .restore = command { depth -= 1 }
                result.append(command)
                continue
            }
            switch command {
            case .save, .restore, .beginGroup, .beginShadow, .beginMasked, .endGroup:
                result.append(command)
            case .concat(let transform):
                // Entered by the preceding save: the block runs in this space until its restore.
                depth = 1
                result[result.count - 1] = .save
                result.append(.concat(transform.concatenating(shift)))
            case .clipRect(let rect): result.append(.clipRect(rect.offsetBy(dx: offset.x, dy: offset.y)))
            case .clipRRect(let rect, let radius): result.append(.clipRRect(rect.offsetBy(dx: offset.x, dy: offset.y), cornerRadius: radius))
            case .clipPath(let path, let eo): result.append(.clipPath(path.applying(shift), eoFill: eo))
            case .beginFilter(let filter, let bounds): result.append(.beginFilter(filter, bounds: bounds.offsetBy(dx: offset.x, dy: offset.y)))
            case .beginBlend(let mode, let bounds): result.append(.beginBlend(mode, bounds: bounds.offsetBy(dx: offset.x, dy: offset.y)))
            case .beginMask(let bounds): result.append(.beginMask(bounds: bounds.offsetBy(dx: offset.x, dy: offset.y)))
            case .backdropBlur(let path, let bounds, let radius, let saturation):
                result.append(.backdropBlur(path.applying(shift), bounds: bounds.offsetBy(dx: offset.x, dy: offset.y), radius: radius, saturation: saturation))
            case .backdropLens(let path, let bounds, let radius, let bend, let corner):
                result.append(.backdropLens(path.applying(shift), bounds: bounds.offsetBy(dx: offset.x, dy: offset.y), radius: radius, bend: bend, cornerRadius: corner))
            case .fillRect(let rect, let color): result.append(.fillRect(rect.offsetBy(dx: offset.x, dy: offset.y), color))
            case .fillRRect(let rect, let radius, let color): result.append(.fillRRect(rect.offsetBy(dx: offset.x, dy: offset.y), cornerRadius: radius, color))
            case .fillPath(let path, let color, let eo): result.append(.fillPath(path.applying(shift), color, eoFill: eo))
            case .strokePath(let path, let style, let color): result.append(.strokePath(path.applying(shift), style: style, color))
            case .fillGradient(let path, let gradient, let eo): result.append(.fillGradient(path.applying(shift), gradient.translated(by: offset), eoFill: eo))
            case .strokeGradient(let path, let style, let gradient): result.append(.strokeGradient(path.applying(shift), style: style, gradient.translated(by: offset)))
            case .drawText(let text, let font, let origin, let color): result.append(.drawText(text, font, origin: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y), color))
            case .drawTextGradient(let text, let font, let origin, let gradient):
                result.append(.drawTextGradient(text, font, origin: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y), gradient.translated(by: offset)))
            case .drawImage(var draw):
                draw.rect = draw.rect.offsetBy(dx: offset.x, dy: offset.y)
                result.append(.drawImage(draw))
            case .drawBitmap(let bitmap, let rect): result.append(.drawBitmap(bitmap, rect: rect.offsetBy(dx: offset.x, dy: offset.y)))
            case .drawSurface(let id, let rect, let fit): result.append(.drawSurface(id, rect: rect.offsetBy(dx: offset.x, dy: offset.y), fit: fit))
            case .beginSegment(let id, let cull): result.append(.beginSegment(id, cull: cull.offsetBy(dx: offset.x, dy: offset.y)))
            case .reuseSegment(let id, let moved, let shown, let cull):
                // The shown and cull areas stay in the segment's recorded coordinates.
                result.append(.reuseSegment(id, offset: CGSize(width: moved.width + offset.x, height: moved.height + offset.y), shown: shown, cull: cull))
            case .beginCullBlock(let bounds): result.append(.beginCullBlock(bounds.offsetBy(dx: offset.x, dy: offset.y)))
            case .endSegment, .endCullBlock: result.append(command)
            }
        }
        return result
    }
}

extension DisplayGradient {
    /// The gradient moved by `offset` (its points are absolute).
    public func translated(by offset: CGPoint) -> DisplayGradient {
        var copy = self
        func moved(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + offset.x, y: point.y + offset.y) }
        switch kind {
        case .linear(let start, let end): copy.kind = .linear(start: moved(start), end: moved(end))
        case .radial(let center, let startRadius, let endRadius): copy.kind = .radial(center: moved(center), startRadius: startRadius, endRadius: endRadius)
        case .focalRadial(let startCenter, let startRadius, let endCenter, let endRadius):
            copy.kind = .focalRadial(startCenter: moved(startCenter), startRadius: startRadius, endCenter: moved(endCenter), endRadius: endRadius)
        case .angular(let center, let startAngle): copy.kind = .angular(center: moved(center), startAngle: startAngle)
        case .elliptical(let center, let startRadius, let endRadius, let aspect):
            copy.kind = .elliptical(center: moved(center), startRadius: startRadius, endRadius: endRadius, aspect: aspect)
        }
        return copy
    }
}

/// The lists a host's stored segments came from (new-website#286), to read a frame that paints
/// segments again as the commands it shows: debug bridges and tests.
public struct SegmentSources: Sendable {
    private var lists: [Int: DisplayList] = [:]

    public init() {}

    /// Keeps `list` as the source of the segments it defines. Only a handful of scroll views
    /// paint at once; past that, the ones the list neither defines nor paints again go.
    public mutating func store(_ list: DisplayList, defining defined: [Int], reusing reused: [Int]) {
        for id in defined { lists[id] = list }
        if lists.count > 64 {
            let kept = Set(defined + reused)
            lists = lists.filter { kept.contains($0.key) }
        }
    }

    /// The commands, every `reuseSegment` replaced by the stored commands moved to where it
    /// paints them (`reuseSegment`s whose source is gone stay as they are).
    public func resolved(_ commands: [DisplayCommand], depth: Int = 0) -> [DisplayCommand] {
        guard depth < 8, commands.contains(where: { if case .reuseSegment = $0 { return true }; return false }) else { return commands }
        var out: [DisplayCommand] = []
        out.reserveCapacity(commands.count)
        for command in commands {
            guard case .reuseSegment(let id, let offset, _, _) = command, let source = lists[id],
                  let stored = Self.segment(id, in: source.commands) else { out.append(command); continue }
            out.append(contentsOf: DisplayList.translated(resolved(stored, depth: depth + 1), by: CGPoint(x: offset.width, y: offset.height)))
        }
        return out
    }

    /// The commands between segment `id`'s `beginSegment` and its `endSegment`.
    public static func segment(_ id: Int, in commands: [DisplayCommand]) -> [DisplayCommand]? {
        guard let start = commands.firstIndex(where: { if case .beginSegment(id, _) = $0 { return true }; return false }) else { return nil }
        var depth = 0
        for index in (start + 1)..<commands.count {
            switch commands[index] {
            case .beginSegment: depth += 1
            case .endSegment:
                if depth == 0 { return Array(commands[(start + 1)..<index]) }
                depth -= 1
            default: break
            }
        }
        return nil
    }
}

extension DisplayCommand {
    /// A lens as the plain blur it reduces to, for painters that draw no lens; any other command
    /// as it is.
    public var asBackdropBlur: DisplayCommand {
        if case .backdropLens(let path, let bounds, let radius, _, _) = self { return .backdropBlur(path, bounds: bounds, radius: radius) }
        return self
    }
}
