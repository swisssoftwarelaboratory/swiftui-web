/// Flat encoding of a display list for a painter that lives across a bridge (JS, C): opcodes and
/// operands in one `[Double]`, strings interned in a side table. Decoders: SwiftUIWebCanvas
/// (`Canvas2DPainter` JS) and tests (`DisplayListDecoder`).
public enum DisplayOp: Double, Sendable {
    case save = 1, restore = 2
    /// clipPath: path, eoFill
    case clipRect = 3, clipRRect = 4, clipPath = 5
    case beginGroup = 6, endGroup = 7
    /// fillPath: path, colour, eoFill. strokePath: path, width, cap, join, miter limit, dash count, dashes, phase, colour
    case fillRect = 8, fillRRect = 9, fillPath = 10, strokePath = 11
    case drawText = 12
    /// file, scale, pixel w/h, rect, tile, insets (top, leading, bottom, trailing), smoothing, hasTint (0 none, 1 colour,
    /// 2 colour then gradient), colour, [gradient]
    case drawImage = 13
    /// a, b, c, d, tx, ty
    case concat = 14
    /// fillGradient: path, gradient, eoFill. strokeGradient: path, stroke style (as strokePath), gradient.
    /// A gradient is: kind (0 linear x0,y0,x1,y1; 1 radial cx,cy,r0,r1; 2 angular cx,cy,angle; 3 focal radial
    /// x0,y0,r0,x1,y1,r1; 4 elliptical cx,cy,r0,r1,aspect), stop count, stops (location, colour).
    case fillGradient = 15, strokeGradient = 16
    /// text, font, origin, gradient
    case drawTextGradient = 17
    /// colour, radius, dx, dy; ended by endGroup
    case beginShadow = 18
    /// bounds, kind (0 colour matrix: 20 values; 1 blur: radius, opaque); ended by endGroup
    case beginFilter = 19
    /// blend mode index, bounds; ended by endGroup
    case beginBlend = 20
    /// bounds; the mask's commands follow until beginMasked, the content's until endGroup
    case beginMask = 21
    case beginMasked = 22
    /// path, bounds, radius, saturation: blurs (and saturates) what lies beneath the path in place
    case backdropBlur = 23
    /// bitmap index (into the side table), rect
    case drawBitmap = 24
    /// beginSegment: id, cull rect. reuseSegment: id, dx, dy, shown rect, cull rect (new-website#286)
    case beginSegment = 25, endSegment = 26, reuseSegment = 27
    /// beginCullBlock: bounds, then the index of the op after its `endCullBlock` (where a painter
    /// skipping the block goes on)
    case beginCullBlock = 28, endCullBlock = 29
}

/// Path element tags inside an encoded path: tag, then coordinates.
public enum DisplayPathOp: Double, Sendable {
    case move = 0, line = 1, quad = 2, curve = 3, close = 4
}

public struct EncodedDisplayList: Equatable, Sendable {
    public var ops: [Double] = []
    /// Interned strings: text runs and CSS font strings.
    public var strings: [String] = []
    /// Bitmaps drawn by value, indexed by `drawBitmap` ops.
    public var bitmaps: [DisplayBitmap] = []
    /// The segments the list defines (`beginSegment`) and paints again (`reuseSegment`), for a
    /// host keeping their sources.
    public var segments: [Int] = []
    public var reusedSegments: [Int] = []

    public init() {}
}

public enum DisplayListEncoder {
    /// Encodes `list`. Colours are emitted as r,g,b (0…255) and alpha (0…1).
    public static func encode(_ list: DisplayList, font fontString: (DisplayFont) -> String) -> EncodedDisplayList {
        var out = EncodedDisplayList()
        var stringIndex: [String: Int] = [:]
        func intern(_ s: String) -> Double {
            if let i = stringIndex[s] { return Double(i) }
            let i = out.strings.count
            out.strings.append(s)
            stringIndex[s] = i
            return Double(i)
        }
        func rect(_ r: CGRect) { out.ops += [r.minX, r.minY, r.width, r.height] }
        func color(_ c: RGBA) { out.ops += [(c.red * 255).rounded(), (c.green * 255).rounded(), (c.blue * 255).rounded(), c.alpha] }
        func path(_ p: Path) {
            out.ops.append(Double(p.elements.count))
            for element in p.elements {
                switch element {
                case .move(let to): out.ops += [DisplayPathOp.move.rawValue, to.x, to.y]
                case .line(let to): out.ops += [DisplayPathOp.line.rawValue, to.x, to.y]
                case .quadCurve(let to, let c): out.ops += [DisplayPathOp.quad.rawValue, to.x, to.y, c.x, c.y]
                case .curve(let to, let c1, let c2): out.ops += [DisplayPathOp.curve.rawValue, to.x, to.y, c1.x, c1.y, c2.x, c2.y]
                case .closeSubpath: out.ops.append(DisplayPathOp.close.rawValue)
                }
            }
        }
        func gradient(_ g: DisplayGradient) {
            switch g.kind {
            case .linear(let start, let end): out.ops += [0, start.x, start.y, end.x, end.y]
            case .radial(let center, let r0, let r1): out.ops += [1, center.x, center.y, r0, r1]
            case .angular(let center, let angle): out.ops += [2, center.x, center.y, angle]
            case .focalRadial(let start, let r0, let end, let r1): out.ops += [3, start.x, start.y, r0, end.x, end.y, r1]
            case .elliptical(let center, let r0, let r1, let aspect): out.ops += [4, center.x, center.y, r0, r1, aspect]
            }
            out.ops.append(Double(g.stops.count))
            for stop in g.stops { out.ops.append(stop.location); color(stop.color) }
        }
        func strokeStyle(_ style: StrokeStyle) {
            out.ops += [style.lineWidth, Double(style.lineCap.rawValue), Double(style.lineJoin.rawValue), style.miterLimit, Double(style.dash.count)]
            out.ops += style.dash.map { Double($0) }
            out.ops.append(style.dashPhase)
        }
        // Open cull blocks: where each one's skip target goes once its end is reached.
        var openBlocks: [Int] = []
        for command in list.commands {
            switch command {
            case .beginSegment(let id, let cull): out.ops += [DisplayOp.beginSegment.rawValue, Double(id)]; rect(cull); out.segments.append(id)
            case .endSegment: out.ops.append(DisplayOp.endSegment.rawValue)
            case .reuseSegment(let id, let offset, let shown, let cull):
                out.ops += [DisplayOp.reuseSegment.rawValue, Double(id), offset.width, offset.height]; rect(shown); rect(cull); out.reusedSegments.append(id)
            case .beginCullBlock(let bounds):
                out.ops.append(DisplayOp.beginCullBlock.rawValue); rect(bounds)
                openBlocks.append(out.ops.count)
                out.ops.append(0)
            case .endCullBlock:
                out.ops.append(DisplayOp.endCullBlock.rawValue)
                if let slot = openBlocks.popLast() { out.ops[slot] = Double(out.ops.count) }
            case .fillGradient(let p, let g, let eo): out.ops.append(DisplayOp.fillGradient.rawValue); path(p); gradient(g); out.ops.append(eo ? 1 : 0)
            case .strokeGradient(let p, let style, let g): out.ops.append(DisplayOp.strokeGradient.rawValue); path(p); strokeStyle(style); gradient(g)
            case .save: out.ops.append(DisplayOp.save.rawValue)
            case .restore: out.ops.append(DisplayOp.restore.rawValue)
            case .clipRect(let r): out.ops.append(DisplayOp.clipRect.rawValue); rect(r)
            case .clipRRect(let r, let radius): out.ops.append(DisplayOp.clipRRect.rawValue); rect(r); out.ops.append(radius)
            case .clipPath(let p, let eo): out.ops.append(DisplayOp.clipPath.rawValue); path(p); out.ops.append(eo ? 1 : 0)
            case .beginGroup(let opacity): out.ops += [DisplayOp.beginGroup.rawValue, opacity]
            case .beginShadow(let c, let radius, let offset):
                out.ops.append(DisplayOp.beginShadow.rawValue); color(c); out.ops += [radius, offset.width, offset.height]
            case .beginFilter(let filter, let bounds):
                out.ops.append(DisplayOp.beginFilter.rawValue); rect(bounds)
                switch filter {
                case .colorMatrix(let matrix): out.ops.append(0); out.ops += matrix.values
                case .blur(let radius, let opaque): out.ops += [1, radius, opaque ? 1 : 0]
                }
            case .beginBlend(let mode, let bounds):
                out.ops += [DisplayOp.beginBlend.rawValue, Double(mode._index)]; rect(bounds)
            case .beginMask(let bounds): out.ops.append(DisplayOp.beginMask.rawValue); rect(bounds)
            case .beginMasked: out.ops.append(DisplayOp.beginMasked.rawValue)
            case .endGroup: out.ops.append(DisplayOp.endGroup.rawValue)
            case .backdropBlur(let p, let bounds, let radius, let saturation): out.ops.append(DisplayOp.backdropBlur.rawValue); path(p); rect(bounds); out.ops += [radius, saturation]
            case .concat(let t): out.ops += [DisplayOp.concat.rawValue, t.a, t.b, t.c, t.d, t.tx, t.ty]
            case .fillRect(let r, let c): out.ops.append(DisplayOp.fillRect.rawValue); rect(r); color(c)
            case .fillRRect(let r, let radius, let c): out.ops.append(DisplayOp.fillRRect.rawValue); rect(r); out.ops.append(radius); color(c)
            case .fillPath(let p, let c, let eo): out.ops.append(DisplayOp.fillPath.rawValue); path(p); color(c); out.ops.append(eo ? 1 : 0)
            case .strokePath(let p, let style, let c):
                out.ops.append(DisplayOp.strokePath.rawValue)
                path(p)
                out.ops += [style.lineWidth, Double(style.lineCap.rawValue), Double(style.lineJoin.rawValue), style.miterLimit, Double(style.dash.count)]
                out.ops += style.dash.map { Double($0) }
                out.ops.append(style.dashPhase)
                color(c)
            case .drawText(let text, let font, let origin, let c):
                out.ops += [DisplayOp.drawText.rawValue, intern(text), intern(fontString(font)), origin.x, origin.y]
                color(c)
            case .drawTextGradient(let text, let font, let origin, let g):
                out.ops += [DisplayOp.drawTextGradient.rawValue, intern(text), intern(fontString(font)), origin.x, origin.y]
                gradient(g)
            case .drawImage(let draw):
                out.ops += [DisplayOp.drawImage.rawValue, intern(draw.file), draw.scale, draw.pixelSize.width, draw.pixelSize.height]
                rect(draw.rect)
                out.ops += [draw.tiles ? 1 : 0, draw.capInsets.top, draw.capInsets.leading, draw.capInsets.bottom, draw.capInsets.trailing,
                            draw.smoothing ? 1 : 0, draw.tint == nil ? 0 : draw.tintGradient == nil ? 1 : 2]
                color(draw.tint ?? .clear)
                if draw.tint != nil, let tintGradient = draw.tintGradient { gradient(tintGradient) }
            case .drawBitmap(let bitmap, let r):
                out.ops += [DisplayOp.drawBitmap.rawValue, Double(out.bitmaps.count)]
                out.bitmaps.append(bitmap)
                rect(r)
            }
        }
        return out
    }

    /// The CSS `font` shorthand for a display font (browser painters and text engines).
    public static func cssFont(_ font: DisplayFont) -> String {
        let family: String
        switch font.family {
        case "system": family = "-apple-system, BlinkMacSystemFont, system-ui, 'Segoe UI', Roboto, sans-serif"
        case "system-rounded": family = "ui-rounded, -apple-system, system-ui, sans-serif"
        case "system-serif": family = "ui-serif, 'New York', Georgia, serif"
        case "system-monospaced": family = "ui-monospace, 'SF Mono', Menlo, Consolas, monospace"
        default: family = "'\(font.family)', -apple-system, system-ui, sans-serif"
        }
        let size = font.size == font.size.rounded() ? "\(Int(font.size))" : "\(font.size)"
        let css = "\(font.italic ? "italic " : "")\(font.weight) \(size)px \(family)"
        // Letter spacing rides behind the CSS font, split off by the painter (`setFont`); tabular
        // figures add a third part (`|<spacing>|t<ratio>`): the digit slot as a multiple of the
        // "0" advance the painter measures (`TabularFigures`).
        if font.tabularDigits { return css + "|" + _displayFormat(font.letterSpacing) + "|t" + _displayFormat(TabularFigures.slotRatio(size: font.size, weight: font.weight)) }
        return font.letterSpacing == 0 ? css : css + "|" + _displayFormat(font.letterSpacing)
    }
}

/// Decodes the flat encoding back into commands (tests, and a reference for the JS decoder).
public enum DisplayListDecoder {
    public static func decode(_ encoded: EncodedDisplayList) -> [String] {
        var out: [String] = []
        var i = 0
        let ops = encoded.ops
        func next() -> Double { defer { i += 1 }; return ops[i] }
        func rect() -> CGRect { CGRect(x: next(), y: next(), width: next(), height: next()) }
        func color() -> String {
            let r = Int(next()), g = Int(next()), b = Int(next()), a = next()
            return a == 1 ? "rgb(\(r),\(g),\(b))" : "rgba(\(r),\(g),\(b),\(a))"
        }
        func path() -> String {
            let count = Int(next())
            var parts: [String] = []
            for _ in 0..<count {
                switch DisplayPathOp(rawValue: next())! {
                case .move: parts.append("M\(next()),\(next())")
                case .line: parts.append("L\(next()),\(next())")
                case .quad: parts.append("Q\(next()),\(next()) \(next()),\(next())")
                case .curve: parts.append("C\(next()),\(next()) \(next()),\(next()) \(next()),\(next())")
                case .close: parts.append("Z")
                }
            }
            return parts.joined(separator: " ")
        }
        func f(_ r: CGRect) -> String { "\(r.minX),\(r.minY),\(r.width),\(r.height)" }
        func gradientText() -> String {
            let kind = Int(next())
            let params = [4, 4, 3, 6, 5][kind]
            let numbers = (0..<params).map { _ in next() }
            let count = Int(next())
            let stops = (0..<count).map { _ in "\(next()):\(color())" }
            return "\(["linear", "radial", "angular", "focalRadial", "elliptical"][kind]) \(numbers) [\(stops.joined(separator: " "))]"
        }
        while i < ops.count {
            switch DisplayOp(rawValue: next())! {
            case .save: out.append("save")
            case .restore: out.append("restore")
            case .beginSegment: let id = Int(next()); out.append("beginSegment \(id) \(f(rect()))")
            case .endSegment: out.append("endSegment")
            case .reuseSegment: let id = Int(next()), dx = next(), dy = next(), shown = f(rect()); out.append("reuseSegment \(id) \(dx),\(dy) \(shown) \(f(rect()))")
            case .beginCullBlock: let bounds = f(rect()); out.append("beginCullBlock \(bounds) to \(Int(next()))")
            case .endCullBlock: out.append("endCullBlock")
            case .clipRect: out.append("clipRect \(f(rect()))")
            case .clipRRect: out.append("clipRRect \(f(rect())) r\(next())")
            case .clipPath: let p = path(); out.append("clipPath \(p)\(next() == 1 ? " eo" : "")")
            case .beginGroup: out.append("beginGroup \(next())")
            case .beginShadow: let c = color(); out.append("beginShadow \(c) r\(next()) \(next()),\(next())")
            case .beginFilter:
                let bounds = f(rect())
                if next() == 0 {
                    let values = (0..<20).map { _ in next() }
                    out.append("beginFilter \(bounds) matrix \(values)")
                } else {
                    out.append("beginFilter \(bounds) blur \(next())\(next() == 1 ? " opaque" : "")")
                }
            case .beginBlend: let mode = Int(next()); out.append("beginBlend \(mode) \(f(rect()))")
            case .beginMask: out.append("beginMask \(f(rect()))")
            case .beginMasked: out.append("beginMasked")
            case .endGroup: out.append("endGroup")
            case .backdropBlur: let p = path(); let bounds = f(rect()); out.append("backdropBlur \(p) \(bounds) r\(next()) sat\(next())")
            case .concat: out.append("concat \(next()),\(next()),\(next()),\(next()),\(next()),\(next())")
            case .fillGradient:
                let p = path(); let g = gradientText(); out.append("fillGradient \(p) \(g)\(next() == 1 ? " eo" : "")")
            case .strokeGradient:
                let p = path()
                let width = next(); _ = next(); _ = next(); _ = next()
                let dashes = (0..<Int(next())).map { _ in next() }; _ = next(); _ = dashes
                let g = gradientText(); out.append("strokeGradient \(p) w\(width) \(g)")
            case .fillRect: out.append("fillRect \(f(rect())) \(color())")
            case .fillRRect: let r = rect(); out.append("fillRRect \(f(r)) r\(next()) \(color())")
            case .fillPath: let p = path(); let c = color(); out.append("fillPath \(p) \(c)\(next() == 1 ? " eo" : "")")
            case .strokePath:
                let p = path()
                let width = next(), cap = Int(next()), join = Int(next()), miter = next()
                let dashes = (0..<Int(next())).map { _ in next() }
                let phase = next()
                var text = "strokePath \(p) w\(width)"
                if cap != 0 || join != 0 || miter != 10 { text += " cap\(cap) join\(join) miter\(miter)" }
                if !dashes.isEmpty { text += " dash\(dashes) phase\(phase)" }
                out.append("\(text) \(color())")
            case .drawText:
                let text = encoded.strings[Int(next())], font = encoded.strings[Int(next())]
                out.append("drawText '\(text)' [\(font)] \(next()),\(next()) \(color())")
            case .drawTextGradient:
                let text = encoded.strings[Int(next())], font = encoded.strings[Int(next())]
                let x = next(), y = next()
                out.append("drawText '\(text)' [\(font)] \(x),\(y) \(gradientText())")
            case .drawImage:
                let file = encoded.strings[Int(next())]
                let scale = next(), pw = next(), ph = next()
                let r = rect()
                let tile = next() == 1
                let insets = "\(next()),\(next()),\(next()),\(next())"
                let smoothing = next() == 1, tintKind = Int(next())
                var tint = color()
                if tintKind == 2 { tint = gradientText() }
                out.append("drawImage \(file) @\(scale)x \(Int(pw))x\(Int(ph)) \(f(r))\(tile ? " tile" : "") insets \(insets)\(smoothing ? "" : " nearest")\(tintKind > 0 ? " tint " + tint : "")")
            case .drawBitmap:
                let bitmap = encoded.bitmaps[Int(next())]
                out.append("drawBitmap \(bitmap.width)x\(bitmap.height) \(f(rect()))")
            }
        }
        return out
    }
}
