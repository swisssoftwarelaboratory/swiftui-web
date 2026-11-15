// Custom drawing (Docs/elements/UIKit/Drawing.md): `draw(_:)` runs with a recording graphics
// context as the current context, which turns the CoreGraphics-style calls (`UIGraphicsGetCurrentContext`,
// `UIBezierPath.fill`, `UIColor.setFill`, `UIRectFill`) into display list commands in the view's
// coordinates. On wasm the context is what `CGContext` names; on Apple platforms CoreGraphics
// keeps that name and `UIGraphicsGetCurrentContext()` returns this class (decision 0014, Phase 3).

/// A graphics context recording into the display list: the current transform, colours, line
/// style and alpha form a state the `saveGState`/`restoreGState` stack keeps, paths are built in
/// user space and painted through the current transform.
@preconcurrency @MainActor
public final class UIGraphicsRecordingContext {
    private struct State {
        var fill = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        var stroke = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        var lineWidth: CGFloat = 1
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var miterLimit: CGFloat = 10
        var dash: [CGFloat] = []
        var dashPhase: CGFloat = 0
        var alpha: CGFloat = 1
        var ctm = CGAffineTransform.identity
        var shadow: (color: RGBA, radius: CGFloat, offset: CGSize)?
        /// The display list's blend mode for what follows; nil composites normally.
        var blend: BlendMode?
    }

    /// The recorded commands (absolute coordinates through the origin the context was made for).
    private(set) var commands: [DisplayCommand] = []
    /// The context's origin in the recording's space (where `drawHierarchy` paints a view).
    var paintOrigin: CGPoint { CGPoint(x: state.ctm.tx, y: state.ctm.ty) }
    /// Appends a painted display list (a view hierarchy drawn into this context).
    func append(painted list: DisplayList) { commands += list.commands }
    private var state = State()
    private var stack: [State] = []
    private var path = Path()
    /// Open groups (a shadow) per saved state, closed on restore.
    private var openGroups: [Int] = []
    private var groupsInState = 0
    let scale: CGFloat
    /// Whether anything was painted with a blend mode (or cleared): the view's own painting
    /// then goes in a group of its own, so the modes composite against the view's background
    /// and earlier drawing, as CoreGraphics composites in a layer's backing store.
    private(set) var usesBlending = false

    /// The size in points of the image an image context draws (nil for a view's context): what
    /// `width`, `height` and `makeImage()` report.
    let canvasSize: CGSize?

    init(origin: CGPoint, scale: CGFloat, canvasSize: CGSize? = nil) {
        self.scale = scale
        self.canvasSize = canvasSize
        state.ctm = CGAffineTransform(translationX: origin.x, y: origin.y)
    }

    // MARK: State

    public func saveGState() {
        stack.append(state)
        openGroups.append(groupsInState)
        groupsInState = 0
    }

    public func restoreGState() {
        guard let saved = stack.popLast() else { return }
        for _ in 0..<groupsInState { commands.append(.endGroup) }
        groupsInState = openGroups.popLast() ?? 0
        // Clips made since the save end with it.
        if clipsInState > 0 { commands.append(.restore); clipsInState = 0 }
        clipsInState = clipStack.popLast() ?? 0
        state = saved
    }

    private var clipsInState = 0
    private var clipStack: [Int] = []

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(translationX: x, y: y).concatenating(state.ctm) }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(state.ctm) }
    public func rotate(by angle: CGFloat) { state.ctm = CGAffineTransform(rotationAngle: angle).concatenating(state.ctm) }
    public func concatenate(_ transform: CGAffineTransform) { state.ctm = transform.concatenating(state.ctm) }

    public func setFillColor(_ color: CGColor) { if let rgba = RGBA(cgColor: color) { state.fill = rgba } }
    public func setStrokeColor(_ color: CGColor) { if let rgba = RGBA(cgColor: color) { state.stroke = rgba } }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.fill = RGBA(red: red, green: green, blue: blue, alpha: alpha) }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.stroke = RGBA(red: red, green: green, blue: blue, alpha: alpha) }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { state.fill = RGBA(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { state.stroke = RGBA(red: gray, green: gray, blue: gray, alpha: alpha) }
    public func setLineWidth(_ width: CGFloat) { state.lineWidth = width }
    public func setLineCap(_ cap: CGLineCap) { state.lineCap = cap }
    public func setLineJoin(_ join: CGLineJoin) { state.lineJoin = join }
    public func setMiterLimit(_ limit: CGFloat) { state.miterLimit = limit }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { state.dash = lengths; state.dashPhase = phase }
    public func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }
    /// The blend mode for what follows until the state is restored (`.copy`, `.sourceIn`,
    /// `.sourceOut`, `.destinationIn`, `.destinationAtop` and `.xor` composite normally: the
    /// display list has no group for them).
    public func setBlendMode(_ mode: CGBlendMode) { state.blend = Self.blendMode(mode) }
    /// Accepted: the painters always antialias.
    public func setShouldAntialias(_ flag: Bool) {}
    public func setAllowsAntialiasing(_ flag: Bool) {}
    public func interpolationQuality(_ quality: Int) {}

    static func blendMode(_ mode: CGBlendMode) -> BlendMode? {
        switch mode {
        case .normal, .copy, .sourceIn, .sourceOut, .destinationIn, .destinationAtop, .xor: return nil
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
        case .destinationOut, .clear: return .destinationOut
        case .plusDarker: return .plusDarker
        case .plusLighter: return .plusLighter
        @unknown default: return nil
        }
    }

    /// Runs `body` with `mode` as the blend mode (the `with:alpha:` drawing forms).
    func withBlendMode(_ mode: CGBlendMode, _ body: () -> Void) {
        let previous = state.blend
        state.blend = Self.blendMode(mode)
        body()
        state.blend = previous
    }

    /// A shadow for what follows until the state is restored.
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        guard let color, let rgba = RGBA(cgColor: color) else { state.shadow = nil; return }
        state.shadow = (rgba, blur, offset)
    }

    public func setShadow(offset: CGSize, blur: CGFloat) {
        state.shadow = (RGBA(red: 0, green: 0, blue: 0, alpha: 1.0 / 3), blur, offset)
    }

    // MARK: Paths

    public func beginPath() { path = Path() }
    public func move(to point: CGPoint) { path.move(to: point) }
    public func addLine(to point: CGPoint) { path.addLine(to: point) }
    public func addLines(between points: [CGPoint]) { path.addLines(points) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { path.addCurve(to: end, control1: control1, control2: control2) }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) { path.addQuadCurve(to: end, control: control) }
    public func addRect(_ rect: CGRect) { path.addRect(rect) }
    public func addRects(_ rects: [CGRect]) { path.addRects(rects) }
    public func addEllipse(in rect: CGRect) { path.addEllipse(in: rect) }
    /// `clockwise` in CoreGraphics's sense (y up): in the view's flipped space `false` runs
    /// through increasing angles, clockwise on screen, as `CGMutablePath.addArc` (uikit/draw/rest).
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        path.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(startAngle)), endAngle: Angle(radians: Double(endAngle)), clockwise: clockwise)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) { path.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius) }
    public func addPath(_ other: Path) { path.addPath(other) }
    public func closePath() { path.closeSubpath() }
    public var isPathEmpty: Bool { path.isEmpty }
    public var currentPointOfPath: CGPoint { path.currentPoint ?? .zero }
    public var boundingBoxOfPath: CGRect { path.boundingRect }

    /// Fills the current path and clears it.
    public func fillPath() { fillPath(using: .winding) }
    public func fillPath(using rule: CGPathFillRule) {
        paintFill(path, evenOdd: rule == .evenOdd, alpha: 1)
        path = Path()
    }

    /// Strokes the current path and clears it.
    public func strokePath() {
        paintStroke(path, style: strokeStyle, alpha: 1)
        path = Path()
    }

    public func drawPath(using mode: CGPathDrawingMode) {
        switch mode {
        case .fill: paintFill(path, evenOdd: false, alpha: 1)
        case .eoFill: paintFill(path, evenOdd: true, alpha: 1)
        case .stroke: paintStroke(path, style: strokeStyle, alpha: 1)
        case .fillStroke: paintFill(path, evenOdd: false, alpha: 1); paintStroke(path, style: strokeStyle, alpha: 1)
        case .eoFillStroke: paintFill(path, evenOdd: true, alpha: 1); paintStroke(path, style: strokeStyle, alpha: 1)
        @unknown default: paintFill(path, evenOdd: false, alpha: 1)
        }
        path = Path()
    }

    public func fill(_ rect: CGRect) { paintFill(Path(rect), evenOdd: false, alpha: 1) }
    public func fill(_ rects: [CGRect]) { for rect in rects { fill(rect) } }
    public func stroke(_ rect: CGRect) { paintStroke(Path(rect), style: strokeStyle, alpha: 1) }
    public func stroke(_ rect: CGRect, width: CGFloat) {
        var style = strokeStyle
        style.lineWidth = width
        paintStroke(Path(rect), style: style, alpha: 1)
    }
    public func fillEllipse(in rect: CGRect) { paintFill(Path(ellipseIn: rect), evenOdd: false, alpha: 1) }
    public func strokeEllipse(in rect: CGRect) { paintStroke(Path(ellipseIn: rect), style: strokeStyle, alpha: 1) }
    public func strokeLineSegments(between points: [CGPoint]) {
        var segments = Path()
        var index = 0
        while index + 1 < points.count {
            segments.move(to: points[index])
            segments.addLine(to: points[index + 1])
            index += 2
        }
        paintStroke(segments, style: strokeStyle, alpha: 1)
    }
    /// Clears `rect` to transparent: what the view painted there (its background included)
    /// goes, and what lies beneath the view shows.
    public func clear(_ rect: CGRect) {
        let previous = state.blend
        state.blend = .destinationOut
        withBlend(Path(rect).applying(state.ctm).boundingRect) { commands.append(.fillPath(Path(rect).applying(state.ctm), RGBA(red: 0, green: 0, blue: 0, alpha: 1))) }
        state.blend = previous
    }

    // MARK: Clipping

    /// Clips to the current path (and clears it) until the state is restored.
    public func clip() { clip(using: .winding) }
    public func clip(using rule: CGPathFillRule) {
        clip(to: path, evenOdd: rule == .evenOdd)
        path = Path()
    }
    public func clip(to rect: CGRect) { clip(to: Path(rect), evenOdd: false) }
    public func clip(to rects: [CGRect]) { clip(to: Path { for rect in rects { $0.addRect(rect) } }, evenOdd: false) }

    func clip(to path: Path, evenOdd: Bool) {
        commands.append(.save)
        commands.append(.clipPath(path.applying(state.ctm), eoFill: evenOdd))
        clipsInState += 1
    }

    // MARK: Transparency layers

    public func beginTransparencyLayer(auxiliaryInfo: [String: Any]?) {
        commands.append(.beginGroup(opacity: Double(state.alpha)))
        groupsInState += 1
    }
    public func endTransparencyLayer() {
        guard groupsInState > 0 else { return }
        commands.append(.endGroup)
        groupsInState -= 1
    }

    // MARK: Painting

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: state.lineWidth, lineCap: state.lineCap, lineJoin: state.lineJoin, miterLimit: state.miterLimit, dash: state.dash, dashPhase: state.dashPhase)
    }

    func fill(_ bezier: UIBezierPath, alpha: CGFloat) { paintFill(bezier.cgPath, evenOdd: bezier.usesEvenOddFillRule, alpha: alpha) }
    func stroke(_ bezier: UIBezierPath, alpha: CGFloat) { paintStroke(bezier.cgPath, style: bezier.strokeStyle, alpha: alpha) }

    private func withShadow(_ body: () -> Void) {
        if let shadow = state.shadow {
            commands.append(.beginShadow(shadow.color, radius: shadow.radius, offset: shadow.offset))
            body()
            commands.append(.endGroup)
        } else {
            body()
        }
    }

    /// Wraps one painted operation over `bounds` (absolute) in a blend group when a blend mode
    /// is set, the shadow group inside it.
    private func withBlend(_ bounds: CGRect, _ body: () -> Void) {
        if let blend = state.blend {
            usesBlending = true
            let shadow = state.shadow.map { max($0.radius * 3, abs($0.offset.width), abs($0.offset.height)) } ?? 0
            commands.append(.beginBlend(blend, bounds: bounds.insetBy(dx: -shadow, dy: -shadow)))
            withShadow(body)
            commands.append(.endGroup)
        } else {
            withShadow(body)
        }
    }

    private func paintFill(_ path: Path, evenOdd: Bool, alpha: CGFloat) {
        guard !path.isEmpty else { return }
        let color = state.fill.multiplyingAlpha(by: Double(state.alpha * alpha))
        let absolute = path.applying(state.ctm)
        withBlend(absolute.boundingRect) { commands.append(.fillPath(absolute, color, eoFill: evenOdd)) }
    }

    private func paintStroke(_ path: Path, style: StrokeStyle, alpha: CGFloat) {
        guard !path.isEmpty else { return }
        let color = state.stroke.multiplyingAlpha(by: Double(state.alpha * alpha))
        // The stroke width scales with the transform (uniformly, as far as it is uniform).
        let magnitude = (state.ctm.a * state.ctm.a + state.ctm.b * state.ctm.b).squareRoot()
        var scaled = style
        scaled.lineWidth = style.lineWidth * magnitude
        scaled.dash = style.dash.map { $0 * magnitude }
        scaled.dashPhase = style.dashPhase * magnitude
        let absolute = path.applying(state.ctm)
        let reach = scaled.lineWidth * max(1, scaled.miterLimit / 2)
        withBlend(absolute.boundingRect.insetBy(dx: -reach, dy: -reach)) { commands.append(.strokePath(absolute, style: scaled, color)) }
    }

    /// The current alpha, for text and image drawing.
    var currentAlpha: CGFloat { state.alpha }

    /// Records one absolute command over `bounds` inside the shadow (and blend) group when
    /// there is one.
    func recordShadowed(_ command: DisplayCommand, bounds: CGRect) { withBlend(bounds) { commands.append(command) } }

    /// Records commands spelled in the context's own coordinates over `bounds` (in those
    /// coordinates too): between a concat of the transform and a restore, inside the shadow
    /// (and blend) group when there is one.
    func record(_ local: [DisplayCommand], bounds: CGRect) {
        guard !local.isEmpty else { return }
        let ctm = state.ctm
        withBlend(bounds.applying(ctm)) {
            commands.append(.save)
            commands.append(.concat(ctm))
            commands.append(contentsOf: local)
            commands.append(.restore)
        }
    }

    /// What has been recorded, with what is still open closed (as `finish` would close it).
    var closedCommands: [DisplayCommand] {
        var out = commands
        var groups = groupsInState, clips = clipsInState
        var savedGroups = openGroups, savedClips = clipStack
        while true {
            out += Array(repeating: DisplayCommand.endGroup, count: groups)
            if clips > 0 { out.append(.restore) }
            guard let next = savedGroups.popLast() else { break }
            groups = next
            clips = savedClips.popLast() ?? 0
        }
        return out
    }

    /// Closes what is still open when drawing ends.
    func finish() {
        while !stack.isEmpty { restoreGState() }
        for _ in 0..<groupsInState { commands.append(.endGroup) }
        groupsInState = 0
        if clipsInState > 0 { commands.append(.restore); clipsInState = 0 }
    }
}

// MARK: - The current context

@MainActor private var contextStack: [UIGraphicsRecordingContext] = []

/// The current graphics context: the one a `draw(_:)` is running in, else nil.
@preconcurrency @MainActor public func UIGraphicsGetCurrentContext() -> UIGraphicsRecordingContext? { contextStack.last }

@preconcurrency @MainActor public func UIGraphicsPushContext(_ context: UIGraphicsRecordingContext) { contextStack.append(context) }
@preconcurrency @MainActor public func UIGraphicsPopContext() { _ = contextStack.popLast() }

/// Fills `rect` with the current fill colour, composited normally whatever blend mode the
/// context has (uikit/draw/rest: UIKit's `UIRectFill` is `UIRectFillUsingBlendMode(_:.normal)`).
@preconcurrency @MainActor public func UIRectFill(_ rect: CGRect) { UIRectFillUsingBlendMode(rect, .normal) }
/// Fills `rect` with the current fill colour in `blendMode`.
@preconcurrency @MainActor public func UIRectFillUsingBlendMode(_ rect: CGRect, _ blendMode: CGBlendMode) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.withBlendMode(blendMode) { context.fill(rect) }
}
/// Strokes a 1 pt frame inside `rect` with the current stroke colour, composited normally.
@preconcurrency @MainActor public func UIRectFrame(_ rect: CGRect) { UIRectFrameUsingBlendMode(rect, .normal) }
@preconcurrency @MainActor public func UIRectFrameUsingBlendMode(_ rect: CGRect, _ blendMode: CGBlendMode) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.withBlendMode(blendMode) { context.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1) }
}
@preconcurrency @MainActor public func UIRectClip(_ rect: CGRect) { UIGraphicsGetCurrentContext()?.clip(to: rect) }

extension UIColor {
    /// Sets this colour as the current context's fill colour.
    @preconcurrency @MainActor public func setFill() { UIGraphicsGetCurrentContext()?.setFillColor(rgba(for: UITraitCollection.current.userInterfaceStyle).cgColor) }
    /// Sets this colour as the current context's stroke colour.
    @preconcurrency @MainActor public func setStroke() { UIGraphicsGetCurrentContext()?.setStrokeColor(rgba(for: UITraitCollection.current.userInterfaceStyle).cgColor) }
    /// Sets this colour as both.
    @preconcurrency @MainActor public func set() { setFill(); setStroke() }
}

extension UIView {
    /// The drawing `draw(_:)` recorded (in the view's own coordinates), run now when nothing
    /// is cached for this scale and appearance: a view that does not override it draws nothing
    /// and costs one empty context once.
    func drawingRecorded(scale: CGFloat) -> DrawingCache {
        let style = traitCollection.userInterfaceStyle
        if let cache = drawingCache, cache.scale == scale, cache.style == style { return cache }
        let recorder = UIGraphicsRecordingContext(origin: .zero, scale: scale)
        // The view's traits are current while it draws (`UIColor.label.setFill()` resolves them).
        let traits = UITraitCollection.current
        UITraitCollection.current = traitCollection
        UIGraphicsPushContext(recorder)
        draw(bounds)
        UIGraphicsPopContext()
        UITraitCollection.current = traits
        recorder.finish()
        let cache = DrawingCache(commands: recorder.commands, scale: scale, style: style, usesBlending: recorder.usesBlending)
        drawingCache = cache
        return cache
    }

    /// Appends the recorded drawing, translated to the layer's absolute origin (the commands
    /// themselves move, so the list is the one an absolute recording would give).
    func drawCustomContent(into list: inout DisplayList, context: PaintContext) {
        let cache = drawingRecorded(scale: context.scale)
        guard !cache.commands.isEmpty else { return }
        for command in DrawingCache.translated(cache.commands, by: context.origin) { list.append(command) }
    }
}

extension UIView.DrawingCache {
    /// The commands moved by `offset` (`DisplayList.translated`).
    static func translated(_ commands: [DisplayCommand], by offset: CGPoint) -> [DisplayCommand] {
        DisplayList.translated(commands, by: offset)
    }
}

