import WebFoundation   // Foundation itself off wasm, the stand-ins on it (decision 0017); `Selector` where there is no Objective-C runtime
// UIImage and UIImageView (Docs/elements/UIKit/Drawing.md): catalog images (decision 0011),
// symbols, images from PNG, JPEG, GIF or WebP data (a data URL the painters load), recorded
// drawings and CGImages (UIImageCG.swift),
// drawn by content mode (uikit/imageview/modes) with their rendering mode and tint
// (uikit/imageview/tints); animated images step on the scene's clock.

/// An object that manages image data in your app.
public final class UIImage: Hashable, @unchecked Sendable {
    public enum RenderingMode: Int, Sendable { case automatic = 0, alwaysOriginal, alwaysTemplate }
    /// How an image's pixels are turned to show it upright (an image from a CGImage made with
    /// one; files decode upright on the web, so images from data are `.up`).
    public enum Orientation: Int, Sendable { case up = 0, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored }

    /// A catalog image by name, or a symbol by system name.
    public let name: String
    public let isSystemSymbol: Bool
    public let renderingMode: RenderingMode
    /// The scale the image was made for, and its point size (from the catalog, else zero).
    public let scale: CGFloat
    public let size: CGSize
    public let tint: UIColor?
    public let symbolConfiguration: SymbolConfiguration?
    /// The recording an image context made (`UIGraphicsImageRenderer`), replayed when drawn.
    public let drawing: UIImageDrawing?
    /// The bytes an image made from data holds (PNG or JPEG), and their pixel size.
    public let data: Data?
    let pixelSize: CGSize
    /// The frames of an animated image (`animatedImage(with:duration:)`) and their total duration.
    public let images: [UIImage]?
    public let duration: TimeInterval
    public let imageOrientation: Orientation
    /// The CGImage the image was made from (UIImageCG.swift), which `cgImage` returns.
    let madeFromCGImage: AnyObject?

    init(name: String, isSystemSymbol: Bool, renderingMode: RenderingMode = .automatic, scale: CGFloat = 2, size: CGSize, tint: UIColor? = nil,
         symbolConfiguration: SymbolConfiguration? = nil, drawing: UIImageDrawing? = nil, data: Data? = nil, pixelSize: CGSize = .zero,
         images: [UIImage]? = nil, duration: TimeInterval = 0, orientation: Orientation = .up, cgImage: AnyObject? = nil) {
        self.name = name
        self.isSystemSymbol = isSystemSymbol
        self.renderingMode = renderingMode
        self.scale = scale
        self.size = size
        self.tint = tint
        self.symbolConfiguration = symbolConfiguration
        self.drawing = drawing
        self.data = data
        self.pixelSize = pixelSize
        self.images = images
        self.duration = duration
        self.imageOrientation = orientation
        self.madeFromCGImage = cgImage
    }

    /// An empty image (no size, draws nothing).
    public convenience init() {
        self.init(name: "", isSystemSymbol: false, scale: 1, size: .zero)
    }

    /// Images do not change, so a copy is the image itself (`UIImage` is `NSCopying` on iOS).
    public func copy() -> Any { self }

    /// An image from PNG, JPEG, GIF or WebP bytes at `scale` (1 by default: a 40 × 40 pixel PNG
    /// is 40 points wide); nil for bytes of another kind. The painters load it as a data URL,
    /// upright (a JPEG's EXIF orientation applied, so its size is the turned one). An animated
    /// file shows as the browser shows it.
    public convenience init?(data: Data, scale: CGFloat = 1) {
        guard let info = _ImageFileInfo(data) else { return nil }
        let file = "data:\(info.kind.mimeType);base64," + data.base64EncodedString()
        let pixels = CGSize(width: info.uprightPixelSize.width, height: info.uprightPixelSize.height)
        self.init(name: file, isSystemSymbol: false, scale: scale, size: CGSize(width: pixels.width / scale, height: pixels.height / scale), data: data, pixelSize: pixels)
    }

    /// An image from the file at `path` (a bundle resource on the web), at the scale its name
    /// carries (`@2x`, `@3x`); nil when the file is missing or not an image.
    public convenience init?(contentsOfFile path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let scale: CGFloat = name.hasSuffix("@3x") ? 3 : name.hasSuffix("@2x") ? 2 : 1
        self.init(data: data, scale: scale)
    }

    /// An image that cycles through `images` over `duration` seconds in an image view.
    public static func animatedImage(with images: [UIImage], duration: TimeInterval) -> UIImage? {
        guard let first = images.first else { return nil }
        return UIImage(name: first.name, isSystemSymbol: first.isSystemSymbol, renderingMode: first.renderingMode, scale: first.scale, size: first.size,
                       tint: first.tint, symbolConfiguration: first.symbolConfiguration, drawing: first.drawing, data: first.data, pixelSize: first.pixelSize,
                       images: images, duration: duration)
    }

    /// An image made by an image context.
    public convenience init(drawing: UIImageDrawing) {
        self.init(name: "", isSystemSymbol: false, scale: drawing.scale, size: drawing.size, drawing: drawing)
    }

    /// An image from the app's asset catalog; nil when the catalog has no such name. Callable
    /// from any context, as Apple's is (a model or a background task makes images too).
    public convenience init?(named name: String) {
        guard let resource = UIKitScene._catalog.image(named: name) else { return nil }
        let size = resource.variants.max { $0.scale < $1.scale }?.pointSize ?? .zero
        self.init(name: name, isSystemSymbol: false, renderingMode: resource.isTemplate ? .alwaysTemplate : .automatic, size: size)
    }

    /// An image set of the app's asset catalog by its generated symbol (`UIImage(resource: .logo)`);
    /// an empty image when the catalog has no such set.
    @MainActor
    public convenience init(resource: ImageResource) {
        let catalogImage = UIKitScene.shared.assetCatalog.image(named: resource._name)
        let size = catalogImage?.variants.max { $0.scale < $1.scale }?.pointSize ?? .zero
        self.init(name: resource._name, isSystemSymbol: false,
                  renderingMode: catalogImage?.isTemplate == true ? .alwaysTemplate : .automatic, size: size)
    }

    /// A symbol image (drawn from the substrate's symbol table at the body size).
    public convenience init?(systemName name: String, withConfiguration configuration: SymbolConfiguration? = nil) {
        guard SystemSymbolGlyphs.table[name] != nil else { return nil }
        let pointSize = configuration?.pointSize ?? 17
        let side = (pointSize * 1.25).rounded()
        self.init(name: name, isSystemSymbol: true, renderingMode: .alwaysTemplate, size: CGSize(width: side, height: side), symbolConfiguration: configuration)
    }

    /// The catalog image for traits or a configuration: the page has one bundle, and a catalog
    /// image has one set of variants, so the image is `init(named:)`'s with the configuration kept.
    public convenience init?(named name: String, in bundle: Bundle?, compatibleWith traitCollection: UITraitCollection?) {
        self.init(named: name)
    }
    public convenience init?(named name: String, in bundle: Bundle?, with configuration: Configuration?) {
        guard let resource = UIKitScene._catalog.image(named: name) else { return nil }
        let size = resource.variants.max { $0.scale < $1.scale }?.pointSize ?? .zero
        self.init(name: name, isSystemSymbol: false, renderingMode: resource.isTemplate ? .alwaysTemplate : .automatic, size: size,
                  symbolConfiguration: configuration)
    }
    /// A variable-value image (a symbol's bars filled to `variableValue`): drawn whole here.
    public convenience init?(named name: String, in bundle: Bundle?, variableValue: Double, configuration: Configuration?) {
        self.init(named: name, in: bundle, with: configuration)
    }
    /// A symbol for traits: the symbol at the body size (traits change no glyph here).
    public convenience init?(systemName name: String, compatibleWith traitCollection: UITraitCollection?) {
        self.init(systemName: name, withConfiguration: nil)
    }
    /// A variable symbol: drawn whole, at the configuration's size.
    public convenience init?(systemName name: String, variableValue: Double, configuration: Configuration?) {
        self.init(systemName: name, withConfiguration: configuration)
    }
    /// The configuration the image was made with.
    public var configuration: Configuration? { symbolConfiguration }

    public func withRenderingMode(_ mode: RenderingMode) -> UIImage {
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: mode, scale: scale, size: size, tint: tint, symbolConfiguration: symbolConfiguration, drawing: drawing, data: data, pixelSize: pixelSize, images: images, duration: duration, orientation: imageOrientation, cgImage: madeFromCGImage)
    }

    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode = .alwaysOriginal) -> UIImage {
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: size, tint: color, symbolConfiguration: symbolConfiguration, drawing: drawing, data: data, pixelSize: pixelSize, images: images, duration: duration, orientation: imageOrientation, cgImage: madeFromCGImage)
    }

    /// The image as PNG data: the bytes an image made from PNG data holds, else a recorded
    /// drawing rasterised by the host (nil without a host rasteriser, and for catalog images
    /// and symbols, whose files the host already has).
    /// A catalog image's file (its largest variant) and whether it is a JPEG, read from the
    /// app's bundle as iOS reads it (on the web, the host fetches the asset); nil for another
    /// image or a file that cannot be read.
    private var catalogFile: (data: Data, isJPEG: Bool)? {
        #if os(WASI)
        guard !isSystemSymbol, data == nil, drawing == nil, !name.isEmpty, !name.hasPrefix("data:"),
              let variant = UIKitScene._catalog.image(named: name)?.variants.max(by: { $0.scale < $1.scale }),
              let url = URL(string: Bundle._resourceBase + variant.file),
              let bytes = try? Data(contentsOf: url) else { return nil }
        let lower = variant.file.lowercased()
        return (bytes, lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg"))
        #else
        return nil
        #endif
    }

    @preconcurrency @MainActor
    public func pngData() -> Data? {
        if let data, name.hasPrefix("data:image/png") { return data }
        if let file = catalogFile, !file.isJPEG { return file.data }
        guard let drawing, let rasterizer = UIKitScene.shared.imageRasterizer else { return nil }
        var list = DisplayList()
        for command in drawing.commands { list.append(command) }
        return rasterizer(list, drawing.size, drawing.scale)
    }

    /// JPEG is not made in this substrate: an image made from JPEG data, or a catalog image
    /// whose file is a JPEG, returns its bytes, another its PNG data, the quality ignored.
    @preconcurrency @MainActor
    public func jpegData(compressionQuality: CGFloat) -> Data? {
        if let data, name.hasPrefix("data:image/jpeg") { return data }
        if let file = catalogFile, file.isJPEG { return file.data }
        return pngData()
    }

    public func withConfiguration(_ configuration: SymbolConfiguration) -> UIImage {
        let pointSize = configuration.pointSize ?? 17
        let side = isSystemSymbol ? (pointSize * 1.25).rounded() : size.width
        return UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: CGSize(width: side, height: side), tint: tint, symbolConfiguration: configuration)
    }

    public static func == (lhs: UIImage, rhs: UIImage) -> Bool {
        lhs.name == rhs.name && lhs.isSystemSymbol == rhs.isSystemSymbol && lhs.renderingMode == rhs.renderingMode && lhs.size == rhs.size && lhs.tint == rhs.tint && lhs.drawing === rhs.drawing && lhs.images?.count == rhs.images?.count
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// An image's configuration. Apple's is a class that `SymbolConfiguration` subclasses; the
    /// symbol configuration is the only one an image here holds, so the two are one type.
    public typealias Configuration = SymbolConfiguration

    /// How a symbol image is sized and weighted.
    public struct SymbolConfiguration: Equatable, Sendable {
        public var pointSize: CGFloat?
        public var weight: UIFont.Weight?
        public var scale: Scale?
        public enum Scale: Int, Sendable { case `default` = -1, unspecified = 0, small = 1, medium = 2, large = 3 }
        public init(pointSize: CGFloat, weight: UIFont.Weight = .regular, scale: Scale = .default) {
            self.pointSize = pointSize; self.weight = weight; self.scale = scale
        }
        public init(scale: Scale) { self.scale = scale }
        public init(textStyle: UIFont.TextStyle) { pointSize = textStyle.metrics.size }
        public init(weight: UIFont.Weight) { self.weight = weight }
        public init(textStyle: UIFont.TextStyle, scale: Scale) { pointSize = textStyle.metrics.size; self.scale = scale }
        public init(font: UIFont, scale: Scale = .default) { pointSize = font.pointSize; self.scale = scale }
        /// The colour forms: a symbol here is drawn in one colour (the tint), so these size nothing
        /// and draw as the tint does.
        public init(hierarchicalColor: UIColor) {}
        public init(paletteColors: [UIColor]) {}
        public static func preferringMulticolor() -> SymbolConfiguration { SymbolConfiguration() }
        public static var unspecified: SymbolConfiguration { SymbolConfiguration() }
        private init() {}
        /// This configuration with `other`'s values over it, where `other` has them.
        public func applying(_ other: SymbolConfiguration?) -> SymbolConfiguration {
            guard let other else { return self }
            var merged = self
            if let size = other.pointSize { merged.pointSize = size }
            if let weight = other.weight { merged.weight = weight }
            if let scale = other.scale { merged.scale = scale }
            return merged
        }
        public func configurationWithoutPointSizeAndWeight() -> SymbolConfiguration {
            var copy = self
            copy.pointSize = nil
            copy.weight = nil
            return copy
        }
    }
}

/// An object that displays a single image or a sequence of animated images in your interface.
@preconcurrency @MainActor
open class UIImageView: UIView, ClockAnimating {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open var image: UIImage? { didSet { if image != oldValue { imageDidChange() } } }

    private func imageDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        // An animated image plays on its own as UIKit plays it.
        if let frames = image?.images, frames.count > 1, animationImages == nil { startAnimating() } else if animationImages == nil, isAnimating { stopAnimating() }
    }
    open var highlightedImage: UIImage?
    open var isHighlighted = false { didSet { setNeedsDisplay() } }
    open var preferredSymbolConfiguration: UIImage.SymbolConfiguration?

    // MARK: Animation (`animationImages`, or an `animatedImage`): the frames cycle over
    // `animationDuration` (the image's duration, else a 30th of a second per frame) on the
    // scene's clock, `animationRepeatCount` times (0 forever).

    open var animationImages: [UIImage]? { didSet { if animationImages == nil, isAnimating { stopAnimating() }; setNeedsDisplay() } }
    open var highlightedAnimationImages: [UIImage]?
    open var animationDuration: TimeInterval = 0
    open var animationRepeatCount = 0
    /// Whether the frames are playing (open, as UIKit's: a subclass may play them its own way).
    open var isAnimating: Bool { animating }
    private var animating = false
    private var clock: Double = 0

    /// The frames playing: `animationImages` first, else the image's own.
    private var frames: [UIImage]? {
        if let animationImages, !animationImages.isEmpty { return isHighlighted ? (highlightedAnimationImages ?? animationImages) : animationImages }
        if let frames = image?.images, frames.count > 1 { return frames }
        return nil
    }
    private var frameDuration: TimeInterval {
        guard let frames else { return 0 }
        if animationDuration > 0 { return animationDuration }
        if let image, image.images != nil, image.duration > 0 { return image.duration }
        return Double(frames.count) / 30
    }
    /// The frame showing: the clock's position in the cycle while animating; at rest the
    /// `image` (an animated image's first frame) as UIKit shows it.
    var currentFrame: UIImage? {
        guard let frames, animating, frameDuration > 0 else { return animationImages?.isEmpty == false ? image : (image?.images?.first ?? image) }
        let cycles = clock / frameDuration
        let fraction = cycles - cycles.rounded(.down)
        return frames[min(frames.count - 1, Int(fraction * Double(frames.count)))]
    }

    open func startAnimating() {
        guard frames != nil, !animating else { return }
        animating = true
        clock = 0
        UIKitScene.shared.spinners.append(WeakActivityIndicator(view: self))
        UIKitScene.shared.setNeedsFrame()
        setNeedsDisplay()
    }

    open func stopAnimating() {
        guard animating else { return }
        animating = false
        UIKitScene.shared.spinners.removeAll { $0.view === self || $0.view == nil }
        setNeedsDisplay()
    }

    func advance(elapsed: Double) {
        let before = currentFrame
        clock += elapsed
        // The repeats done, the view shows its `image` again.
        if animationRepeatCount > 0, frameDuration > 0, clock / frameDuration >= Double(animationRepeatCount) { stopAnimating() }
        if currentFrame != before { setNeedsDisplay() }
    }

    public init(image: UIImage?) {
        super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
        self.image = image
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
        if image != nil { imageDidChange() }
    }

    /// Designated, as UIKit's is, so a subclass can override it.
    public init(image: UIImage?, highlightedImage: UIImage?) {
        super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
        self.image = image
        self.highlightedImage = highlightedImage
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
        if image != nil { imageDidChange() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    override open var intrinsicContentSize: CGSize { image?.size ?? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    override open func sizeThatFits(_ size: CGSize) -> CGSize { image?.size ?? .zero }

    override open var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.image) }
        set { super.accessibilityTraits = newValue }
    }

    /// The rectangle the image draws in for the content mode.
    func imageRect(for size: CGSize) -> CGRect {
        let b = bounds
        switch contentMode {
        case .scaleToFill, .redraw: return b
        case .scaleAspectFit, .scaleAspectFill:
            guard size.width > 0, size.height > 0 else { return b }
            let scale = contentMode == .scaleAspectFit ? min(b.width / size.width, b.height / size.height) : max(b.width / size.width, b.height / size.height)
            let w = size.width * scale, h = size.height * scale
            return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
        case .center: return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .top: return CGRect(x: b.midX - size.width / 2, y: b.minY, width: size.width, height: size.height)
        case .bottom: return CGRect(x: b.midX - size.width / 2, y: b.maxY - size.height, width: size.width, height: size.height)
        case .left: return CGRect(x: b.minX, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .right: return CGRect(x: b.maxX - size.width, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .topLeft: return CGRect(origin: b.origin, size: size)
        case .topRight: return CGRect(x: b.maxX - size.width, y: b.minY, width: size.width, height: size.height)
        case .bottomLeft: return CGRect(x: b.minX, y: b.maxY - size.height, width: size.width, height: size.height)
        case .bottomRight: return CGRect(x: b.maxX - size.width, y: b.maxY - size.height, width: size.width, height: size.height)
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let image = animating ? currentFrame : (isHighlighted ? (highlightedImage ?? self.image?.images?.first ?? self.image) : (self.image?.images?.first ?? self.image)) else { return }
        let rect = context.absoluteRect(imageRect(for: image.size))
        let tint: RGBA? = image.renderingMode == .alwaysTemplate || (image.renderingMode == .automatic && image.isSystemSymbol)
            ? (image.tint ?? tintColor).rgba(for: style) : image.tint?.rgba(for: style)
        Self.paint(image, in: rect, tint: tint, scale: context.scale, style: style, into: &list)
    }

    /// Paints `image` into the absolute `rect`: its drawing, a symbol in `tint` (the label colour
    /// without one), its bytes, or the catalog's variant for the scale (controls draw their
    /// images through this: a slider's end images).
    static func paint(_ image: UIImage, in rect: CGRect, tint: RGBA?, scale: CGFloat, style: UIUserInterfaceStyle, into list: inout DisplayList) {
        if let drawing = image.drawing {
            for command in drawing.commands(in: rect) { list.append(command) }
            return
        }
        if image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: rect, color: tint ?? UIColor.label.rgba(for: style), weight: image.symbolConfiguration?.weight?.css ?? 400, into: &list)
            return
        }
        if image.data != nil {
            var draw = ImageDraw(file: image.name, scale: image.scale, pixelSize: image.pixelSize, rect: rect)
            draw.tint = tint
            list.append(.drawImage(draw))
            return
        }
        let catalog = UIKitScene.shared.assetCatalog
        guard let resource = catalog.image(named: image.name),
              let variant = resource.variants.first(where: { $0.scale == scale }) ?? resource.variants.max(by: { $0.scale < $1.scale }) else { return }
        var draw = ImageDraw(file: variant.file, scale: variant.scale, pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: rect)
        draw.tint = tint
        list.append(.drawImage(draw))
    }
}

// MARK: - Saving to the photo library

/// `Selector` for the completion arguments below is WebFoundation's string-backed one where
/// there is no Objective-C runtime (Responder.swift), Objective-C's on Darwin; one declaration.
/// Adds the image to the user's photo library: in the browser, a download of its PNG through
/// the host's file saver (the closest thing a page has to a camera roll). The completion target
/// and selector are accepted; without a runtime to dispatch a selector, nothing is called.
@preconcurrency @MainActor public func UIImageWriteToSavedPhotosAlbum(_ image: UIImage, _ completionTarget: Any?, _ completionSelector: Selector?, _ contextInfo: UnsafeMutableRawPointer?) {
    guard let data = image.pngData() else { return }
    UIKitScene.shared.fileSaveHandler?(HostFile(data: data, name: "Image.png", mimeType: "image/png"))
}

/// Adds the video to the user's photo library: a download of the file.
@preconcurrency @MainActor public func UISaveVideoAtPathToSavedPhotosAlbum(_ videoPath: String, _ completionTarget: Any?, _ completionSelector: Selector?, _ contextInfo: UnsafeMutableRawPointer?) {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: videoPath)) else { return }
    UIKitScene.shared.fileSaveHandler?(HostFile(data: data, name: URL(fileURLWithPath: videoPath).lastPathComponent, mimeType: "video/mp4"))
}

/// Whether a video at the path could be saved (any file the page can read).
@preconcurrency @MainActor public func UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(_ videoPath: String) -> Bool { FileManager.default.fileExists(atPath: videoPath) }
