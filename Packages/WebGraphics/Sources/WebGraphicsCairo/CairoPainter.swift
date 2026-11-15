// The Cairo painter (pf-linux, decision 0018): paints a display list into a cairo context —
// an image surface for tests and snapshots, a GTK drawing area's context in the window host.
// The display list is backend-neutral: rects, rounded rects, paths, strokes, gradients, clips,
// transforms and opacity groups map onto cairo one to one; shadows, filters, blend modes and
// masks are composited through intermediate groups where cairo has the operator (blend modes)
// and approximated where it has none (a shadow is a blurred-looking offset copy at the
// colour, a filter leaves its group as is, a backdrop blur fills with the ground's average
// tint). Text goes through cairo's toy font API with the display font's family, weight and
// slant, so the glyph shapes are the system's fonts (metrics come from the scene's text
// engine, the same as in the browser). Images are loaded from PNG files (cairo reads PNG);
// bitmaps are drawn from their pixels.
#if canImport(CCairo)
import CCairo
import WebFoundation
import WebGraphics

@MainActor
public final class CairoPainter {
    /// The directory image files are resolved against (the asset manifest's base).
    public var assetBase: URL?
    /// Loaded PNG surfaces by file, freed with the cache (or by `releaseImages`).
    private var imageCache = ImageCache()

    /// Owns loaded surfaces and destroys them when it goes.
    private final class ImageCache: @unchecked Sendable {
        var surfaces: [String: OpaquePointer] = [:]
        deinit { for surface in surfaces.values { cairo_surface_destroy(surface) } }
    }

    public init() {}

    /// Drops the loaded images (a changed asset base).
    public func releaseImages() { imageCache = ImageCache() }

    // MARK: Surfaces

    /// Paints `list` into a new RGBA image of `size` points at `scale`, returning the surface
    /// (the caller destroys it) and its premultiplied BGRA pixels.
    public func image(of list: DisplayList, size: CGSize, scale: CGFloat, background: RGBA? = nil) -> (surface: OpaquePointer, width: Int, height: Int) {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height))!
        let context = cairo_create(surface)!
        cairo_scale(context, Double(scale), Double(scale))
        if let background {
            setColor(context, background)
            cairo_paint(context)
        }
        paint(list, into: context)
        cairo_destroy(context)
        cairo_surface_flush(surface)
        return (surface, width, height)
    }

    /// The pixel at (`x`, `y`) of a painted image surface, as an RGBA with straight alpha.
    public static func pixel(of surface: OpaquePointer, x: Int, y: Int) -> RGBA {
        let stride = Int(cairo_image_surface_get_stride(surface))
        guard let data = cairo_image_surface_get_data(surface) else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        let offset = y * stride + x * 4
        let b = Double(data[offset]), g = Double(data[offset + 1]), r = Double(data[offset + 2]), a = Double(data[offset + 3])
        guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        return RGBA(r: Int((r / a * 255).rounded()), g: Int((g / a * 255).rounded()), b: Int((b / a * 255).rounded()), a: a / 255)
    }

    /// Writes a painted surface as a PNG file.
    @discardableResult
    public static func writePNG(_ surface: OpaquePointer, to path: String) -> Bool {
        cairo_surface_write_to_png(surface, path) == CAIRO_STATUS_SUCCESS
    }

    // MARK: Painting

    /// Paints `list` into `context`, whose user space is in points.
    public func paint(_ list: DisplayList, into context: OpaquePointer) {
        var groups: [Group] = []
        for command in list.commands {
            switch command {
            case .save: cairo_save(context)
            case .restore: cairo_restore(context)
            case .clipRect(let rect):
                addRect(context, rect)
                cairo_clip(context)
            case .clipRRect(let rect, let radius):
                addRoundedRect(context, rect, radius)
                cairo_clip(context)
            case .clipPath(let path, let eo):
                addPath(context, path)
                cairo_set_fill_rule(context, eo ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
                cairo_clip(context)
            case .beginGroup(let opacity):
                cairo_push_group(context)
                groups.append(.opacity(opacity))
            case .beginShadow(let color, let radius, let offset):
                cairo_push_group(context)
                groups.append(.shadow(color, radius: radius, offset: offset))
            case .beginFilter(let filter, _):
                cairo_push_group(context)
                groups.append(.filter(filter))
            case .beginBlend(let mode, _):
                cairo_push_group(context)
                groups.append(.blend(mode))
            case .beginMask:
                cairo_push_group(context)
                groups.append(.mask(nil))
            case .beginMasked:
                // The mask's drawing ends here: it becomes a pattern, the masked content starts.
                guard case .mask = groups.last else { continue }
                let mask = cairo_pop_group(context)
                groups[groups.count - 1] = .mask(mask)
                cairo_push_group(context)
            case .endGroup:
                guard let group = groups.popLast() else { continue }
                end(group, context)
            case .backdropBlur(let path, let bounds, _, _):
                // No backdrop access here: a translucent white over the path stands in for the blur.
                cairo_save(context)
                addPath(context, path)
                cairo_clip(context)
                cairo_set_source_rgba(context, 1, 1, 1, 0.6)
                addRect(context, bounds)
                cairo_fill(context)
                cairo_restore(context)
            case .concat(let transform):
                var matrix = cairo_matrix_t(xx: Double(transform.a), yx: Double(transform.b), xy: Double(transform.c), yy: Double(transform.d), x0: Double(transform.tx), y0: Double(transform.ty))
                cairo_transform(context, &matrix)
            case .fillRect(let rect, let color):
                setColor(context, color)
                addRect(context, rect)
                cairo_fill(context)
            case .fillRRect(let rect, let radius, let color):
                setColor(context, color)
                addRoundedRect(context, rect, radius)
                cairo_fill(context)
            case .fillPath(let path, let color, let eo):
                setColor(context, color)
                addPath(context, path)
                cairo_set_fill_rule(context, eo ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
                cairo_fill(context)
            case .strokePath(let path, let style, let color):
                setColor(context, color)
                addPath(context, path)
                apply(style, context)
                cairo_stroke(context)
            case .fillGradient(let path, let gradient, let eo):
                guard let pattern = makePattern(gradient, bounds: path.boundingRect) else { continue }
                cairo_set_source(context, pattern)
                addPath(context, path)
                cairo_set_fill_rule(context, eo ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
                cairo_fill(context)
                cairo_pattern_destroy(pattern)
            case .strokeGradient(let path, let style, let gradient):
                guard let pattern = makePattern(gradient, bounds: path.boundingRect) else { continue }
                cairo_set_source(context, pattern)
                addPath(context, path)
                apply(style, context)
                cairo_stroke(context)
                cairo_pattern_destroy(pattern)
            case .drawText(let text, let font, let origin, let color):
                setColor(context, color)
                drawText(context, text, font, origin)
            case .drawTextGradient(let text, let font, let origin, let gradient):
                let extent = CGRect(x: origin.x, y: origin.y - font.size, width: font.size * CGFloat(text.count), height: font.size * 1.3)
                guard let pattern = makePattern(gradient, bounds: extent) else { continue }
                cairo_set_source(context, pattern)
                drawText(context, text, font, origin)
                cairo_pattern_destroy(pattern)
            case .drawImage(let draw):
                drawImage(context, draw)
            case .drawBitmap(let bitmap, let rect):
                drawBitmap(context, bitmap, rect)
            // Segments and cull blocks only mark the commands: this painter draws every frame's
            // whole list (only a host that keeps segments is sent `reuseSegment`).
            case .beginSegment, .endSegment, .reuseSegment, .beginCullBlock, .endCullBlock: break
            }
        }
        for group in groups.reversed() { end(group, context) }
    }

    private enum Group {
        case opacity(Double)
        case shadow(RGBA, radius: CGFloat, offset: CGSize)
        case filter(DisplayFilter)
        case blend(BlendMode)
        case mask(OpaquePointer?)
    }

    private func end(_ group: Group, _ context: OpaquePointer) {
        switch group {
        case .opacity(let opacity):
            cairo_pop_group_to_source(context)
            cairo_paint_with_alpha(context, opacity)
        case .shadow(let color, let radius, let offset):
            // The group's shape, offset and tinted at the colour under the group itself (the
            // blur is not reproduced: cairo has no filter, so the shadow's edge is sharp at
            // a lowered alpha that stands in for the spread).
            let pattern = cairo_pop_group(context)!
            cairo_save(context)
            cairo_translate(context, Double(offset.width), Double(offset.height))
            setColor(context, RGBA(r: Int(color.red * 255), g: Int(color.green * 255), b: Int(color.blue * 255), a: color.alpha * (radius > 0 ? 0.6 : 1)))
            cairo_mask(context, pattern)
            cairo_restore(context)
            cairo_set_source(context, pattern)
            cairo_paint(context)
            cairo_pattern_destroy(pattern)
        case .filter:
            cairo_pop_group_to_source(context)
            cairo_paint(context)
        case .blend(let mode):
            cairo_pop_group_to_source(context)
            cairo_save(context)
            cairo_set_operator(context, Self.operator(for: mode))
            cairo_paint(context)
            cairo_restore(context)
        case .mask(let mask):
            let content = cairo_pop_group(context)!
            cairo_set_source(context, content)
            if let mask { cairo_mask(context, mask); cairo_pattern_destroy(mask) } else { cairo_paint(context) }
            cairo_pattern_destroy(content)
        }
    }

    private static func `operator`(for mode: BlendMode) -> cairo_operator_t {
        switch mode {
        case .multiply: return CAIRO_OPERATOR_MULTIPLY
        case .screen: return CAIRO_OPERATOR_SCREEN
        case .overlay: return CAIRO_OPERATOR_OVERLAY
        case .darken: return CAIRO_OPERATOR_DARKEN
        case .lighten: return CAIRO_OPERATOR_LIGHTEN
        case .colorDodge: return CAIRO_OPERATOR_COLOR_DODGE
        case .colorBurn: return CAIRO_OPERATOR_COLOR_BURN
        case .hardLight: return CAIRO_OPERATOR_HARD_LIGHT
        case .softLight: return CAIRO_OPERATOR_SOFT_LIGHT
        case .difference: return CAIRO_OPERATOR_DIFFERENCE
        case .exclusion: return CAIRO_OPERATOR_EXCLUSION
        case .hue: return CAIRO_OPERATOR_HSL_HUE
        case .saturation: return CAIRO_OPERATOR_HSL_SATURATION
        case .color: return CAIRO_OPERATOR_HSL_COLOR
        case .luminosity: return CAIRO_OPERATOR_HSL_LUMINOSITY
        case .sourceAtop: return CAIRO_OPERATOR_ATOP
        case .destinationOver: return CAIRO_OPERATOR_DEST_OVER
        case .destinationOut: return CAIRO_OPERATOR_DEST_OUT
        case .plusLighter: return CAIRO_OPERATOR_ADD
        default: return CAIRO_OPERATOR_OVER
        }
    }

    // MARK: Primitives

    private func setColor(_ context: OpaquePointer, _ color: RGBA) {
        cairo_set_source_rgba(context, color.red, color.green, color.blue, color.alpha)
    }

    private func addRect(_ context: OpaquePointer, _ rect: CGRect) {
        cairo_rectangle(context, Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height))
    }

    private func addRoundedRect(_ context: OpaquePointer, _ rect: CGRect, _ radius: CGFloat) {
        let r = Double(min(radius, min(rect.width, rect.height) / 2))
        guard r > 0 else { addRect(context, rect); return }
        let x0 = Double(rect.minX), y0 = Double(rect.minY), x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        cairo_new_sub_path(context)
        cairo_arc(context, x1 - r, y0 + r, r, -Double.pi / 2, 0)
        cairo_arc(context, x1 - r, y1 - r, r, 0, Double.pi / 2)
        cairo_arc(context, x0 + r, y1 - r, r, Double.pi / 2, Double.pi)
        cairo_arc(context, x0 + r, y0 + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(context)
    }

    private func addPath(_ context: OpaquePointer, _ path: Path) {
        cairo_new_path(context)
        var current = CGPoint.zero
        for element in path.elements {
            switch element {
            case .move(let to):
                cairo_move_to(context, Double(to.x), Double(to.y))
                current = to
            case .line(let to):
                cairo_line_to(context, Double(to.x), Double(to.y))
                current = to
            case .quadCurve(let to, let control):
                // A quadratic as a cubic: the controls two thirds of the way to the quadratic's.
                let c1 = CGPoint(x: current.x + 2 / 3 * (control.x - current.x), y: current.y + 2 / 3 * (control.y - current.y))
                let c2 = CGPoint(x: to.x + 2 / 3 * (control.x - to.x), y: to.y + 2 / 3 * (control.y - to.y))
                cairo_curve_to(context, Double(c1.x), Double(c1.y), Double(c2.x), Double(c2.y), Double(to.x), Double(to.y))
                current = to
            case .curve(let to, let control1, let control2):
                cairo_curve_to(context, Double(control1.x), Double(control1.y), Double(control2.x), Double(control2.y), Double(to.x), Double(to.y))
                current = to
            case .closeSubpath:
                cairo_close_path(context)
            }
        }
    }

    private func apply(_ style: StrokeStyle, _ context: OpaquePointer) {
        cairo_set_line_width(context, Double(style.lineWidth))
        switch style.lineCap {
        case .round: cairo_set_line_cap(context, CAIRO_LINE_CAP_ROUND)
        case .square: cairo_set_line_cap(context, CAIRO_LINE_CAP_SQUARE)
        default: cairo_set_line_cap(context, CAIRO_LINE_CAP_BUTT)
        }
        switch style.lineJoin {
        case .round: cairo_set_line_join(context, CAIRO_LINE_JOIN_ROUND)
        case .bevel: cairo_set_line_join(context, CAIRO_LINE_JOIN_BEVEL)
        default: cairo_set_line_join(context, CAIRO_LINE_JOIN_MITER)
        }
        cairo_set_miter_limit(context, Double(style.miterLimit))
        if style.dash.isEmpty {
            cairo_set_dash(context, nil, 0, 0)
        } else {
            let dashes = style.dash.map(Double.init)
            dashes.withUnsafeBufferPointer { cairo_set_dash(context, $0.baseAddress, Int32($0.count), Double(style.dashPhase)) }
        }
    }

    private func makePattern(_ gradient: DisplayGradient, bounds: CGRect) -> OpaquePointer? {
        let pattern: OpaquePointer?
        switch gradient.kind {
        case .linear(let start, let end):
            pattern = cairo_pattern_create_linear(Double(start.x), Double(start.y), Double(end.x), Double(end.y))
        case .radial(let center, let startRadius, let endRadius):
            pattern = cairo_pattern_create_radial(Double(center.x), Double(center.y), Double(startRadius), Double(center.x), Double(center.y), Double(endRadius))
        case .focalRadial(let startCenter, let startRadius, let endCenter, let endRadius):
            pattern = cairo_pattern_create_radial(Double(startCenter.x), Double(startCenter.y), Double(startRadius), Double(endCenter.x), Double(endCenter.y), Double(endRadius))
        case .elliptical(let center, let startRadius, let endRadius, _):
            pattern = cairo_pattern_create_radial(Double(center.x), Double(center.y), Double(startRadius), Double(center.x), Double(center.y), Double(endRadius))
        case .angular(let center, _):
            // Cairo has no conic gradient: the stops run radially from the centre instead.
            let radius = Double(max(bounds.width, bounds.height) / 2)
            pattern = cairo_pattern_create_radial(Double(center.x), Double(center.y), 0, Double(center.x), Double(center.y), radius)
        }
        guard let pattern else { return nil }
        for stop in gradient.stops {
            cairo_pattern_add_color_stop_rgba(pattern, stop.location, stop.color.red, stop.color.green, stop.color.blue, stop.color.alpha)
        }
        return pattern
    }

    // MARK: Text

    private func drawText(_ context: OpaquePointer, _ text: String, _ font: DisplayFont, _ origin: CGPoint) {
        let family: String
        switch font.family {
        case "system", "system-rounded": family = "sans-serif"
        case "system-serif": family = "serif"
        case "system-monospaced": family = "monospace"
        default: family = font.family
        }
        cairo_select_font_face(context, family, font.italic ? CAIRO_FONT_SLANT_ITALIC : CAIRO_FONT_SLANT_NORMAL, font.weight >= 600 ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(context, Double(font.size))
        cairo_move_to(context, Double(origin.x), Double(origin.y))
        if font.letterSpacing != 0 {
            var x = Double(origin.x)
            for character in text {
                let glyph = String(character)
                cairo_move_to(context, x, Double(origin.y))
                cairo_show_text(context, glyph)
                var extents = cairo_text_extents_t()
                cairo_text_extents(context, glyph, &extents)
                x += extents.x_advance + Double(font.letterSpacing)
            }
        } else {
            cairo_show_text(context, text)
        }
    }

    // MARK: Images

    private func surface(for file: String) -> OpaquePointer? {
        if let cached = imageCache.surfaces[file] { return cached }
        let path: String
        if file.hasPrefix("/") {
            path = file
        } else if let base = assetBase {
            path = base.appendingPathComponent(file).path
        } else {
            path = file
        }
        let surface = cairo_image_surface_create_from_png(path)
        guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else {
            if let surface { cairo_surface_destroy(surface) }
            return nil
        }
        imageCache.surfaces[file] = surface
        return surface
    }

    private func drawImage(_ context: OpaquePointer, _ draw: ImageDraw) {
        guard let surface = surface(for: draw.file) else { return }
        let width = Double(cairo_image_surface_get_width(surface)), height = Double(cairo_image_surface_get_height(surface))
        guard width > 0, height > 0 else { return }
        cairo_save(context)
        addRect(context, draw.rect)
        cairo_clip(context)
        if draw.tiles {
            let pattern = cairo_pattern_create_for_surface(surface)
            cairo_pattern_set_extend(pattern, CAIRO_EXTEND_REPEAT)
            var matrix = cairo_matrix_t()
            cairo_matrix_init_scale(&matrix, Double(draw.scale), Double(draw.scale))
            cairo_matrix_translate(&matrix, -Double(draw.rect.minX), -Double(draw.rect.minY))
            cairo_pattern_set_matrix(pattern, &matrix)
            cairo_set_source(context, pattern)
            cairo_paint(context)
            cairo_pattern_destroy(pattern)
        } else {
            cairo_translate(context, Double(draw.rect.minX), Double(draw.rect.minY))
            cairo_scale(context, Double(draw.rect.width) / width, Double(draw.rect.height) / height)
            cairo_set_source_surface(context, surface, 0, 0)
            cairo_paint(context)
        }
        cairo_restore(context)
    }

    private func drawBitmap(_ context: OpaquePointer, _ bitmap: DisplayBitmap, _ rect: CGRect) {
        guard bitmap.width > 0, bitmap.height > 0 else { return }
        // The bitmap's RGBA bytes as cairo's premultiplied BGRA.
        let stride = Int(cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(bitmap.width)))
        var data = [UInt8](repeating: 0, count: stride * bitmap.height)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let source = (y * bitmap.width + x) * 4
                guard source + 3 < bitmap.pixels.count else { continue }
                let a = Int(bitmap.pixels[source + 3])
                let target = y * stride + x * 4
                data[target] = UInt8(Int(bitmap.pixels[source + 2]) * a / 255)
                data[target + 1] = UInt8(Int(bitmap.pixels[source + 1]) * a / 255)
                data[target + 2] = UInt8(Int(bitmap.pixels[source]) * a / 255)
                data[target + 3] = UInt8(a)
            }
        }
        data.withUnsafeMutableBufferPointer { buffer in
            guard let surface = cairo_image_surface_create_for_data(buffer.baseAddress, CAIRO_FORMAT_ARGB32, Int32(bitmap.width), Int32(bitmap.height), Int32(stride)) else { return }
            cairo_save(context)
            cairo_translate(context, Double(rect.minX), Double(rect.minY))
            cairo_scale(context, Double(rect.width) / Double(bitmap.width), Double(rect.height) / Double(bitmap.height))
            cairo_set_source_surface(context, surface, 0, 0)
            cairo_paint(context)
            cairo_restore(context)
            cairo_surface_destroy(surface)
        }
    }
}
#endif
