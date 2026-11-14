#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
import WebGraphics
#if os(WASI)
import JavaScriptKit

/// Hosts a `HostedScene` in a `<canvas>`: sizing at device pixel ratio, a requestAnimationFrame
/// loop that advances the scene, lays out, paints through the injected JS decoder, forwards
/// pointer events in points, and maintains a DOM overlay of focusable elements and real inputs
/// for accessibility and text entry (decisions 0007 and 0014).
@MainActor
public final class CanvasSceneHost {
    public let scene: any HostedScene
    private let document: JSObject
    private let window: JSObject
    private let container: JSObject
    private let canvas: JSObject
    private let context: JSObject
    private let overlay: JSObject
    /// The platform elements over the canvas (`<video>`, `<iframe>`; `HostedScene.hostElements`).
    private let elementsLayer: JSObject
    private var hostElementViews: [Int: (wrapper: JSObject, element: JSObject, state: HostElement)] = [:]
    /// The live region announcements are spoken from.
    private let announcer: JSObject
    private let bridge: JSObject
    private var width: Double = 0
    private var height: Double = 0
    private var dpr: Double = 1
    private var frameScheduled = false
    private var needsLayout = true
    private var overlayButtons: [Int: JSObject] = [:]
    /// The semantics each overlay element was last written from (writes cross the JS bridge).
    private var overlayState: [Int: SemanticsNode] = [:]
    private var closures: [JSClosure] = []
    private var frameClosure: JSClosure?

    /// The platform look the page asks for (`data-platform="ios"` / `"macos"` on the container
    /// or `?platform=` in the URL, lowercased), if any.
    public let requestedPlatform: String?
    /// Whether the primary pointer is coarse (a finger: phones and tablets, an iPad with a
    /// trackpad included), the cue for a touch-first look.
    public let hasCoarsePointer: Bool
    /// The container's size in points and the device pixel ratio, as of the last resize.
    public var viewportSize: CGSize { CGSize(width: width, height: height) }
    public var pixelScale: CGFloat { dpr }

    /// Creates a host for `scene` in `#app` (or `<body>`): installs the text engine, assets,
    /// image loader, clipboard and appearance, and schedules the first frame.
    public init(scene: any HostedScene) {
        self.scene = scene
        window = JSObject.global
        // The browser's zone is the app's `TimeZone.current` (WebFoundation has no tz database;
        // `Intl` answers for named zones and the browser's language is `Locale.current`).
        if let minutes = JSObject.global.Date.function?.new().getTimezoneOffset?().number {
            TimeZone._hostSecondsFromGMT = -Int(minutes) * 60
        }
        IntlBridge.install()
        // `UserDefaults` suites live in localStorage as JSON (decision 0021).
        if let storage = JSObject.global.localStorage.object {
            UserDefaults._hostStore = (load: { storage.getItem?("swiftuiweb.defaults." + $0).string },
                                       save: { _ = storage.setItem?("swiftuiweb.defaults." + $0, $1) })
            // The app's durable files (`FileManager`'s documents) as base64 under their paths.
            _MemoryFiles._hostStore = (
                list: {
                    var paths: [String] = []
                    let count = Int(storage.length.number ?? 0)
                    for index in 0..<count {
                        if let key = storage.key?(index).string, key.hasPrefix("swiftuiweb.files") { paths.append(String(key.dropFirst("swiftuiweb.files".count))) }
                    }
                    return paths
                },
                load: { storage.getItem?("swiftuiweb.files" + $0).string },
                save: { path, text in
                    if let text { _ = storage.setItem?("swiftuiweb.files" + path, text) } else { _ = storage.removeItem?("swiftuiweb.files" + path) }
                })
        }
        scene.hostDisplayScale = JSObject.global.devicePixelRatio.number.map { CGFloat($0) } ?? 1
        document = window.document.object!
        if window.__swiftuiweb.isUndefined {
            let script = document.createElement!("script").object!
            script.textContent = .string(PainterScript.source)
            _ = document.head.object!.appendChild!(script)
        }
        bridge = window.__swiftuiweb.object!
        container = document.getElementById!("app").object ?? document.body.object!
        // iOS Safari exposes the user's text size through the `-apple-system-body` font keyword:
        // the computed size of a probe span is the body style's point size at the current
        // category (17 at Large). Browsers without the keyword leave the style empty.
        scene.hostDynamicTypeSize = Self.dynamicTypeSize(in: document)
        let containerStyle = container.style.object!
        if (containerStyle.position.string ?? "").isEmpty {
            containerStyle.position = .string("relative")
        }
        // Overlay elements sit wherever their views are, including outside the window on a
        // scrolled page: clipped, or mobile browsers widen the layout viewport to fit them.
        containerStyle.overflow = .string("hidden")
        canvas = document.createElement!("canvas").object!
        canvas.style.object!.display = .string("block")
        canvas.style.object!.touchAction = .string("none")
        _ = container.appendChild!(canvas)
        context = canvas.getContext!("2d").object!
        // Videos and web views sit between the canvas and the accessibility overlay, taking
        // pointer events themselves; the canvas's painted stand-ins stay underneath.
        elementsLayer = document.createElement!("div").object!
        let elementsStyle = elementsLayer.style.object!
        elementsStyle.position = .string("absolute")
        elementsStyle.left = .string("0")
        elementsStyle.top = .string("0")
        elementsStyle.width = .string("100%")
        elementsStyle.height = .string("100%")
        elementsStyle.pointerEvents = .string("none")
        elementsStyle.overflow = .string("hidden")
        _ = container.appendChild!(elementsLayer)
        overlay = document.createElement!("div").object!
        let overlayStyle = overlay.style.object!
        overlayStyle.position = .string("absolute")
        overlayStyle.left = .string("0")
        overlayStyle.top = .string("0")
        overlayStyle.width = .string("100%")
        overlayStyle.height = .string("100%")
        overlayStyle.pointerEvents = .string("none")
        overlayStyle.overflow = .string("hidden")
        _ = overlay.setAttribute!("aria-label", "SwiftUI content")
        _ = container.appendChild!(overlay)
        // Announcements (`UIAccessibility.post(.announcement)`) are spoken from a live region.
        announcer = document.createElement!("div").object!
        _ = announcer.setAttribute!("aria-live", "polite")
        _ = announcer.setAttribute!("role", "status")
        let announcerStyle = announcer.style.object!
        announcerStyle.position = .string("absolute")
        announcerStyle.width = .string("1px")
        announcerStyle.height = .string("1px")
        announcerStyle.overflow = .string("hidden")
        announcerStyle.clip = .string("rect(0 0 0 0)")
        _ = container.appendChild!(announcer)

        requestedPlatform = Self.requestedPlatform(window: window, container: container)
        hasCoarsePointer = window.matchMedia?("(pointer: coarse)").object?.matches.boolean ?? false
        scene.textEngine = Canvas2DTextEngine(context: context, bridge: bridge)
        scene.assetCatalog = Self.assetCatalog(from: window.__swiftuiwebAssets)
        // The app's languages reach `Bundle.main` (EnvironmentOverrides lists them, decision 0021).
        Bundle._hostLocalizations = (languages: scene.assetCatalog.localizations, source: scene.assetCatalog.sourceLanguage)
        loadFonts(scene.assetCatalog, base: window.__swiftuiwebAssets.object?.base.string ?? "")
        scene.onNeedsFrame = { [weak self] in self?.scheduleFrame() }
        // An image the painter had to fetch has arrived: paint the frame again (and let the
        // scene's image views move to their loaded or failed phase).
        let imageLoaded = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scene.imageLoadDidFinish()
                self?.scheduleFrame()
            }
            return .undefined
        }
        scene.imageLoader = CanvasImageLoader(bridge: bridge)
        // The full SF Symbol layout table (`assets/symbol-metrics.txt`, sw-symbols) is fetched
        // on the first symbol outside the built-in set and the scene lays out again.
        let assetBase = window.__swiftuiwebAssets.object?.base.string ?? "assets/"
        // A bundled file read with `Data(contentsOf:)` (a resource URL, `assets/<name>`): fetched
        // synchronously from the bundle's assets, as iOS reads a bundle's files at once (an
        // app's JSON script decoded in an initializer).
        if let made = JSObject.global.Function.function?.new("url", """
            try {
              const x = new XMLHttpRequest(); x.open('GET', url, false);
              x.overrideMimeType('text/plain; charset=x-user-defined'); x.send();
              if (x.status !== 200 && x.status !== 0) return null;
              const t = x.responseText, a = new Uint8Array(t.length);
              for (let i = 0; i < t.length; i++) a[i] = t.charCodeAt(i) & 0xff;
              return a;
            } catch (e) { return null; }
            """), let reader = JSValue.object(made).function {
            _MemoryFiles._hostResource = { key in
                guard let array = reader(assetBase + key.dropFirst(Bundle._resourceBase.count)).object else { return nil }
                return Data(JSTypedArray<UInt8>(unsafelyWrapping: array).withUnsafeBytes { Array($0) })
            }
        }
        scene.onNeedsSymbolMetrics = { [weak self] in
            guard let self else { return }
            let loaded = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    if let text = arguments.first?.string {
                        self?.scene.symbolMetricsDidLoad(SystemSymbolMetricsTable.parse(text))
                        self?.scheduleFrame()
                    }
                }
                return .undefined
            }
            let toText = JSClosure { arguments in
                guard let response = arguments.first?.object, let ok = response.ok.boolean, ok else { return .undefined }
                return response.text?() ?? .undefined
            }
            symbolMetricsClosures = [loaded, toText]
            _ = JSObject.global.fetch?(assetBase + "symbol-metrics.txt").object?.then?(toText).object?.then?(loaded)
        }
        // A recorded drawing becomes PNG data through a canvas of its own (`UIImage.pngData()`).
        let painterBridge = bridge
        scene.imageRasterizer = { list, size, scale in
            let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
            let buffer = JSTypedArray<Double>(encoded.ops)
            let strings = JSObject.global.Array.function!.new()
            for s in encoded.strings { _ = strings.push!(s) }
            guard let url = painterBridge.rasterize!(buffer, strings, scale, size.width, size.height).string,
                  let comma = url.firstIndex(of: ",") else { return nil }
            return Data(base64Encoded: String(url[url.index(after: comma)...]))
        }
        closures.append(imageLoaded)
        _ = bridge.setImageLoadHandler!(imageLoaded)
        // Copies reach the system clipboard when the page may write it.
        if let navigator = JSObject.global.navigator.object, let clipboard = navigator.clipboard.object, clipboard.writeText.function != nil {
            scene.clipboardWriter = { text in _ = clipboard.writeText!(text) }
        }
        // The share sheet, file chooser and downloads (uk-system-sheets).
        scene.shareHandler = { [weak self] request in
            self?.share(items: request.items, subject: request.subject, message: request.message, files: request.files.map { (data: Array($0.data), name: $0.name, mimeType: $0.mimeType) })
        }
        scene.fileOpenHandler = { [weak self] request, completion in
            self?.openFile(extensions: request.extensions, imagesOnly: request.imagesOnly, allowsMultiple: request.allowsMultiple) { files in completion(files) }
        }
        scene.fileSaveHandler = { [weak self] file in self?.download(Array(file.data), name: file.name) }
        // A colour well opens the browser's colour chooser (sw-colorpicker): a colour input kept
        // under the well, opened inside the press's gesture; `input` events feed the well while
        // the chooser is open, `change` ends it. The input has no alpha: the well's stays.
        scene.colorPanelHandler = { [weak self] request in self?.showColorInput(request) ?? false }
        // The system appearance, now and when it changes.
        if let media = window.matchMedia?("(prefers-color-scheme: dark)").object {
            scene.hostColorScheme = (media.matches.boolean ?? false) ? .dark : .light
            let listener = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    self?.scene.hostColorScheme = (arguments.first?.matches.boolean ?? false) ? .dark : .light
                    self?.scheduleFrame()
                }
                return .undefined
            }
            _ = media.addEventListener?("change", listener)
            closures.append(listener)
        }
        // The scene phase: the page's visibility and the window's focus; the URL's fragment at
        // launch and later changes reach `onOpenURL`.
        scene.hostIsVisible = document.visibilityState.string != "hidden"
        scene.hostIsFocused = document.hasFocus.function.map { _ in document.hasFocus!().boolean ?? true } ?? true
        on(document, "visibilitychange") { [weak self] _ in
            guard let self else { return }
            self.scene.hostIsVisible = self.document.visibilityState.string != "hidden"
            self.scheduleFrame()
        }
        on(window, "focus") { [weak self] _ in self?.scene.hostIsFocused = true; self?.scheduleFrame() }
        on(window, "blur") { [weak self] _ in self?.scene.hostIsFocused = false; self?.scheduleFrame() }
        if let location = window.location.object, let href = location.href.string, let hash = location["hash"].string, !hash.isEmpty {
            scene.handleOpenURL(href)
        }
        for event in ["hashchange", "popstate"] {
            on(window, event) { [weak self] _ in
                guard let self, let href = self.window.location.object?.href.string else { return }
                self.scene.handleOpenURL(href)
                self.scheduleFrame()
            }
        }
        // Increased contrast, now and when it changes.
        if let media = window.matchMedia?("(prefers-contrast: more)").object {
            scene.hostIncreasesContrast = media.matches.boolean ?? false
            let listener = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    self?.scene.hostIncreasesContrast = arguments.first?.matches.boolean ?? false
                    self?.scheduleFrame()
                }
                return .undefined
            }
            _ = media.addEventListener?("change", listener)
            closures.append(listener)
        }
        // Reduce motion, now and when it changes.
        if let media = window.matchMedia?("(prefers-reduced-motion: reduce)").object {
            scene.hostReducesMotion = media.matches.boolean ?? false
            let listener = JSClosure { [weak self] arguments in
                MainActor.assumeIsolated {
                    self?.scene.hostReducesMotion = arguments.first?.matches.boolean ?? false
                    self?.scheduleFrame()
                }
                return .undefined
            }
            _ = media.addEventListener?("change", listener)
            closures.append(listener)
        }
        installEventHandlers()
        resize()
        installDebugBridge()
    }

    /// Opens `url` in a new tab.
    public func openURL(_ url: String) {
        _ = window.window.object?.open?(url, "_blank", "noopener")
    }

    /// Shares `items` through Web Share where the browser offers it (a user gesture must be in
    /// flight): a single URL as a link, anything else as text.
    public func share(items: [String], subject: String?) {
        share(items: items, subject: subject, message: nil, files: [])
    }

    /// Shares links and texts, a message, and data as files (Web Share level 2: `files` go
    /// only where `navigator.canShare` accepts them; a title from the subject, the message
    /// before the texts).
    public func share(items: [String], subject: String?, message: String?, files: [(data: [UInt8], name: String, mimeType: String)]) {
        guard let navigator = JSObject.global.navigator.object, navigator.share.function != nil else { return }
        let data = JSObject.global.Object.function!.new()
        var texts: [String] = []
        if let message { texts.append(message) }
        for item in items {
            if data.url.isUndefined, item.hasPrefix("http") { data.url = .string(item) } else { texts.append(item) }
        }
        if !texts.isEmpty { data.text = .string(texts.joined(separator: "\n")) }
        if let subject { data.title = .string(subject) }
        if !files.isEmpty, let fileConstructor = JSObject.global.File.function {
            let list = JSObject.global.Array.function!.new()
            for file in files {
                let bytes = JSTypedArray<UInt8>(file.data)
                let parts = JSObject.global.Array.function!.new()
                _ = parts.push!(bytes.jsValue)
                let options = JSObject.global.Object.function!.new()
                options.type = .string(file.mimeType)
                _ = list.push!(fileConstructor.new(parts, file.name, options))
            }
            data.files = .object(list)
            if let canShare = navigator.canShare.function, !(canShare(this: navigator, data).boolean ?? false) {
                _ = JSObject.global.Reflect.object?.deleteProperty?(data, "files")
            }
        }
        _ = navigator.share!(data)
    }

    /// The platform a page forces with `data-platform` on the container or `?platform=` in its URL.
    static func requestedPlatform(window: JSObject, container: JSObject) -> String? {
        var forced = container.dataset.object?.platform.string
        if forced == nil, let search = window.location.object?.search.string {
            for pair in search.dropFirst().split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0] == "platform" { forced = String(parts[1]) }
            }
        }
        return forced?.lowercased()
    }

    /// The catalog `scripts/assets.py --js` published as `window.__swiftuiwebAssets`, or an empty
    /// one when the page has no manifest script.
    static func assetCatalog(from manifest: JSValue) -> AssetCatalog {
        guard let manifest = manifest.object else { return .empty }
        var images: [String: CatalogImage] = [:]
        if let sets = manifest.images.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let set = sets[dynamicMember: name].object,
                      let variants = set.variants.object else { continue }
                var resource = CatalogImage(name: name, isTemplate: set.template.boolean ?? false, variants: [])
                if let insets = set.capInsets.object {
                    resource.capInsets = EdgeInsets(top: insets.top.number ?? 0, leading: insets.leading.number ?? 0, bottom: insets.bottom.number ?? 0, trailing: insets.trailing.number ?? 0)
                }
                resource.tilesCenter = set.tilesCenter.boolean ?? false
                for v in 0..<Int(variants.length.number ?? 0) {
                    guard let variant = variants[v].object, let file = variant.file.string else { continue }
                    resource.variants.append(ImageVariant(
                        file: file, scale: CGFloat(variant.scale.number ?? 1),
                        pixelWidth: Int((variant.width.number ?? 0).rounded()), pixelHeight: Int((variant.height.number ?? 0).rounded()),
                        idiom: variant.idiom.string ?? "universal", appearance: variant.appearance.string ?? "any", isVector: variant.vector.boolean ?? false))
                }
                images[name] = resource
            }
        }
        var colors: [String: [ColorVariant]] = [:]
        if let sets = manifest.colors.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let set = sets[dynamicMember: name].object,
                      let variants = set.variants.object else { continue }
                var entries: [ColorVariant] = []
                for v in 0..<Int(variants.length.number ?? 0) {
                    guard let variant = variants[v].object else { continue }
                    entries.append(ColorVariant(
                        idiom: variant.idiom.string ?? "universal", appearance: variant.appearance.string ?? "any",
                        colorSpace: variant.colorSpace.string ?? "srgb",
                        red: variant.red.number ?? 0, green: variant.green.number ?? 0, blue: variant.blue.number ?? 0,
                        alpha: variant.alpha.number ?? 1))
                }
                colors[name] = entries
            }
        }
        var fonts: [String: FontResource] = [:]
        if let sets = manifest.fonts.object, let names = JSObject.global.Object.function!.keys!(sets).object {
            for index in 0..<Int(names.length.number ?? 0) {
                guard let name = names[index].string, let entry = sets[dynamicMember: name].object, let file = entry.file.string else { continue }
                fonts[name] = FontResource(postScriptName: entry.postScriptName.string ?? name, family: entry.family.string ?? name, file: file,
                                           unitsPerEm: entry.unitsPerEm.number ?? 1000, ascender: entry.ascender.number ?? 0,
                                           descender: entry.descender.number ?? 0, lineGap: entry.lineGap.number ?? 0,
                                           capHeight: entry.capHeight.number ?? 0, xHeight: entry.xHeight.number ?? 0,
                                           underlinePosition: entry.underlinePosition.number ?? 0, underlineThickness: entry.underlineThickness.number ?? 0)
            }
        }
        var localizations: [String] = []
        if let list = manifest.localizations.object {
            for index in 0..<Int(list.length.number ?? 0) { if let tag = list[index].string { localizations.append(tag) } }
        }
        return AssetCatalog(images: images, colors: colors, fonts: fonts, localizations: localizations, sourceLanguage: manifest.sourceLanguage.string)
    }

    /// Loads the catalog's font files as `FontFace`s under their PostScript and family names,
    /// so Canvas2D measures and draws them; text measured before a face arrived is laid out again.
    private func loadFonts(_ catalog: AssetCatalog, base: String) {
        guard let fontSet = document.fonts.object, let fontFace = JSObject.global.FontFace.function else { return }
        for font in catalog.fonts.values {
            let source = "url(\(base)\(font.file))"
            for name in Set([font.postScriptName, font.family]) {
                let face = fontFace.new(name, source)
                _ = fontSet.add?(face)
                let loaded = JSClosure { [weak self] _ in
                    MainActor.assumeIsolated { self?.textLayoutsNeedMeasuring() }
                    return .undefined
                }
                let failed = JSClosure { _ in
                    _ = JSObject.global.console.object?.error?("SwiftUIWeb: could not load font \(name) from \(font.file)")
                    return .undefined
                }
                _ = face.load?().object?.then?(loaded, failed)
                pendingFontLoads += 2  // the closures stay alive until the promise settles
                fontLoadClosures += [loaded, failed]
            }
        }
    }

    private var pendingFontLoads = 0
    private var fontLoadClosures: [JSClosure] = []

    private func textLayoutsNeedMeasuring() {
        (scene.textEngine as? Canvas2DTextEngine)?.forgetMeasurements()
        scene.fontsDidLoad()
        scheduleFrame()
    }

    /// The scene's content changed outside its own invalidation (a new root was mounted):
    /// lays out again on the next frame.
    public func invalidate() {
        needsLayout = true
        scheduleFrame()
    }

    private func on(_ target: JSObject, _ event: String, _ handler: @escaping @MainActor (JSObject) -> Void) {
        let closure = JSClosure { args in
            MainActor.assumeIsolated { if let e = args.first?.object { handler(e) } }
            return .undefined
        }
        closures.append(closure)
        _ = target.addEventListener!(event, closure)
    }

    private func installEventHandlers() {
        on(canvas, "pointerdown") { [weak self] e in
            guard let self else { return }
            if (e.button.number ?? 0) == 2 {
                self.scene.secondaryPointerDown(at: self.point(of: e))
                self.scheduleFrame()
                return
            }
            _ = self.canvas.setPointerCapture?(e.pointerId)
            if self.pointerType(of: e) == .touch, self.touchDown(e) { return }
            self.scene.pointerModifiersChanged(self.modifiers(of: e))
            self.scene.pointerDown(at: self.point(of: e), type: self.pointerType(of: e), time: self.seconds(of: e))
            // A press on a drag source makes the canvas draggable for this press: the browser
            // then starts a system drag when the pointer moves (sw-dragdrop-os).
            self.canvas.draggable = .boolean(self.pointerType(of: e) == .mouse && self.scene.hasDragSource(at: self.point(of: e)))
            self.scheduleFrame()
        }
        // The browser's default for a mouse-down on the canvas would move the page's focus to
        // the body, blurring the overlay element of the focused view and with it the scene's
        // keyboard focus — a click on a button beside a focusable board would take the board's
        // arrow keys away. Focus stays where it is; the scene moves it itself when a press
        // lands on a focusable view or a text field. The default stays when the press began a
        // system drag (`draggable`), which the browser starts from this same event.
        on(canvas, "mousedown") { [weak self] e in
            guard let self, self.canvas.draggable.boolean != true else { return }
            _ = e.preventDefault?()
        }
        // Context menus are the scene's; the browser's stays closed.
        on(canvas, "contextmenu") { e in _ = e.preventDefault!() }
        on(canvas, "pointermove") { [weak self] e in
            guard let self else { return }
            if self.pointerType(of: e) == .touch, self.touchMoved(e) { return }
            self.scene.pointerMoved(to: self.point(of: e), time: self.seconds(of: e))
            self.applyPointerStyle()
            if self.scene.needsFrame { self.scheduleFrame() }
        }
        on(canvas, "pointerleave") { [weak self] e in
            guard let self else { return }
            self.scene.pointerLeft()
            self.applyPointerStyle()
            if self.scene.needsFrame { self.scheduleFrame() }
        }
        on(canvas, "pointerup") { [weak self] e in
            guard let self, (e.button.number ?? 0) != 2 else { return }
            self.canvas.draggable = .boolean(false)
            if self.systemDrag { return }
            if self.pointerType(of: e) == .touch, self.touchUp(e) { return }
            self.scene.pointerUp(at: self.point(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "pointercancel") { [weak self] e in
            guard let self else { return }
            // The browser cancels the pointer when its system drag takes over: the scene's drag
            // goes on through the drag events.
            if self.systemDrag { return }
            if self.pointerType(of: e) == .touch, self.touchUp(e) { return }
            self.scene.pointerUp(at: CGPoint(x: -1, y: -1), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        installDragHandlers()
        // Safari delivers trackpad pinches as gesture events (scale and rotation in degrees).
        on(canvas, "gesturestart") { [weak self] e in
            guard let self else { return }
            _ = e.preventDefault?()
            self.endWheelPinch()
            self.gesturePinch = true
            self.scene.pinch(.began, scale: 1, rotation: 0, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "gesturechange") { [weak self] e in
            guard let self, self.gesturePinch else { return }
            _ = e.preventDefault?()
            self.scene.pinch(.changed, scale: e.scale.number ?? 1, rotation: (e.rotation.number ?? 0) * .pi / 180, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        on(canvas, "gestureend") { [weak self] e in
            guard let self, self.gesturePinch else { return }
            _ = e.preventDefault?()
            self.gesturePinch = false
            self.scene.pinch(.ended, scale: e.scale.number ?? 1, rotation: (e.rotation.number ?? 0) * .pi / 180, at: self.clientPoint(of: e), time: self.seconds(of: e))
            self.scheduleFrame()
        }
        // Wheel deltas are consumed here (non-passive, so the page does not scroll too): pixel
        // deltas map to points, lines to 16 pt, pages to the viewport. A wheel with the control
        // key is a trackpad pinch (Chromium and Firefox): the scale compounds by e^(-deltaY/100)
        // and the pinch ends a fifth of a second after its last event.
        let wheel = JSClosure { [weak self] args in
            MainActor.assumeIsolated {
                guard let self, let e = args.first?.object else { return }
                _ = e.preventDefault!()
                if e.ctrlKey.boolean == true, !self.gesturePinch {
                    self.wheelPinch(e)
                    return
                }
                let mode = e.deltaMode.number ?? 0
                let factor = mode == 1 ? 16.0 : mode == 2 ? self.height : 1.0
                let delta = CGSize(width: (e.deltaX.number ?? 0) * factor, height: (e.deltaY.number ?? 0) * factor)
                self.scene.scrollWheel(by: delta, at: self.point(of: e), time: self.seconds(of: e))
                if self.scene.needsFrame { self.scheduleFrame() }
            }
            return .undefined
        }
        closures.append(wheel)
        let wheelOptions = JSObject.global.Object.function!.new()
        wheelOptions.passive = .boolean(false)
        _ = canvas.addEventListener!("wheel", wheel, wheelOptions)
        on(window, "resize") { [weak self] _ in self?.resize() }
        // Keys go to the scene: the focused element's handlers,
        // the open menu, keyboard shortcuts, Escape. A text field's input keeps its own keys
        // except Escape.
        on(window, "keydown") { [weak self] e in
            guard let self, let event = self.keyEvent(of: e) else { return }
            if self.scene.keyDown(event) {
                _ = e.preventDefault?()
                self.scheduleFrame()
            }
        }
        on(window, "keyup") { [weak self] e in
            guard let self, let event = self.keyEvent(of: e) else { return }
            if self.scene.keyUp(event) {
                _ = e.preventDefault?()
                self.scheduleFrame()
            }
        }
        if let resizeObserver = window.ResizeObserver.function {
            let closure = JSClosure { [weak self] _ in
                MainActor.assumeIsolated { self?.resize() }
                return .undefined
            }
            closures.append(closure)
            let observer = resizeObserver.new(closure)
            _ = observer.observe!(container)
        }
    }

    private func point(of event: JSObject) -> CGPoint {
        CGPoint(x: event.offsetX.number ?? 0, y: event.offsetY.number ?? 0)
    }

    private func modifiers(of event: JSObject) -> EventModifiers {
        var modifiers: EventModifiers = []
        if event.shiftKey.boolean == true { modifiers.insert(.shift) }
        if event.ctrlKey.boolean == true { modifiers.insert(.control) }
        if event.altKey.boolean == true { modifiers.insert(.option) }
        if event.metaKey.boolean == true { modifiers.insert(.command) }
        return modifiers
    }

    /// The scene's key event for a DOM keyboard event; nil for keys the scene has no equivalent
    /// for and for keys a text field's input keeps (all but Escape).
    private func keyEvent(of e: JSObject) -> KeyEvent? {
        guard let domKey = e.key.string, let key = KeyEquivalent(domKey: domKey) else { return nil }
        if let target = e.target.object, target.tagName.string == "INPUT", target.type.string != "range", key != .escape { return nil }
        return KeyEvent(key: key, characters: domKey.count == 1 ? domKey : "", modifiers: modifiers(of: e), isRepeat: e["repeat"].boolean == true, time: seconds(of: e))
    }

    /// The event's point from its client coordinates (gesture events carry no offset).
    private func clientPoint(of event: JSObject) -> CGPoint {
        let rect = canvas.getBoundingClientRect!().object!
        return CGPoint(x: (event.clientX.number ?? 0) - (rect.left.number ?? 0), y: (event.clientY.number ?? 0) - (rect.top.number ?? 0))
    }

    // MARK: Pinches

    /// A Safari gesture-event pinch in flight (control-wheel events are ignored meanwhile).
    private var gesturePinch = false
    /// The cumulative scale of a control-wheel pinch, nil when none is in flight.
    private var wheelPinchScale: Double?
    private var wheelPinchPoint = CGPoint.zero
    private var wheelPinchGeneration = 0
    private var wheelPinchClosure: JSClosure?

    private func wheelPinch(_ e: JSObject) {
        let point = point(of: e)
        let time = seconds(of: e)
        if wheelPinchScale == nil {
            wheelPinchScale = 1
            wheelPinchPoint = point
            scene.pinch(.began, scale: 1, rotation: 0, at: point, time: time)
        }
        let scale = (wheelPinchScale ?? 1) * _exp(-(e.deltaY.number ?? 0) / 100)
        wheelPinchScale = scale
        scene.pinch(.changed, scale: scale, rotation: 0, at: wheelPinchPoint, time: time)
        scheduleFrame()
        wheelPinchGeneration += 1
        let generation = wheelPinchGeneration
        let closure = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wheelPinchGeneration == generation else { return }
                self.endWheelPinch()
            }
            return .undefined
        }
        wheelPinchClosure = closure
        _ = window.setTimeout!(closure, 200)
    }

    private func endWheelPinch() {
        guard let scale = wheelPinchScale else { return }
        wheelPinchScale = nil
        wheelPinchGeneration += 1
        scene.pinch(.ended, scale: scale, rotation: 0, at: wheelPinchPoint, time: now)
        scheduleFrame()
    }

    /// Touches by pointer id; two of them pinch (the press under the first is cancelled, and
    /// the touch that remains after the pinch is ignored until it lifts).
    private var touches: [Int: CGPoint] = [:]
    private var touchOrder: [Int] = []
    private var touchPinch: (distance: Double, angle: Double)?
    private var touchPinchLast: (scale: CGFloat, rotation: Double) = (1, 0)
    private var touchesAfterPinch = false

    private func touchGeometry() -> (centre: CGPoint, distance: Double, angle: Double)? {
        guard touchOrder.count >= 2, let a = touches[touchOrder[0]], let b = touches[touchOrder[1]] else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        return (CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), (dx * dx + dy * dy).squareRoot(), _atan2(dy, dx))
    }

    /// Returns whether the touch was taken by a pinch (or ignored after one).
    private func touchDown(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        touches[id] = point(of: e)
        touchOrder.append(id)
        if touchesAfterPinch || touchPinch != nil { return true }
        guard touchOrder.count == 2, let geometry = touchGeometry() else { return false }
        scene.pointerUp(at: CGPoint(x: -1, y: -1), time: seconds(of: e))
        touchPinch = (max(geometry.distance, 1), geometry.angle)
        touchPinchLast = (1, 0)
        scene.pinch(.began, scale: 1, rotation: 0, at: geometry.centre, time: seconds(of: e))
        scheduleFrame()
        return true
    }

    private func touchMoved(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        guard touches[id] != nil else { return false }
        touches[id] = point(of: e)
        if touchesAfterPinch { return true }
        guard let start = touchPinch, let geometry = touchGeometry() else { return false }
        var rotation = geometry.angle - start.angle
        while rotation > .pi { rotation -= 2 * .pi }
        while rotation < -.pi { rotation += 2 * .pi }
        touchPinchLast = (geometry.distance / start.distance, rotation)
        scene.pinch(.changed, scale: touchPinchLast.scale, rotation: touchPinchLast.rotation, at: geometry.centre, time: seconds(of: e))
        scheduleFrame()
        return true
    }

    private func touchUp(_ e: JSObject) -> Bool {
        let id = Int(e.pointerId.number ?? 0)
        guard touches[id] != nil else { return false }
        let centre = touchGeometry()?.centre ?? point(of: e)
        touches[id] = nil
        touchOrder.removeAll { $0 == id }
        if touchPinch != nil {
            touchPinch = nil
            touchesAfterPinch = !touches.isEmpty
            scene.pinch(.ended, scale: touchPinchLast.scale, rotation: touchPinchLast.rotation, at: centre, time: seconds(of: e))
            scheduleFrame()
            return true
        }
        if touchesAfterPinch {
            if touches.isEmpty { touchesAfterPinch = false }
            return true
        }
        return false
    }

    private func pointerType(of event: JSObject) -> PointerType {
        switch event.pointerType.string {
        case "touch": return .touch
        case "pen": return .pen
        default: return .mouse
        }
    }

    /// The event's timestamp in seconds (same clock as `performance.now()`).
    private func seconds(of event: JSObject) -> Double {
        (event.timeStamp.number ?? 0) / 1000
    }

    private var now: Double { (window.performance.object?.now?().number ?? 0) / 1000 }

    private func resize() {
        let newWidth = container.clientWidth.number ?? 0
        let newHeight = container.clientHeight.number ?? 0
        let newDPR = window.devicePixelRatio.number ?? 1
        guard newWidth != width || newHeight != height || newDPR != dpr else { return }
        width = newWidth
        height = newHeight
        dpr = newDPR
        canvas.width = .number((width * dpr).rounded())
        canvas.height = .number((height * dpr).rounded())
        canvas.style.object!.width = .string("\(width)px")
        canvas.style.object!.height = .string("\(height)px")
        applySafeArea()
        needsLayout = true
        scheduleFrame()
    }

    /// The device's safe area for the app (`HostedScene.hostSafeAreaInsets`): the container's
    /// `data-safe-area` or the page's `?safeArea=` ("top,leading,bottom,trailing" in points, as
    /// a drawn phone around the app sets it), else the browser's own `env(safe-area-inset-*)`
    /// (a phone's browser on a page with `viewport-fit=cover`; zero on a desktop, which leaves
    /// the app as it was). `env` as the value asks for the browser's explicitly. Read again
    /// whenever the page resizes (a phone turning).
    private func applySafeArea() {
        var text = container.dataset.object?.safeArea.string
        if text == nil, let search = window.location.object?.search.string {
            for pair in search.dropFirst().split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2, parts[0] == "safeArea" { text = String(parts[1]).replacingOccurrences(of: "%2C", with: ",") }
            }
        }
        let insets: [CGFloat]
        if let text, text != "env" {
            insets = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) } }
        } else {
            insets = browserSafeArea()
        }
        if insets.count == 4, insets != scene.hostSafeAreaInsets { scene.hostSafeAreaInsets = insets }
    }

    /// The browser's `env(safe-area-inset-*)` in CSS pixels (points), top, leading, bottom,
    /// trailing, measured on a hidden element's padding.
    private func browserSafeArea() -> [CGFloat] {
        guard let probe = document.createElement!("div").object, let style = probe.style.object,
              let body = document.body.object else { return [] }
        style.cssText = .string("position:fixed;visibility:hidden;pointer-events:none;left:0;top:0;width:0;height:0;"
            + "padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)")
        _ = body.appendChild!(probe)
        defer { _ = probe.remove!() }
        guard let computed = window.getComputedStyle!(probe).object else { return [] }
        func points(_ property: String) -> CGFloat {
            let text = computed[property].string ?? "0"
            return CGFloat(Double(text.replacingOccurrences(of: "px", with: "")) ?? 0)
        }
        let leftToRight = (computed.direction.string ?? "ltr") != "rtl"
        let left = points("paddingLeft"), right = points("paddingRight")
        return [points("paddingTop"), leftToRight ? left : right, points("paddingBottom"), leftToRight ? right : left]
    }

    /// Requests one animation frame; several invalidations coalesce into it.
    /// The cursor over the canvas follows the hovered `pointerStyle`.
    private var appliedCursor = ""
    private func applyPointerStyle() {
        let cursor = scene.pointerCursor ?? ""
        guard cursor != appliedCursor else { return }
        appliedCursor = cursor
        canvas.style.cursor = .string(cursor)
    }

    public func scheduleFrame() {
        guard !frameScheduled else { return }
        frameScheduled = true
        if frameClosure == nil {
            frameClosure = JSClosure { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
                return .undefined
            }
        }
        // A hidden document gets no animation frames (a WKWebView window the window server has
        // not shown yet, a background tab): the first frames come from a timer instead so the
        // page has content when it appears; after that only visible documents paint.
        if frameCount == 0, document.hidden.boolean == true {
            _ = window.setTimeout!(frameClosure!, 16)
        } else {
            _ = window.requestAnimationFrame!(frameClosure!)
        }
    }

    private func tick() {
        frameScheduled = false
        let time = now
        // The gap between consecutive animation frames while frames run back to back: a gap
        // over one vsync with a short frame means the time went to the compositor, not here.
        frameGapMillis = lastFrameTime.map { (time - $0) * 1000 } ?? 0
        let elapsed = lastFrameTime.map { min(0.1, time - $0) } ?? 0
        advanceScriptedDrag(time: time)
        // Animations the last frame began start from when it was painted: the clock is about
        // to move by the whole gap, and the work before the paint is not part of the motion.
        if let painted = lastPaintTime, lastFrameTime != nil { scene.commitAnimations(lateness: max(0, elapsed - (time - painted))) }
        lastPaintTime = nil
        let animating = scene.advanceFrame(elapsed: elapsed)
        lastFrameTime = time
        guard needsLayout || scene.needsFrame else {
            // An animation in a phase that changes nothing on screen (the indicator hold) still
            // needs the clock to advance.
            if animating || scriptedDrag != nil { scheduleFrame() } else { lastFrameTime = nil }
            return
        }
        needsLayout = false
        mark("layout")
        scene.layout(in: CGSize(width: width, height: height))
        let laidOut = now
        mark("render")
        let list = scene.render(scale: dpr)
        let rendered = now
        mark("paint")
        let jsPaintMillis = paint(list)
        let painted = now
        lastPaintTime = painted
        mark("overlay")
        overlayStart = painted
        updateOverlay()
        updateHostElements()
        mark(nil)
        lastDisplayList = list
        frameCount += 1
        frameMillis = (now - time) * 1000
        framePhases = [(laidOut - time) * 1000, (rendered - laidOut) * 1000, (painted - rendered) * 1000 - jsPaintMillis, jsPaintMillis, semanticsMillis, (now - painted) * 1000 - semanticsMillis]
        // The first frame is on screen: a loading screen in the page can go (`index.html`
        // listens for `swiftuiwebready` on the container; it bubbles to the document).
        if frameCount == 1, let event = window.CustomEvent.function {
            let options = JSObject.global.Object.function!.new()
            options.bubbles = .boolean(true)
            _ = container.dispatchEvent?(event.new("swiftuiwebready", options))
        }
        // A preference action, observation, scroll animation or an animation the layout just
        // started may need another frame.
        if animating || scene.isAnimating || scene.needsFrame || scriptedDrag != nil { scheduleFrame() } else { lastFrameTime = nil }
    }

    /// Time of the previous frame while frames run back to back (scroll animations).
    private var lastFrameTime: Double?
    /// When the previous frame finished painting, for the animations it began.
    private var lastPaintTime: Double?

    /// A finger drag the debug bridge scripted (`__swiftuiwebDebug.drag`): one touch moving
    /// from `start` by `delta` over `duration` seconds, one step per frame, released at the
    /// end so momentum follows. Measurements on a phone drive it where no input tool reaches.
    private var scriptedDrag: (start: CGPoint, delta: CGPoint, startTime: Double, duration: Double, began: Bool)?
    private func advanceScriptedDrag(time: Double) {
        guard var drag = scriptedDrag else { return }
        if !drag.began {
            drag.startTime = time
            drag.began = true
            scriptedDrag = drag
            scene.pointerDown(at: drag.start, type: .touch, time: time)
            return
        }
        let progress = min(1, (time - drag.startTime) / max(0.001, drag.duration))
        let point = CGPoint(x: drag.start.x + drag.delta.x * progress, y: drag.start.y + drag.delta.y * progress)
        // Stamped with when the finger was there: a late frame must not make a finger that
        // lifted on time look as if it had stopped first (its speed at the lift is measured).
        let eventTime = min(time, drag.startTime + drag.duration)
        scene.pointerMoved(to: point, time: eventTime)
        if progress >= 1 {
            scene.pointerUp(at: point, time: eventTime)
            scriptedDrag = nil
        }
    }

    /// Layout + paint time of the most recent frame in milliseconds (debug bridge), and its
    /// split into layout, display list, encode (the typed array and the bridge), the painter's
    /// Canvas2D loop, semantics walk and overlay DOM milliseconds; the gap since the previous
    /// animation frame.
    public private(set) var frameMillis: Double = 0
    public private(set) var framePhases: [Double] = [0, 0, 0, 0, 0, 0]
    public private(set) var frameGapMillis: Double = 0
    private var overlayStart: Double = 0
    private var semanticsMillis: Double = 0

    /// A `performance.mark` per phase when the page URL carries `perf`: the browser's timeline
    /// then shows where a frame went (Safari's Web Inspector over USB on a phone). `nil` ends
    /// the open measure. Marks accumulate in the performance buffer, hence the opt-in.
    /// `?perf` (or any query naming it) turns the marks on. The scan is by UTF-8 bytes, since
    /// `String.contains(String)` would link _StringProcessing and the Regex parser (decision 0006).
    private lazy var marksEnabled: Bool = {
        let query = (window.location.object?.search.string ?? "").utf8
        return query.indices.contains { query[$0...].starts(with: "perf".utf8) }
    }()
    private var openMark: String?
    private func mark(_ phase: String?) {
        guard marksEnabled, let performance = window.performance.object, let measure = performance.measure.function, let mark = performance.mark.function else { return }
        if let openMark { _ = measure(this: performance, "swiftuiweb." + openMark, "swiftuiweb." + openMark + ".start") }
        if let phase { _ = mark(this: performance, "swiftuiweb." + phase + ".start") }
        openMark = phase
    }

    /// The most recently painted display list and the number of frames painted (debug bridge).
    private var symbolMetricsClosures: [JSClosure] = []
    private var colorInput: JSObject?
    private var colorInputRequest: ColorPanelRequest?

    /// Shows the browser's colour chooser for a well (`HostedScene.colorPanelHandler`).
    private func showColorInput(_ request: ColorPanelRequest) -> Bool {
        let input: JSObject
        if let existing = colorInput {
            input = existing
        } else {
            guard let created = document.createElement!("input").object else { return false }
            input = created
            _ = input.setAttribute!("type", "color")
            _ = input.setAttribute!("aria-hidden", "true")
            _ = input.setAttribute!("tabindex", "-1")
            let style = input.style.object!
            style.position = .string("absolute")
            style.opacity = .string("0")
            style.pointerEvents = .string("none")
            style.width = .string("1px")
            style.height = .string("1px")
            style.border = .string("0")
            style.padding = .string("0")
            on(input, "input") { [weak self] e in
                guard let self, let request = self.colorInputRequest, let hex = e.target.object?.value.string else { return }
                self.scene.colorPanel(request.identifier, didPick: Self.color(fromHex: hex, alpha: request.color.alpha))
                self.scheduleFrame()
            }
            on(input, "change") { [weak self] e in
                guard let self, let request = self.colorInputRequest else { return }
                if let hex = e.target.object?.value.string { self.scene.colorPanel(request.identifier, didPick: Self.color(fromHex: hex, alpha: request.color.alpha)) }
                self.scene.colorPanelDidClose(request.identifier)
                self.colorInputRequest = nil
                self.scheduleFrame()
            }
            _ = overlay.appendChild!(input)
            colorInput = input
        }
        if let previous = colorInputRequest, previous.identifier != request.identifier { scene.colorPanelDidClose(previous.identifier) }
        colorInputRequest = request
        let style = input.style.object!
        style.left = .string("\(request.anchor.minX)px")
        style.top = .string("\(request.anchor.maxY)px")
        input.value = .string(Self.hex(request.color))
        if input.showPicker.function != nil {
            _ = input.showPicker!()
        } else {
            _ = input.click!()
        }
        return true
    }

    private var fileInput: JSObject?
    private var fileClosures: [JSClosure] = []

    /// Opens the browser's file picker (a file input clicked inside the press) for the
    /// extensions and reads the chosen file's bytes (sw-windows: a document group's Open…).
    public func openFile(extensions: [String], completion: @escaping @MainActor (Data, String, URL?) -> Void) {
        openFile(extensions: extensions, imagesOnly: false, allowsMultiple: false) { files in
            if let file = files.first { completion(file.data, file.name, file.url) }
        }
    }

    /// The file picker for several files, or images only (`accept="image/*"`, which a phone
    /// offers from its photo library), each read into a `HostFile` with the browser's type.
    public func openFile(extensions: [String], imagesOnly: Bool, allowsMultiple: Bool, completion: @escaping @MainActor ([HostFile]) -> Void) {
        guard let input = fileInput ?? document.createElement!("input").object else { return }
        if fileInput == nil {
            _ = input.setAttribute!("type", "file")
            let style = input.style.object!
            style.position = .string("absolute"); style.opacity = .string("0"); style.pointerEvents = .string("none"); style.width = .string("1px"); style.height = .string("1px")
            _ = overlay.appendChild!(input)
            fileInput = input
        }
        input.accept = .string(imagesOnly ? "image/*" : extensions.map { "." + $0 }.joined(separator: ","))
        input.multiple = .boolean(allowsMultiple)
        input.value = .string("")
        let onChange = JSClosure { [weak self] _ in
            guard let self, let list = input.files.object else { return .undefined }
            let count = Int(list.length.number ?? 0)
            guard count > 0 else { return .undefined }
            nonisolated(unsafe) var files: [HostFile?] = Array(repeating: nil, count: count)
            nonisolated(unsafe) var remaining = count
            for index in 0..<count {
                guard let file = list[index].object, let name = file.name.string else { remaining -= 1; continue }
                let mimeType = file.type.string ?? "application/octet-stream"
                let onBuffer = JSClosure { arguments in
                    MainActor.assumeIsolated {
                        if let buffer = arguments.first?.object {
                            let bytes = JSTypedArray<UInt8>(unsafelyWrapping: JSObject.global.Uint8Array.function!.new(buffer))
                            files[index] = HostFile(data: Data(bytes.withUnsafeBytes { Array($0) }), name: name, mimeType: mimeType)
                        }
                        remaining -= 1
                        if remaining == 0 {
                            completion(files.compactMap { $0 })
                            self.scheduleFrame()
                        }
                    }
                    return .undefined
                }
                self.fileClosures.append(onBuffer)
                _ = file.arrayBuffer?().object?.then?(onBuffer)
            }
            return .undefined
        }
        fileClosures = [onChange]
        input.onchange = .object(onChange)
        _ = input.click!()
    }

    // MARK: Drags across the app boundary (sw-dragdrop-os)

    /// Whether the browser carries the scene's drag (its pointer events stopped at `dragstart`).
    private var systemDrag = false
    private var dragImage: JSObject?
    private var dragClosures: [JSClosure] = []

    /// The scene's drag becomes the browser's: `dragstart` fills the `DataTransfer` from the
    /// scene's items (text under its MIME type, bytes as base64, files as a `DownloadURL`) and
    /// sets the lifted preview as the drag image; `dragover` and `drop` carry both the scene's
    /// own drag and drags from other pages and apps (their text at once, files read as bytes
    /// before the drop is delivered); `dragend` tells the scene how its drag ended.
    private func installDragHandlers() {
        on(canvas, "dragstart") { [weak self] e in
            guard let self else { return }
            let items = self.scene.beginExternalDrag(at: self.point(of: e))
            guard !items.isEmpty, let transfer = e.dataTransfer.object else {
                _ = e.preventDefault!()
                return
            }
            self.systemDrag = true
            transfer.effectAllowed = .string("copyMove")
            for item in items {
                if let text = item.text {
                    _ = transfer.setData!(item.type, text)
                } else if let data = item.data {
                    _ = transfer.setData!(item.type, Self.base64(Array(data)))
                }
                if let name = item.fileName, let data = item.data, let blobConstructor = JSObject.global.Blob.function, let urlClass = JSObject.global.URL.object {
                    let parts = JSObject.global.Array.function!.new()
                    _ = parts.push!(JSTypedArray<UInt8>(Array(data)).jsValue)
                    let blob = blobConstructor.new(parts)
                    if let url = urlClass.createObjectURL?(blob).string {
                        _ = transfer.setData!("DownloadURL", "\(item.type):\(name):\(url)")
                    }
                }
            }
            if let preview = self.scene.externalDragPreview(), let image = self.document.createElement!("canvas").object {
                let scale = self.dpr, width = Double(preview.size.width), height = Double(preview.size.height)
                image.width = .number(max(1, (width * scale).rounded()))
                image.height = .number(max(1, (height * scale).rounded()))
                let style = image.style.object!
                style.position = .string("absolute"); style.top = .string("-10000px"); style.left = .string("-10000px")
                style.width = .string("\(width)px"); style.height = .string("\(height)px")
                _ = self.overlay.appendChild!(image)
                if let context = image.getContext!("2d").object {
                    let encoded = DisplayListEncoder.encode(preview.list, font: DisplayListEncoder.cssFont)
                    let strings = JSObject.global.Array.function!.new()
                    for string in encoded.strings { _ = strings.push!(string) }
                    _ = self.bridge.paint!(context, JSTypedArray<Double>(encoded.ops), strings, scale, width, height, JSObject.global.Array.function!.new())
                }
                _ = transfer.setDragImage?(image, Double(preview.grab.x), Double(preview.grab.y))
                self.dragImage = image
            }
            self.scheduleFrame()
        }
        on(canvas, "dragenter") { e in _ = e.preventDefault!() }
        on(canvas, "dragover") { [weak self] e in
            guard let self, let transfer = e.dataTransfer.object else { return }
            let accepted = self.scene.externalDragUpdated(types: Self.types(of: transfer), at: self.point(of: e))
            if accepted {
                _ = e.preventDefault!()
                transfer.dropEffect = .string("copy")
            }
            self.scheduleFrame()
        }
        on(canvas, "dragleave") { [weak self] e in
            guard let self else { return }
            // Leaving for an element inside the canvas's box is not leaving.
            if let related = e.relatedTarget.object, related.isSameNode?(self.canvas).boolean == true { return }
            self.scene.externalDragExited()
            self.scheduleFrame()
        }
        on(canvas, "drop") { [weak self] e in
            guard let self, let transfer = e.dataTransfer.object else { return }
            _ = e.preventDefault!()
            self.canvas.draggable = .boolean(false)
            let point = self.point(of: e)
            var items: [ExternalDragItem] = []
            for type in Self.types(of: transfer) where type != "Files" {
                let text = transfer.getData!(type).string ?? ""
                items.append(ExternalDragItem(type: type, text: text))
            }
            let files = transfer.files.object
            let count = Int(files?.length.number ?? 0)
            guard count > 0 else {
                _ = self.scene.externalDrop(items: items, at: point)
                self.scheduleFrame()
                return
            }
            // Files arrive as bytes: every one is read before the drop is delivered.
            var pending = count
            var fileItems = Array(repeating: ExternalDragItem(type: "application/octet-stream"), count: count)
            for index in 0..<count {
                guard let file = files?[index].object else { pending -= 1; continue }
                let name = file.name.string ?? "file"
                let type = file.type.string.flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"
                let onBuffer = JSClosure { [weak self] arguments in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let buffer = arguments.first?.object {
                            let bytes = JSTypedArray<UInt8>(unsafelyWrapping: JSObject.global.Uint8Array.function!.new(buffer))
                            fileItems[index] = ExternalDragItem(type: type, text: nil, data: Data(bytes.withUnsafeBytes { Array($0) }), fileName: name)
                        }
                        pending -= 1
                        if pending == 0 {
                            _ = self.scene.externalDrop(items: items + fileItems, at: point)
                            self.scheduleFrame()
                        }
                    }
                    return .undefined
                }
                self.dragClosures.append(onBuffer)
                _ = file.arrayBuffer?().object?.then?(onBuffer)
            }
        }
        on(canvas, "dragend") { [weak self] e in
            guard let self else { return }
            let dropped = e.dataTransfer.object?.dropEffect.string.map { $0 != "none" } ?? false
            self.systemDrag = false
            self.canvas.draggable = .boolean(false)
            if let image = self.dragImage { _ = self.overlay.removeChild!(image); self.dragImage = nil }
            self.dragClosures.removeAll()
            self.scene.externalDragEnded(dropped: dropped)
            self.scheduleFrame()
        }
    }

    /// The types a `DataTransfer` carries (`Files` for files).
    private static func types(of transfer: JSObject) -> [String] {
        guard let list = transfer.types.object else { return [] }
        return (0..<Int(list.length.number ?? 0)).compactMap { list[$0].string }
    }

    private static func base64(_ bytes: [UInt8]) -> String {
        let table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var out = ""
        var index = 0
        while index < bytes.count {
            let b0 = bytes[index], b1 = index + 1 < bytes.count ? bytes[index + 1] : 0, b2 = index + 2 < bytes.count ? bytes[index + 2] : 0
            out.append(table[Int(b0 >> 2)])
            out.append(table[Int((b0 & 3) << 4 | b1 >> 4)])
            out.append(index + 1 < bytes.count ? table[Int((b1 & 15) << 2 | b2 >> 6)] : "=")
            out.append(index + 2 < bytes.count ? table[Int(b2 & 63)] : "=")
            index += 3
        }
        return out
    }

    /// Hands the browser a file to save: a Blob download named `name` (sw-windows: Save).
    public func download(_ bytes: [UInt8], name: String) {
        guard let blobConstructor = JSObject.global.Blob.function, let urlClass = JSObject.global.URL.object else { return }
        let parts = JSObject.global.Array.function!.new()
        _ = parts.push!(JSTypedArray<UInt8>(bytes).jsValue)
        let blob = blobConstructor.new(parts)
        guard let url = urlClass.createObjectURL?(blob).string, let anchor = document.createElement!("a").object else { return }
        anchor.href = .string(url)
        anchor.download = .string(name)
        _ = overlay.appendChild!(anchor)
        _ = anchor.click!()
        _ = overlay.removeChild!(anchor)
        _ = urlClass.revokeObjectURL?(url)
    }

    /// `#rrggbb` for a colour input (no alpha).
    private static func hex(_ color: RGBA) -> String {
        func channel(_ value: Double) -> String {
            let byte = Int((min(max(value, 0), 1) * 255).rounded())
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }
        return "#" + channel(color.red) + channel(color.green) + channel(color.blue)
    }

    private static func color(fromHex hex: String, alpha: Double) -> RGBA {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        return RGBA(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: alpha)
    }
    public private(set) var lastDisplayList = DisplayList()
    public private(set) var frameCount = 0

    /// Encodes and paints the list; returns the painter's own Canvas2D loop time in
    /// milliseconds (the rest of the phase is the encode and the bridge).
    @discardableResult
    private func paint(_ list: DisplayList) -> Double {
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        lastOpCount = list.commands.count
        let buffer = JSTypedArray<Double>(encoded.ops)
        let strings = JSObject.global.Array.function!.new()
        for s in encoded.strings { _ = strings.push!(s) }
        let bitmaps = JSObject.global.Array.function!.new()
        for bitmap in encoded.bitmaps {
            let object = JSObject.global.Object.function!.new()
            object.width = .number(Double(bitmap.width))
            object.height = .number(Double(bitmap.height))
            object.pixels = .object(JSObject.global.Uint8ClampedArray.function!.new(JSTypedArray<UInt8>(bitmap.pixels).jsValue))
            _ = bitmaps.push!(object)
        }
        return bridge.paint!(context, buffer, strings, dpr, width, height, bitmaps).number ?? 0
    }
    private var lastOpCount = 0

    /// Mirrors the scene's host elements into the elements layer: a clipping wrapper at the
    /// visible frame holding the element at the element's own frame.
    private func updateHostElements() {
        let elements = scene.hostElements()
        var seen = Set<Int>()
        for element in elements {
            seen.insert(element.identifier)
            var entry = hostElementViews[element.identifier]
            if let existing = entry, !Self.sameElementKind(existing.state.kind, element.kind) {
                _ = existing.wrapper.remove!()
                entry = nil
            }
            if entry == nil {
                let wrapper = document.createElement!("div").object!
                let wrapperStyle = wrapper.style.object!
                wrapperStyle.position = .string("absolute")
                wrapperStyle.overflow = .string("hidden")
                wrapperStyle.pointerEvents = .string("auto")
                let created: JSObject
                switch element.kind {
                case .video:
                    created = document.createElement!("video").object!
                    _ = created.setAttribute!("playsinline", "")
                case .web:
                    created = document.createElement!("iframe").object!
                    _ = created.setAttribute!("sandbox", "allow-scripts allow-same-origin allow-forms allow-popups")
                    _ = created.setAttribute!("referrerpolicy", "no-referrer")
                }
                let style = created.style.object!
                style.position = .string("absolute")
                style.border = .string("0")
                style.margin = .string("0")
                style.padding = .string("0")
                style.display = .string("block")
                // A frame is clear: a page paints its own background, and one that refuses to
                // be framed paints nothing (WebKit), so what the view drew beneath shows.
                style.background = .string(element.kind.isVideo ? "black" : "transparent")
                _ = wrapper.appendChild!(created)
                if case .web = element.kind {
                    // A page that refuses to be framed (`X-Frame-Options`, `frame-ancestors`:
                    // Hacker News, GitHub, most news sites) shows nothing in the frame, and the
                    // page around it cannot tell. The way out is a link over the frame's corner
                    // that opens the page in a tab of its own — the one thing a browser's "open
                    // in Safari" is (decision 0021, Ember's reader and sign-in sheets).
                    let open = document.createElement!("a").object!
                    _ = open.setAttribute!("target", "_blank")
                    _ = open.setAttribute!("rel", "noopener noreferrer")
                    _ = open.setAttribute!("aria-label", "Open in browser")
                    open.textContent = .string("Open \u{2197}")
                    open.style.object!.cssText = .string("position:absolute;right:12px;bottom:12px;padding:6px 12px;border-radius:999px;background:rgba(28,28,30,0.78);color:#fff;font:600 13px -apple-system,system-ui,sans-serif;text-decoration:none;pointer-events:auto;box-shadow:0 1px 4px rgba(0,0,0,0.3)")
                    _ = wrapper.appendChild!(open)
                }
                _ = elementsLayer.appendChild!(wrapper)
                entry = (wrapper, created, HostElement(identifier: element.identifier, kind: element.kind, frame: .null, visibleFrame: .null))
            }
            guard var current = entry else { continue }
            if current.state.frame != element.frame || current.state.visibleFrame != element.visibleFrame {
                let wrapperStyle = current.wrapper.style.object!
                let visible = element.visibleFrame
                wrapperStyle.left = .string("\(visible.minX)px"); wrapperStyle.top = .string("\(visible.minY)px")
                wrapperStyle.width = .string("\(max(visible.width, 0))px"); wrapperStyle.height = .string("\(max(visible.height, 0))px")
                let style = current.element.style.object!
                style.left = .string("\(element.frame.minX - visible.minX)px"); style.top = .string("\(element.frame.minY - visible.minY)px")
                style.width = .string("\(element.frame.width)px"); style.height = .string("\(element.frame.height)px")
            }
            applyHostElementState(current.element, from: current.state.kind, to: element.kind, fresh: current.state.frame.isNull)
            current.state = element
            hostElementViews[element.identifier] = current
        }
        for (identifier, entry) in hostElementViews where !seen.contains(identifier) {
            _ = entry.wrapper.remove!()
            hostElementViews[identifier] = nil
        }
    }

    private static func sameElementKind(_ a: HostElement.Kind, _ b: HostElement.Kind) -> Bool {
        switch (a, b) {
        case (.video, .video), (.web, .web): return true
        default: return false
        }
    }

    /// Writes what changed of an element's state: the source, play/pause, the attributes.
    private func applyHostElementState(_ element: JSObject, from previous: HostElement.Kind, to kind: HostElement.Kind, fresh: Bool) {
        switch (previous, kind) {
        case (.video(let oldURL, let wasPlaying, let wasMuted, let didLoop, let hadControls, let oldRate),
              .video(let url, let playing, let muted, let loops, let controls, let rate)):
            if fresh || oldURL != url { element.src = .string(url) }
            if fresh || wasMuted != muted { element.muted = .boolean(muted) }
            if fresh || didLoop != loops { element.loop = .boolean(loops) }
            if fresh || hadControls != controls { element.controls = .boolean(controls) }
            if fresh || oldRate != rate { element.playbackRate = .number(rate == 0 ? 1 : rate) }
            if fresh || wasPlaying != playing {
                if playing { _ = element.play?() } else { _ = element.pause?() }
            }
        case (.web(let oldURL, let oldHTML), .web(let url, let html)):
            if fresh || oldHTML != html, let html { element.srcdoc = .string(html) }
            else if fresh || oldURL != url, let url { element.src = .string(url) }
            // The open-in-browser link follows the page; an HTML string has no page to open.
            if fresh || oldURL != url || oldHTML != html, let open = element.parentNode.object?.lastElementChild.object, open.tagName.string == "A" {
                if let url, html == nil {
                    _ = open.setAttribute!("href", url)
                    open.style.object!.display = .string("")
                } else {
                    open.style.object!.display = .string("none")
                }
            }
        default:
            break
        }
    }

    private func updateOverlay() {
        var seen = Set<Int>()
        let tree = scene.semanticsTree()
        semanticsMillis = (now - overlayStart) * 1000
        // Elements that moved or resized, positioned with one bridge call at the end:
        // identifier, x, y, then width and height or -1 when the size is unchanged.
        var moved: [Double] = []
        for node in tree {
            seen.insert(node.identifier)
            if let input = node.textInput {
                updateInputElement(node, input, moved: &moved)
                continue
            }
            let element: JSObject
            // A heading whose level changed needs a new element (the tag carries the level).
            if let existing = overlayButtons[node.identifier], let previous = overlayState[node.identifier], Self.overlayTag(for: previous) != Self.overlayTag(for: node) {
                _ = existing.remove!()
                _ = bridge.overlayRemove!(node.identifier)
                overlayButtons[node.identifier] = nil
                overlayState[node.identifier] = nil
            }
            if let existing = overlayButtons[node.identifier] {
                element = existing
            } else {
                element = document.createElement!(Self.overlayTag(for: node)).object!
                let style = element.style.object!
                style.position = .string("absolute")
                style.opacity = .string("0")
                style.pointerEvents = .string("none")
                style.margin = .string("0")
                style.padding = .string("0")
                style.border = .string("0")
                let id = node.identifier
                switch node.role {
                case .slider:
                    on(element, "input") { [weak self] e in
                        guard let self, let target = e.target.object, let value = Double(target.value.string ?? "") else { return }
                        self.scene.setValue(semanticsIdentifier: id, value: value)
                        self.scheduleFrame()
                    }
                case .text, .heading, .image, .group, .list:
                    break
                default:
                    on(element, "click") { [weak self] _ in
                        self?.scene.activate(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                // Keyboard focus is mirrored into the scene: the ring shows for keyboard focus
                // (`:focus-visible`), not for a click.
                if node.isFocusable || ![.text, .heading, .image, .group].contains(node.role) {
                    on(element, "focus") { [weak self] e in
                        guard let self else { return }
                        let visible = e.target.object?.matches?(":focus-visible").boolean ?? true
                        self.scene.focus(semanticsIdentifier: id, keyboard: visible)
                        self.scheduleFrame()
                    }
                    on(element, "blur") { [weak self] _ in
                        self?.scene.blur(semanticsIdentifier: id)
                        self?.scheduleFrame()
                    }
                }
                _ = overlay.appendChild!(element)
                overlayButtons[node.identifier] = element
                _ = bridge.overlayAdd!(node.identifier, element)
            }
            let previous = overlayState[node.identifier]
            if previous?.frame != node.frame {
                let resized = previous?.frame.size != node.frame.size
                moved += [Double(node.identifier), node.frame.minX, node.frame.minY, resized ? node.frame.width : -1, resized ? node.frame.height : -1]
            }
            var unmoved = node
            unmoved.frame = previous?.frame ?? .zero
            if previous == nil || previous != unmoved {
                Self.applyAttributes(of: node, to: element)
            }
            if previous?.customActions != node.customActions || previous?.rotors != node.rotors {
                syncActionsAndRotors(of: node, in: element)
            }
            overlayState[node.identifier] = node
            // Programmatic focus (`FocusState`, a click on a focusable view) moves the host's focus.
            if scene.focusedIdentifier == node.identifier, !(document.activeElement.object === element) {
                _ = element.focus?()
            }
        }
        for (id, element) in overlayButtons where !seen.contains(id) {
            _ = element.remove!()
            _ = bridge.overlayRemove!(id)
            overlayButtons[id] = nil
            overlayState[id] = nil
        }
        if !moved.isEmpty { _ = bridge.overlayFrames!(JSTypedArray<Double>(moved)) }
        deliverAccessibilityEvents()
    }

    /// Speaks the announcements the scene posted (the live region's text changes; the same text
    /// twice gets a zero-width space so it is spoken again) and moves focus where asked.
    private func deliverAccessibilityEvents() {
        for event in scene.takeAccessibilityEvents() {
            switch event {
            case .announce(let text):
                let previous = announcer.textContent.string ?? ""
                announcer.textContent = .string(previous == text ? text + "\u{200B}" : text)
            case .focus(let identifier):
                if let element = overlayButtons[identifier] { _ = element.focus?() }
            case .layoutChanged, .screenChanged:
                break
            }
        }
    }

    /// The overlay element for a semantics role: real controls where the browser has them
    /// (buttons, range inputs), headings (at their level) and plain elements for static content.
    private static func overlayTag(for node: SemanticsNode) -> String {
        switch node.role {
        case .slider: return "input"
        case .heading: return "h\(min(max(node.headingLevel ?? 2, 1), 6))"
        case .text, .image, .group, .list: return "div"
        default: return "button"
        }
    }

    /// Custom actions become buttons inside the element (reachable by assistive technology,
    /// each performing its action), rotors a `nav` landmark named after the rotor with a link
    /// per entry that focuses the entry's element.
    private func syncActionsAndRotors(of node: SemanticsNode, in element: JSObject) {
        let stale = element.querySelectorAll!("[data-swiftuiweb-extra]").object!
        var index = 0
        while let child = stale[index].object {
            _ = child.remove!()
            index += 1
        }
        let id = node.identifier
        for name in node.customActions {
            let button = document.createElement!("button").object!
            _ = button.setAttribute!("data-swiftuiweb-extra", "action")
            _ = button.setAttribute!("aria-label", name)
            button.textContent = .string(name)
            Self.hide(button)
            on(button, "click") { [weak self] e in
                _ = e.stopPropagation?()
                self?.scene.performAccessibilityAction(semanticsIdentifier: id, name: name)
                self?.scheduleFrame()
            }
            _ = element.appendChild!(button)
        }
        for rotor in node.rotors {
            let nav = document.createElement!("nav").object!
            _ = nav.setAttribute!("data-swiftuiweb-extra", "rotor")
            _ = nav.setAttribute!("aria-label", rotor.label)
            Self.hide(nav)
            for entry in rotor.entries {
                let link = document.createElement!("a").object!
                _ = link.setAttribute!("href", "#")
                _ = link.setAttribute!("aria-label", entry.label)
                link.textContent = .string(entry.label)
                let target = entry.target
                on(link, "click") { [weak self] e in
                    _ = e.preventDefault?()
                    _ = e.stopPropagation?()
                    guard let self, let target else { return }
                    self.scene.focus(semanticsIdentifier: target, keyboard: true)
                    self.scheduleFrame()
                }
                _ = nav.appendChild!(link)
            }
            _ = element.appendChild!(nav)
        }
    }

    private static func hide(_ element: JSObject) {
        let style = element.style.object!
        style.position = .string("absolute")
        style.opacity = .string("0")
        style.pointerEvents = .string("none")
        style.margin = .string("0")
        style.padding = .string("0")
        style.border = .string("0")
    }

    /// ARIA attributes and text for an element from its semantics.
    private static func applyAttributes(of node: SemanticsNode, to element: JSObject) {
        // The label is the element's first text node (`textContent` would drop the action
        // buttons and rotor landmarks inside it).
        if let first = element.firstChild.object, first.nodeType.number == 3 {
            first.nodeValue = .string(node.label)
        } else {
            let text = element.ownerDocument.object!.createTextNode!(node.label).object!
            if let first = element.firstChild.object { _ = element.insertBefore!(text, first) } else { _ = element.appendChild!(text) }
        }
        _ = element.setAttribute!("aria-label", node.label)
        switch node.role {
        case .checkbox:
            _ = element.setAttribute!("role", "checkbox")
            _ = element.setAttribute!("aria-checked", node.isOn == true ? "true" : "false")
        case .switch:
            _ = element.setAttribute!("role", "switch")
            _ = element.setAttribute!("aria-checked", node.isOn == true ? "true" : "false")
        case .slider:
            element.type = .string("range")
            if let range = node.range {
                _ = element.setAttribute!("min", "\(range.minimum)")
                _ = element.setAttribute!("max", "\(range.maximum)")
                _ = element.setAttribute!("step", range.step.map { "\($0)" } ?? "any")
                if element.value.string != "\(range.value)" { element.value = .string("\(range.value)") }
            }
        case .stepper:
            _ = element.setAttribute!("role", "spinbutton")
        case .popUpButton:
            _ = element.setAttribute!("aria-haspopup", "listbox")
        case .segmented, .radioGroup:
            _ = element.setAttribute!("role", "radiogroup")
        case .image:
            _ = element.setAttribute!("role", "img")
        case .group:
            _ = element.setAttribute!("role", "group")
        case .list:
            _ = element.setAttribute!("role", "listbox")
        case .link:
            _ = element.setAttribute!("role", "link")
        case .text, .heading, .button, .textField:
            break
        }
        if node.isFocusable { _ = element.setAttribute!("tabindex", "0") }
        if let value = node.value { _ = element.setAttribute!("aria-valuetext", value) }
        if let hint = node.hint { _ = element.setAttribute!("aria-description", hint) } else { _ = element.removeAttribute!("aria-description") }
        if let identifier = node.accessibilityIdentifier { _ = element.setAttribute!("data-testid", identifier) }
        if let description = node.description { _ = element.setAttribute!("title", description) } else { _ = element.removeAttribute!("title") }
        if node.isLive { _ = element.setAttribute!("aria-live", "polite") } else { _ = element.removeAttribute!("aria-live") }
        if let selected = node.isSelected { _ = element.setAttribute!("aria-selected", selected ? "true" : "false") } else { _ = element.removeAttribute!("aria-selected") }
        if node.isEnabled { _ = element.removeAttribute!("aria-disabled") } else { _ = element.setAttribute!("aria-disabled", "true") }
    }

    /// A text field's editor: a real `<input>` over the text line with transparent text (the
    /// canvas paints it), so typing, IME composition, caret, selection and copy/paste are the
    /// browser's. Its value flows into the binding on every `input` event.
    private func updateInputElement(_ node: SemanticsNode, _ info: TextInputInfo, moved: inout [Double]) {
        let element: JSObject
        if let existing = overlayButtons[node.identifier] {
            element = existing
        } else {
            element = document.createElement!(info.isMultiline ? "textarea" : "input").object!
            let style = element.style.object!
            style.position = .string("absolute")
            style.margin = .string("0")
            style.padding = .string("0")
            style.border = .string("0")
            style.outline = .string("none")
            style.background = .string("transparent")
            style.color = .string("transparent")
            // The scene paints the caret and selection (TextInputInfo.paintsCaret): the
            // element's stay invisible (`::selection` through the overlay's style rule).
            style.caretColor = .string(info.paintsCaret ? "transparent" : "black")
            style.pointerEvents = .string("auto")
            style.boxSizing = .string("border-box")
            if info.paintsCaret { _ = element.classList.object?.add?("swiftuiweb-input") }
            installInputStyleRule()
            if info.isMultiline {
                style.resize = .string("none")
                style.overflow = .string("hidden")
                style.whiteSpace = .string("pre-wrap")
                style.wordBreak = .string("break-word")
            }
            _ = element.setAttribute!("autocomplete", "off")
            _ = element.setAttribute!("autocapitalize", "off")
            _ = element.setAttribute!("spellcheck", "false")
            let id = node.identifier
            on(element, "input") { [weak self] e in
                guard let self, let target = e.target.object else { return }
                self.scene.textField(id, didChange: target.value.string ?? "")
                self.reportSelection(id, target)
                self.scheduleFrame()
            }
            // The caret and selection follow keys, the pointer and programmatic moves.
            for event in ["select", "keyup", "mouseup", "focus"] {
                on(element, event) { [weak self] e in
                    guard let self, let target = e.target.object else { return }
                    self.reportSelection(id, target)
                    self.scheduleFrame()
                }
            }
            on(element, "keydown") { [weak self] e in
                guard let self, e.key.string == "Enter" else { return }
                // A text field submits on Return, even a multi-line one; an editor keeps the newline.
                guard self.overlayState[id]?.textInput?.submitsOnReturn ?? true else { return }
                if e.shiftKey.boolean != true { _ = e.preventDefault?() }
                self.scene.textFieldDidSubmit(id)
                self.scheduleFrame()
            }
            on(element, "focus") { [weak self] _ in
                self?.scene.textField(id, focused: true)
                self?.scheduleFrame()
            }
            if info.isMultiline {
                // The editor's own scrolling: the scene paints its text at the same offset.
                on(element, "scroll") { [weak self] _ in
                    guard let self, let top = element.scrollTop.number else { return }
                    self.scene.textField(id, scrolledTo: CGFloat(top))
                    self.scheduleFrame()
                }
            }
            on(element, "blur") { [weak self] _ in
                self?.scene.textField(id, focused: false)
                self?.scheduleFrame()
            }
            _ = overlay.appendChild!(element)
            overlayButtons[node.identifier] = element
            _ = bridge.overlayAdd!(node.identifier, element)
        }
        let previous = overlayState[node.identifier]?.textInput
        if previous?.textRect != info.textRect {
            moved += [Double(node.identifier), info.textRect.minX, info.textRect.minY, info.textRect.width, info.textRect.height]
        }
        if previous == nil || previous?.font != info.font || previous?.lineHeight != info.lineHeight
            || previous?.firstBaseline != info.firstBaseline || previous?.textRect.height != info.textRect.height
            || previous?.isSecure != info.isSecure || previous?.isEnabled != info.isEnabled || previous?.inputType != info.inputType {
            let style = element.style.object!
            style.font = .string(DisplayListEncoder.cssFont(info.font))
            if info.isMultiline {
                // The textarea's first baseline lands where the canvas paints it: pad the top by
                // the difference between the scene's first baseline and the line box's own.
                style.lineHeight = .string("\(info.lineHeight)px")
                style.paddingTop = .string("\(max(0, info.firstBaseline - info.lineHeight * 0.8))px")
            } else {
                style.lineHeight = .string("\(info.textRect.height)px")
                element.type = .string(info.isSecure ? "password" : (info.inputType ?? "text"))
            }
            element.disabled = .boolean(!info.isEnabled)
        }
        // The keyboard attributes (submitLabel, keyboardType, textContentType, autocapitalization,
        // autocorrection) reach the element as it changes.
        if previous == nil || previous?.inputMode != info.inputMode || previous?.autocomplete != info.autocomplete
            || previous?.autocapitalize != info.autocapitalize || previous?.enterKeyHint != info.enterKeyHint || previous?.autocorrect != info.autocorrect {
            setOrRemove(element, "inputmode", info.inputMode)
            setOrRemove(element, "autocomplete", info.autocomplete ?? "off")
            setOrRemove(element, "autocapitalize", info.autocapitalize ?? "off")
            setOrRemove(element, "enterkeyhint", info.enterKeyHint)
            setOrRemove(element, "autocorrect", info.autocorrect ? "on" : "off")
            setOrRemove(element, "spellcheck", info.autocorrect ? "true" : "false")
        }
        if overlayState[node.identifier]?.label != node.label { _ = element.setAttribute!("aria-label", node.label) }
        overlayState[node.identifier] = node
        if element.value.string != info.text { element.value = .string(info.text) }
        // A selection the scene set (a selection binding) and an editor scrolled by the wheel.
        if let selection = info.selection, previous?.selection != info.selection {
            _ = element.setSelectionRange?(selection.start, selection.end)
        }
        if info.isMultiline, previous?.scrollOffset != info.scrollOffset, abs((element.scrollTop.number ?? 0) - info.scrollOffset) > 0.5 {
            element.scrollTop = .number(info.scrollOffset)
        }
        // A field the scene focused (a canvas press) takes the browser focus too.
        if scene.focusedTextFieldIdentifier == node.identifier, document.activeElement.object != element {
            _ = element.focus?()
        }
    }

    private func setOrRemove(_ element: JSObject, _ name: String, _ value: String?) {
        if let value { _ = element.setAttribute!(name, value) } else { _ = element.removeAttribute!(name) }
    }

    /// Tells the scene where the element's caret or selection is (UTF-16 offsets).
    private func reportSelection(_ id: Int, _ element: JSObject) {
        guard let start = element.selectionStart.number, let end = element.selectionEnd.number else { return }
        scene.textField(id, selectionStart: Int(start), end: Int(end))
    }

    private var installedInputStyleRule = false

    /// The overlay inputs' own selection highlight is invisible: the scene paints it.
    private func installInputStyleRule() {
        guard !installedInputStyleRule else { return }
        installedInputStyleRule = true
        let style = document.createElement!("style").object!
        style.textContent = .string(".swiftuiweb-input::selection { background: transparent; color: transparent; }")
        _ = document.head.object?.appendChild!(style)
    }

    /// The content size category short name the body point size of `-apple-system-body` maps to,
    /// nil when the browser does not know the keyword or the size is not one of the table's.
    static func dynamicTypeSize(in document: JSObject) -> String? {
        guard let span = document.createElement!("span").object, let body = document.body.object else { return nil }
        span.style.object!.font = .string("-apple-system-body")
        guard let font = span.style.object!.font.string, !font.isEmpty else { return nil }
        span.style.object!.position = .string("absolute")
        span.style.object!.visibility = .string("hidden")
        _ = body.appendChild!(span)
        defer { _ = body.removeChild!(span) }
        guard let text = JSObject.global.getComputedStyle!(span).object?.fontSize.string, let size = Double(text.prefix { $0 != "p" }) else { return nil }
        return categoryName(forBodySize: size)
    }

    /// The body text style's point size at each content size category (the HIG table).
    static func categoryName(forBodySize size: Double) -> String? {
        let sizes: [(Double, String)] = [(14, "XS"), (15, "S"), (16, "M"), (17, "L"), (19, "XL"), (21, "XXL"), (23, "XXXL"), (28, "AXM"), (33, "AXL"), (40, "AXXL"), (47, "AXXXL"), (53, "AXXXXL")]
        return sizes.first { abs($0.0 - size) < 0.5 }?.1
    }

    /// `window.__swiftuiwebDebug`: probe frames, display list and frame count for Tier B tests.
    private func installDebugBridge() {
        let debug = JSObject.global.Object.function!.new()
        let frames = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let object = JSObject.global.Object.function!.new()
            for (id, frame) in self.scene.probeFrames {
                let rect = JSObject.global.Object.function!.new()
                rect.x = .number(frame.minX); rect.y = .number(frame.minY)
                rect.width = .number(frame.width); rect.height = .number(frame.height)
                object[dynamicMember: id] = .object(rect)
            }
            return .object(object)
        }
        let displayList = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let array = JSObject.global.Array.function!.new()
            for command in self.lastDisplayList.commands { _ = array.push!(command.description) }
            return .object(array)
        }
        let frameCount = JSClosure { [weak self] _ in .number(Double(self?.frameCount ?? 0)) }
        let frameMillis = JSClosure { [weak self] _ in .number(self?.frameMillis ?? 0) }
        let framePhases = JSClosure { [weak self] _ in
            let object = JSObject.global.Object.function!.new()
            let phases = self?.framePhases ?? [0, 0, 0, 0, 0, 0]
            object.layout = .number(phases[0]); object.render = .number(phases[1]); object.encode = .number(phases[2])
            object.paint = .number(phases[3]); object.semantics = .number(phases[4]); object.overlay = .number(phases[5])
            object.gap = .number(self?.frameGapMillis ?? 0)
            object.ops = .number(Double(self?.lastOpCount ?? 0))
            // Why the frame laid out (or "moved"/"repaint"), with the pass's measurements and memo misses.
            object.reason = .string(self?.scene.lastLayoutReason ?? "")
            object.measures = .number(Double(self?.scene.lastLayoutMeasures ?? 0))
            object.computes = .number(Double(self?.scene.lastLayoutComputes ?? 0))
            return .object(object)
        }
        let pendingImages = JSClosure { [weak self] _ in self?.bridge.pendingImages!() ?? .number(0) }
        let animating = JSClosure { [weak self] _ in .boolean(self?.scene.isAnimating ?? false) }
        let semantics = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let array = JSObject.global.Array.function!.new()
            for node in self.scene.semanticsTree() {
                let object = JSObject.global.Object.function!.new()
                object.role = .string(node.role.rawValue)
                object.label = .string(node.label)
                if let value = node.value { object.value = .string(value) }
                if let identifier = node.accessibilityIdentifier { object.identifier = .string(identifier) }
                _ = array.push!(object)
            }
            return .object(array)
        }
        // WebFoundation as the host wired it: the zone `Intl` named, its offsets on a date, the
        // locale, a formatted date (Playwright/foundation-probe.mjs reads them).
        let foundation = JSClosure { arguments in
            let object = JSObject.global.Object.function!.new()
            let zone = TimeZone.current
            let date = arguments.first?.number.map { Date(timeIntervalSince1970: $0) } ?? Date()
            object.timeZone = .string(zone.identifier)
            object.secondsFromGMT = .number(Double(zone.secondsFromGMT(for: date)))
            object.isDaylightSavingTime = .boolean(zone.isDaylightSavingTime(for: date))
            object.abbreviation = .string(zone.abbreviation(for: date) ?? "")
            object.zoneName = .string(zone.localizedName(for: .standard, locale: nil) ?? "")
            object.locale = .string(Locale.current.identifier)
            object.knownZones = .number(Double(TimeZone.knownTimeZoneIdentifiers.count))
            object.formatted = .string(date.formatted(date: .complete, time: .complete))
            if let berlin = TimeZone(identifier: "Europe/Berlin") {
                object.berlinOffset = .number(Double(berlin.secondsFromGMT(for: date)))
                object.berlinName = .string(berlin.abbreviation(for: date) ?? "")
            }
            return .object(object)
        }
        // drag(x, y, dx, dy, seconds): a scripted finger drag (see `scriptedDrag`).
        let drag = JSClosure { [weak self] arguments in
            guard let self else { return .undefined }
            let v = arguments.map { $0.number ?? 0 }
            guard v.count >= 5 else { return .boolean(false) }
            self.scriptedDrag = (CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3]), 0, v[4], false)
            self.scheduleFrame()
            return .boolean(true)
        }
        let dragging = JSClosure { [weak self] _ in .boolean(self?.scriptedDrag != nil) }
        // bench(n): milliseconds for n iterations of plain Swift arithmetic over an array, the
        // speed of this module's wasm tier on the device, against the same loop in JavaScript.
        let bench = JSClosure { [weak self] arguments in
            guard let self else { return .undefined }
            let n = Int(arguments.first?.number ?? 1_000_000)
            let start = self.now
            var values = [Double](repeating: 1, count: 1024)
            var acc = 0.0
            for i in 0..<n {
                let j = i & 1023
                values[j] = values[j] * 0.5 + Double(i & 255) * 0.25
                acc += values[j].squareRoot()
            }
            return .number((self.now - start) * 1000 + (acc.isNaN ? 1 : 0))
        }
        // layoutProfile(on): switches layout profiling; returns the last profiled pass as
        // { computes: { kind: n }, proposals: { kind: most distinct proposals one node computed } }.
        let layoutProfile = JSClosure { [weak self] arguments in
            guard let self else { return .undefined }
            if let on = arguments.first?.boolean { self.scene.profileLayout = on }
            let object = JSObject.global.Object.function!.new()
            let computes = JSObject.global.Object.function!.new(), proposals = JSObject.global.Object.function!.new()
            for (kind, n) in self.scene.lastComputeHistogram { computes[dynamicMember: kind] = .number(Double(n)) }
            for (kind, n) in self.scene.lastProposalHistogram { proposals[dynamicMember: kind] = .number(Double(n)) }
            object.computes = .object(computes); object.proposals = .object(proposals)
            let worst = JSObject.global.Array.function!.new()
            for p in self.scene.lastWorstNodeProposals { _ = worst.push!(p) }
            object.worst = .object(worst)
            let chain = JSObject.global.Array.function!.new()
            for p in self.scene.lastWorstNodeChain { _ = chain.push!(p) }
            object.chain = .object(chain)
            let shares = JSObject.global.Object.function!.new()
            for (k, n) in self.scene.lastShareProbes { shares[dynamicMember: k] = .number(Double(n)) }
            object.shares = .object(shares)
            return .object(object)
        }
        closures += [frames, displayList, frameCount, frameMillis, framePhases, pendingImages, animating, semantics, foundation, drag, dragging, bench, layoutProfile]
        debug.layoutProfile = .object(layoutProfile)
        // scrollViews(): every scroll view's [x, y, w, h, offsetX, offsetY] in points.
        let scrollViews = JSClosure { [weak self] _ in
            guard let self else { return .undefined }
            let list = JSObject.global.Array.function!.new()
            for entry in self.scene.debugScrollViews {
                let row = JSObject.global.Array.function!.new()
                for value in entry { _ = row.push!(JSValue.number(value)) }
                _ = list.push!(row)
            }
            return .object(list)
        }
        closures.append(scrollViews)
        debug.scrollViews = .object(scrollViews)
        debug.bench = .object(bench)
        debug.drag = .object(drag)
        debug.dragging = .object(dragging)
        debug.foundation = .object(foundation)
        debug.framePhases = .object(framePhases)
        debug.animating = .object(animating)
        debug.semantics = .object(semantics)
        debug.pendingImages = .object(pendingImages)
        debug.frames = .object(frames)
        debug.displayList = .object(displayList)
        debug.frameCount = .object(frameCount)
        debug.frameMillis = .object(frameMillis)
        JSObject.global.__swiftuiwebDebug = .object(debug)
        // The frame-time HUD (`?perf`): rolling frame statistics over the page, a scripted drag.
        if marksEnabled { _ = bridge.installHud?(debug) }
    }
}

/// The browser's image loader: `Image` elements kept by the painter script, asked by URL.
@MainActor
final class CanvasImageLoader: _ImageLoading {
    private let bridge: JSObject
    init(bridge: JSObject) { self.bridge = bridge }

    func state(for url: String) -> _ImageLoadState {
        let state = bridge.imageState!(url)
        if let text = state.string { return text == "failed" ? .failed : .loading }
        guard let array = state.object, let width = array[0].number, let height = array[1].number else { return .loading }
        return .loaded(pixelSize: CGSize(width: width, height: height))
    }

    func cancel(_ url: String) {
        _ = bridge.imageCancel?(url)
    }
}


/// The browser's `Intl` behind WebFoundation's named time zones and the current locale.
enum IntlBridge {
    /// One `Intl.DateTimeFormat` per zone and name style, made on first use.
    nonisolated(unsafe) private static var formatters: [String: JSObject] = [:]
    /// One `Intl.DisplayNames` per locale and kind of code, made on first use.
    nonisolated(unsafe) private static var displayNames: [String: JSObject] = [:]

    static func install() {
        let intl = JSObject.global.Intl
        guard let dateTimeFormat = intl.DateTimeFormat.function else { return }
        if let zone = dateTimeFormat.new().resolvedOptions?().timeZone.string, !zone.isEmpty { TimeZone._hostIdentifier = zone }
        TimeZone._hostOffset = { identifier, time in
            guard let parts = formatParts(identifier, style: "longOffset", time: time) else { return nil }
            return parseOffset(parts)
        }
        TimeZone._hostName = { identifier, time, style in formatParts(identifier, style: style, time: time) }
        TimeZone._hostKnownIdentifiers = {
            guard let values = JSObject.global.Intl.supportedValuesOf.function?("timeZone").object else { return ["GMT"] }
            let count = Int(values.length.number ?? 0)
            return (0..<count).compactMap { values[$0].string }
        }
        if intl.DisplayNames.function != nil {
            Locale._hostDisplayName = { locale, type, code in
                let key = locale + "|" + type
                let names: JSObject
                if let known = displayNames[key] {
                    names = known
                } else {
                    let options = JSObject.global.Object.function!.new()
                    options.type = .string(type)
                    options.fallback = .string("none")
                    guard let made = JSObject.global.Intl.DisplayNames.function?.new(locale, options) else { return nil }
                    names = made
                    displayNames[key] = made
                }
                // `of` throws a RangeError for a malformed code; an undefined answer is unknown.
                guard code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }), !code.isEmpty else { return nil }
                return names.of?(code.replacingOccurrences(of: "_", with: "-")).string
            }
        }
        Locale._hostDatePattern = { locale, request in
            let key = locale + "|" + request
            if let known = datePatterns[key] { return known }
            let made = datePattern(locale, request)
            datePatterns[key] = made
            return made
        }
        Locale._hostDateSymbols = { locale in
            if let known = dateSymbols[locale] { return known }
            let made = symbols(locale)
            dateSymbols[locale] = made
            return made
        }
        let navigator = JSObject.global.navigator
        if let language = navigator.language.string, !language.isEmpty { Locale._hostIdentifier = language }
        if let languages = navigator.languages.object {
            let count = Int(languages.length.number ?? 0)
            let list = (0..<count).compactMap { languages[$0].string }
            if !list.isEmpty { Locale._hostPreferredLanguages = list }
        }
    }

    /// The `timeZoneName` part of a format in the given style, nil for a zone `Intl` rejects.
    private static func formatParts(_ identifier: String, style: String, time: Double) -> String? {
        let key = identifier + "|" + style
        let formatter: JSObject
        if let known = formatters[key] {
            formatter = known
        } else {
            guard let constructor = JSObject.global.Intl.DateTimeFormat.function else { return nil }
            let options = JSObject.global.Object.function!.new()
            options.timeZone = .string(identifier)
            options.timeZoneName = .string(style)
            guard let made = try? JSThrowingFunction(constructor).new("en-US", options) else { return nil }
            formatters[key] = made
            formatter = made
        }
        guard let parts = formatter.formatToParts?(time * 1000).object else { return nil }
        let count = Int(parts.length.number ?? 0)
        for index in 0..<count where parts[index].type.string == "timeZoneName" { return parts[index].value.string }
        return nil
    }

    // MARK: Dates in a locale's own order and words

    nonisolated(unsafe) private static var datePatterns: [String: String?] = [:]
    nonisolated(unsafe) private static var dateSymbols: [String: _DatePattern.Symbols?] = [:]

    /// A formatter in UTC (the patterns and words don't depend on the zone), nil when `Intl` rejects it.
    private static func dateFormatter(_ locale: String, _ options: [String: String]) -> JSObject? {
        guard let constructor = JSObject.global.Intl.DateTimeFormat.function else { return nil }
        let object = JSObject.global.Object.function!.new()
        object.timeZone = .string("UTC")
        for (key, value) in options { object[key] = .string(value) }
        return try? JSThrowingFunction(constructor).new(locale, object)
    }

    /// `(type, value)` for each part of a UTC instant (seconds since 1970) formatted.
    private static func parts(_ formatter: JSObject, _ time: Double) -> [(String, String)] {
        guard let list = formatter.formatToParts?(time * 1000).object else { return [] }
        return (0..<Int(list.length.number ?? 0)).compactMap { index in
            guard let type = list[index].type.string, let value = list[index].value.string else { return nil }
            return (type, value)
        }
    }

    /// The LDML pattern `Intl` formats a request with: a canonical skeleton ("EEEEdMMMM"), a
    /// `Date.FormatStyle` style ("style:<date>:<time>") or a `DateFormatter` one
    /// ("formatter:<date>:<time>"). Read off the parts of a reference instant whose day, month and
    /// hour have one digit, so a two-digit field shows as two letters. Nil for a field `Intl` has
    /// no option for (quarters, weeks, day of year), which then formats as `en`.
    private static func datePattern(_ locale: String, _ request: String) -> String? {
        var options: [String: String] = [:]
        var dropPeriod = false
        let pieces = request.split(separator: ":")
        if pieces.count == 3, pieces[0] == "style" || pieces[0] == "formatter", let date = Int(pieces[1]), let time = Int(pieces[2]) {
            let formatter = pieces[0] == "formatter"
            switch date {
            case 1: options = formatter ? ["dateStyle": "short"] : ["year": "numeric", "month": "numeric", "day": "numeric"]
            case 2: options = formatter ? ["dateStyle": "medium"] : ["year": "numeric", "month": "short", "day": "numeric"]
            case 3: options = formatter ? ["dateStyle": "long"] : ["year": "numeric", "month": "long", "day": "numeric"]
            case 4: options = formatter ? ["dateStyle": "full"] : ["year": "numeric", "month": "long", "day": "numeric", "weekday": "long"]
            default: break
            }
            if formatter {
                switch time {
                case 1: options["timeStyle"] = "short"
                case 2: options["timeStyle"] = "medium"
                case 3: options["timeStyle"] = "long"
                case 4: options["timeStyle"] = "full"
                default: break
                }
            } else if time > 0 {
                options["hour"] = "numeric"; options["minute"] = "2-digit"
                if time >= 2 { options["second"] = "2-digit" }
                if time >= 3 { options["timeZoneName"] = "short" }
            }
        } else {
            var index = request.startIndex
            while index < request.endIndex {
                let letter = request[index]
                var end = request.index(after: index)
                while end < request.endIndex, request[end] == letter { end = request.index(after: end) }
                let count = request.distance(from: index, to: end)
                index = end
                let text = count == 2 ? "2-digit" : "numeric"
                let name = count == 4 ? "long" : count == 5 ? "narrow" : "short"
                switch letter {
                case "G": options["era"] = name
                case "y": options["year"] = text
                case "M", "L": options["month"] = count <= 2 ? text : name
                case "E": options["weekday"] = count == 6 ? "short" : name
                case "d": options["day"] = text
                case "h": options["hour"] = text   // the locale's own clock, as Apple's `j`
                case "J": options["hour"] = text; dropPeriod = true
                case "H": options["hour"] = text; options["hourCycle"] = "h23"
                case "m": options["minute"] = "2-digit"
                case "s": options["second"] = "2-digit"
                case "a": break
                case "z": options["timeZoneName"] = count >= 4 ? "long" : "short"
                case "v": options["timeZoneName"] = count >= 4 ? "longGeneric" : "shortGeneric"
                case "O": options["timeZoneName"] = count >= 4 ? "longOffset" : "shortOffset"
                default: return nil
                }
            }
        }
        guard !options.isEmpty, let formatter = dateFormatter(locale, options) else { return nil }
        let cycle = formatter.resolvedOptions?().hourCycle.string ?? "h23"
        // Friday 5 January 2001, 09:03:07 UTC.
        var list = parts(formatter, 978_685_387)
        guard !list.isEmpty else { return nil }
        if dropPeriod, let period = list.firstIndex(where: { $0.0 == "dayPeriod" }) {
            list.remove(at: period)
            if period < list.count, list[period].0 == "literal", list[period].1.allSatisfy(\.isWhitespace) { list.remove(at: period) }
            else if period > 0, list[period - 1].0 == "literal", list[period - 1].1.allSatisfy(\.isWhitespace) { list.remove(at: period - 1) }
        }
        let hasDay = list.contains { $0.0 == "day" }
        var pattern = ""
        for (type, value) in list {
            let width = value.count
            switch type {
            case "literal":
                var quoted = ""
                var open = false
                for character in value {
                    if character == "'" { quoted += "''"; continue }
                    let letter = character.isASCII && character.isLetter
                    if letter != open { quoted += "'"; open = letter }
                    quoted.append(character)
                }
                if open { quoted += "'" }
                pattern += quoted
            case "era": pattern += options["era"] == "long" ? "GGGG" : options["era"] == "narrow" ? "GGGGG" : "G"
            case "year": pattern += width == 2 ? "yy" : "y"
            case "month":
                let letter = hasDay ? "M" : "L"
                if value.allSatisfy(\.isNumber) { pattern += String(repeating: letter, count: width >= 2 ? 2 : 1) }
                else {
                    let style = options["month"] ?? (options["dateStyle"] == "medium" ? "short" : "long")
                    pattern += String(repeating: letter, count: style == "long" ? 4 : style == "narrow" ? 5 : 3)
                }
            case "weekday":
                let style = options["weekday"] ?? "long"
                pattern += style == "long" ? "EEEE" : style == "narrow" ? "EEEEE" : "E"
            case "day": pattern += width >= 2 ? "dd" : "d"
            case "dayPeriod": pattern += "a"
            case "hour":
                let letter = cycle == "h11" ? "K" : cycle == "h12" ? "h" : cycle == "h24" ? "k" : "H"
                pattern += String(repeating: letter, count: width >= 2 ? 2 : 1)
            case "minute": pattern += "mm"
            case "second": pattern += "ss"
            case "fractionalSecond": pattern += String(repeating: "S", count: width)
            case "timeZoneName":
                switch options["timeZoneName"] {
                case "long": pattern += "zzzz"
                case "shortGeneric": pattern += "v"
                case "longGeneric": pattern += "vvvv"
                case "shortOffset": pattern += "O"
                case "longOffset": pattern += "OOOO"
                default: pattern += options["timeStyle"] == "full" ? "zzzz" : "z"
                }
            default: return nil
            }
        }
        return pattern
    }

    /// A locale's month and weekday names and day periods, from formatting each month and day.
    private static func symbols(_ locale: String) -> _DatePattern.Symbols? {
        func names(_ options: [String: String], _ type: String, _ times: [Double]) -> [String]? {
            guard let formatter = dateFormatter(locale, options) else { return nil }
            let list = times.compactMap { time in parts(formatter, time).first { $0.0 == type }?.1 }
            return list.count == times.count ? list : nil
        }
        // The 15th of each month of 2001, and Sunday 7 to Saturday 13 January 2001, at noon UTC.
        let months = (0..<12).map { 979_560_000 + Double([0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][$0]) * 86_400 }
        let days = (0..<7).map { 978_868_800 + Double($0) * 86_400 }
        guard let full = names(["day": "numeric", "month": "long"], "month", months),
              let short = names(["day": "numeric", "month": "short"], "month", months),
              let standalone = names(["month": "long"], "month", months),
              let shortStandalone = names(["month": "short"], "month", months),
              let weekdays = names(["weekday": "long"], "weekday", days),
              let shortWeekdays = names(["weekday": "short"], "weekday", days),
              let narrowWeekdays = names(["weekday": "narrow"], "weekday", days),
              let periods = names(["hour": "numeric", "hourCycle": "h12"], "dayPeriod", [978_685_200, 978_728_400])
        else { return nil }
        return _DatePattern.Symbols(months: full, shortMonths: short, standaloneMonths: standalone, shortStandaloneMonths: shortStandalone,
                                    weekdays: weekdays, shortWeekdays: shortWeekdays,
                                    shortestWeekdays: shortWeekdays.map { String($0.prefix(2)) }, narrowWeekdays: narrowWeekdays,
                                    am: periods[0], pm: periods[1])
    }

    /// Seconds east of GMT from "GMT", "GMT+2", "GMT-04:00" or "GMT+05:45".
    private static func parseOffset(_ text: String) -> Int? {
        let body = text.hasPrefix("GMT") ? text.dropFirst(3) : text.hasPrefix("UTC") ? text.dropFirst(3) : Substring(text)
        if body.isEmpty { return 0 }
        guard let sign = body.first, sign == "+" || sign == "-" || sign == "\u{2212}" else { return nil }
        let pieces = body.dropFirst().split(separator: ":")
        guard let hours = pieces.first.flatMap({ Int($0) }) else { return nil }
        let minutes = pieces.count > 1 ? Int(pieces[1]) ?? 0 : 0
        return (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
    }
}

#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum WebGraphicsCanvas {}
#endif
