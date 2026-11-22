// ShareLink (Docs/elements/ShareLink.md): a bordered button with the share symbol that hands
// its items to the host's share sheet.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// One thing a share link hands the host: a link, a text, or data of a content type (a
/// `Transferable` item's first fitting representation).
public struct _ShareItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case url(String)
        case text(String)
        case data(Data, type: UTType)
    }
    public let kind: Kind
    public init(_ kind: Kind) { self.kind = kind }

    /// The item as a URL string, text or data for a host: a `URL` or `String` as itself, else
    /// its first exported representation (a proxy to one of those, or data with its type).
    @MainActor package init?<T: Transferable>(_ value: T) {
        if let url = value as? URL { self.init(.url(url.absoluteString)); return }
        if let text = value as? String { self.init(.text(text)); return }
        if let data = value as? Data { self.init(.data(data, type: .data)); return }
        // The representations in declaration order: a proxy to a URL or a string as that, data
        // with its content type as a file (never imported across types: PNG bytes are no URL).
        for exporter in _TransferItem(value).exporters {
            if exporter.exportedType == URL.self, let url = exporter.export(value) as? URL { self.init(.url(url.absoluteString)); return }
            if exporter.exportedType == String.self, let text = exporter.export(value) as? String { self.init(.text(text)); return }
            if exporter.exportedType == Data.self, let data = exporter.export(value) as? Data {
                let type = exporter.contentType ?? .data
                if type == .url, let url = String(data: data, encoding: .utf8) { self.init(.url(url)); return }
                if type == .utf8PlainText || type == .plainText, let text = String(data: data, encoding: .utf8) { self.init(.text(text)); return }
                self.init(.data(data, type: type)); return
            }
        }
        return nil
    }
}

/// An item whose bytes come from an `async` exporter (an app that renders its image when shared,
/// `DataRepresentation(exportedContentType:)` with an async closure): the drawn share sheet waits
/// for them when it opens, as iOS's does.
public struct _PendingShareItem: @unchecked Sendable {
    public let contentType: UTType
    package let load: @MainActor () async -> Data?

    /// The value's first async data export, when it has no export to give at once.
    @MainActor package init?<T: Transferable>(_ value: T) {
        for exporter in _TransferItem(value).exporters {
            guard exporter.exportedType == Data.self, let work = exporter.exportAsync else { continue }
            contentType = exporter.contentType ?? .data
            load = { await work(value) as? Data }
            return
        }
        return nil
    }

    /// The item with its bytes, nil when the export gave none.
    @MainActor package func resolve() async -> _ShareItem? {
        guard let data = await load(), !data.isEmpty else { return nil }
        return _ShareItem(.data(data, type: contentType))
    }
}

/// What a share link asks the host to share: the items, the subject and message, and the
/// preview's title (the browser's Web Share takes a title, a text, a URL and files; the native
/// host hands the items to the sharing service picker).
public struct _ShareRequest: Equatable, Sendable {
    public var items: [_ShareItem]
    public var subject: String?
    public var message: String?
    public var previewTitle: String?
    /// Items still to be exported (awaited by the drawn share sheet; hosts get only `items`).
    public var pending: [_PendingShareItem] = []
    /// `SharePreview`'s image, shown in the drawn share sheet's header.
    package var previewImage: Image?

    public init(items: [_ShareItem], subject: String? = nil, message: String? = nil, previewTitle: String? = nil) {
        self.items = items
        self.subject = subject
        self.message = message
        self.previewTitle = previewTitle
    }

    public static func == (lhs: _ShareRequest, rhs: _ShareRequest) -> Bool {
        lhs.items == rhs.items && lhs.subject == rhs.subject && lhs.message == rhs.message && lhs.previewTitle == rhs.previewTitle
            && lhs.pending.map(\.contentType) == rhs.pending.map(\.contentType)
    }

    /// The data items as files for a host: the bytes, a name from the preview title or the
    /// index, and the MIME type of the content type.
    public var files: [(data: [UInt8], name: String, mimeType: String)] {
        var result: [(data: [UInt8], name: String, mimeType: String)] = []
        for (index, item) in items.enumerated() {
            guard case .data(let data, let type) = item.kind else { continue }
            let (mime, ext) = Self.mime(for: type)
            let base = previewTitle.map { title in String(title.map { (c: Character) -> Character in c.isLetter || c.isNumber ? c : "-" }) } ?? "item"
            result.append((data: Array(data), name: "\(base)\(result.isEmpty ? "" : "-\(index + 1)").\(ext)", mimeType: mime))
        }
        return result
    }

    private static func mime(for type: UTType) -> (String, String) {
        switch type.identifier {
        case "public.png": return ("image/png", "png")
        case "public.jpeg": return ("image/jpeg", "jpg")
        case "public.image": return ("image/png", "png")
        case "public.utf8-plain-text", "public.plain-text", "public.text": return ("text/plain", "txt")
        case "public.json": return ("application/json", "json")
        case "public.url": return ("text/uri-list", "url")
        default: return ("application/octet-stream", "bin")
        }
    }

    /// The items as strings, for hosts that share text and links (URLs as their strings).
    public var strings: [String] {
        items.compactMap { item in
            switch item.kind {
            case .url(let url): return url
            case .text(let text): return text
            case .data: return nil
            }
        }
    }
}

/// An action that shares items (the host's share sheet; the browser's Web Share).
public struct ShareAction: Sendable {
    /// The host's sharer: nil until a host installs one.
    @MainActor public static var systemHandler: (@MainActor (_ShareRequest) -> Void)?
    /// The host's clipboard, for the drawn share sheet's Copy: text, and image bytes with their
    /// MIME type (a browser takes PNG; the host converts).
    @MainActor public static var _copyText: (@MainActor (String) -> Void)?
    @MainActor public static var _copyImage: (@MainActor ([UInt8], String) -> Void)?

    @MainActor package static func share(_ request: _ShareRequest) {
        systemHandler?(request)
    }
}

/// A representation of a `Transferable` item for the share sheet: a title with an image and
/// an icon (the title reaches hosts; the images are kept for the sheet, which the hosts own).
public struct SharePreview<Image, Icon> {
    package let title: Text
    package let image: Image?
    package let icon: Icon?

    public init(_ title: Text, image: Image, icon: Icon) {
        self.title = title
        self.image = image
        self.icon = icon
    }
    public init(_ titleKey: LocalizedStringKey, image: Image, icon: Icon) { self.init(Text(titleKey), image: image, icon: icon) }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: Image, icon: Icon) { self.init(Text(title), image: image, icon: icon) }
}

extension SharePreview where Icon == Never {
    public init(_ title: Text, image: Image) { self.title = title; self.image = image; icon = nil }
    public init(_ titleKey: LocalizedStringKey, image: Image) { self.init(Text(titleKey), image: image) }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: Image) { self.init(Text(title), image: image) }
}

extension SharePreview where Image == Never {
    public init(_ title: Text, icon: Icon) { self.title = title; image = nil; self.icon = icon }
    public init(_ titleKey: LocalizedStringKey, icon: Icon) { self.init(Text(titleKey), icon: icon) }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, icon: Icon) { self.init(Text(title), icon: icon) }
}

extension SharePreview where Image == Never, Icon == Never {
    public init(_ title: Text) { self.title = title; image = nil; icon = nil }
    public init(_ titleKey: LocalizedStringKey) { self.init(Text(titleKey)) }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S) { self.init(Text(title)) }
}

/// A share link's subject, message and preview title, in one box: three `Text?` fields held
/// inline made `ShareLink`'s copy and assign witnesses about 60 KB of every bundle. Equatable,
/// so a re-render compares the texts and not the box.
/// The box also holds what only the drawn share sheet reads: the items an async exporter gives
/// and the preview's image.
private final class _ShareTexts: Equatable, @unchecked Sendable {
    let subject: Text?
    let message: Text?
    let previewTitle: Text?
    let pending: [_PendingShareItem]
    let previewImage: Image?

    init(subject: Text?, message: Text?, previewTitle: Text?, pending: [_PendingShareItem] = [], previewImage: Image? = nil) {
        self.subject = subject
        self.message = message
        self.previewTitle = previewTitle
        self.pending = pending
        self.previewImage = previewImage
    }

    static func == (lhs: _ShareTexts, rhs: _ShareTexts) -> Bool {
        lhs.subject == rhs.subject && lhs.message == rhs.message && lhs.previewTitle == rhs.previewTitle
            && lhs.pending.map(\.contentType) == rhs.pending.map(\.contentType)
    }
}

/// A view that controls a sharing presentation.
public struct ShareLink<Label: View>: View {
    package let items: [_ShareItem]
    private let texts: _ShareTexts
    package let label: Label
    package var subject: Text? { texts.subject }
    package var message: Text? { texts.message }
    package var previewTitle: Text? { texts.previewTitle }

    package init(shareItems: [_ShareItem], subject: Text?, message: Text?, previewTitle: Text?, label: Label,
                 pending: [_PendingShareItem] = [], previewImage: Image? = nil) {
        items = shareItems
        texts = _ShareTexts(subject: subject, message: message, previewTitle: previewTitle, pending: pending, previewImage: previewImage)
        self.label = label
    }

    /// Creates an instance that presents the share interface for the items with a custom label.
    public init(items: [URL], subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(shareItems: items.map { _ShareItem(.url($0.absoluteString)) }, subject: subject, message: message, previewTitle: nil, label: label())
    }

    @_disfavoredOverload
    public init(items: [String], subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(shareItems: items.map { _ShareItem(.text($0)) }, subject: subject, message: message, previewTitle: nil, label: label())
    }

    /// Creates an instance that shares `Transferable` items with a preview for each.
    @MainActor public init<I: Transferable, PreviewImage, PreviewIcon>(items: [I], subject: Text? = nil, message: Text? = nil,
                                                                       preview: (I) -> SharePreview<PreviewImage, PreviewIcon>, @ViewBuilder label: () -> Label) {
        self.init(shareItems: items.compactMap { _ShareItem($0) }, subject: subject, message: message,
                  previewTitle: items.first.map { preview($0).title }, label: label(),
                  pending: items.filter { _ShareItem($0) == nil }.compactMap { _PendingShareItem($0) },
                  previewImage: items.first.flatMap { preview($0).image as? Image })
    }

    /// Creates an instance that shares a `Transferable` item with a preview.
    @MainActor public init<I: Transferable, PreviewImage, PreviewIcon>(item: I, subject: Text? = nil, message: Text? = nil,
                                                                       preview: SharePreview<PreviewImage, PreviewIcon>, @ViewBuilder label: () -> Label) {
        let ready = _ShareItem(item)
        self.init(shareItems: [ready].compactMap { $0 }, subject: subject, message: message, previewTitle: preview.title, label: label(),
                  pending: ready == nil ? [_PendingShareItem(item)].compactMap { $0 } : [], previewImage: preview.image as? Image)
    }

    public init(item: URL, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(items: [item], subject: subject, message: message, label: label)
    }

    @_disfavoredOverload
    public init(item: String, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(items: [item], subject: subject, message: message, label: label)
    }

    public var body: some View {
        var request = _ShareRequest(items: items, subject: subject?.resolvedString, message: message?.resolvedString, previewTitle: previewTitle?.resolvedString)
        request.pending = texts.pending
        request.previewImage = texts.previewImage
        return _ShareLinkButton(request: request, label: label)
    }
}

/// A share link's button: on iOS it opens the drawn iPhone's share sheet (`_ShareSheet`), growing
/// out of the button as iOS 27's does; elsewhere it hands the items to the host (Web Share).
struct _ShareLinkButton<Label: View>: View {
    let request: _ShareRequest
    let label: Label
    @State private var presented = false
    @Environment(\.platformProfile) private var platformProfile

    var body: some View {
        if platformProfile.isIOS {
            Button(action: { presented = true }) { label }
                .sheet(isPresented: $presented) {
                    _ShareSheet(request: request, close: { presented = false })
                }
        } else {
            let request = request
            Button(action: { ShareAction.share(request) }) { label }
        }
    }
}

extension ShareLink where Label == SwiftUIWebCore.Label<Text, Image> {
    /// The default label: "Share…" with the share symbol.
    public init(item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init(item: String, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    public init(items: [URL], subject: Text? = nil, message: Text? = nil) {
        self.init(items: items, subject: subject, message: message) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    /// A titled share link with the share symbol.
    public init(_ titleKey: LocalizedStringKey, item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(titleKey, systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, item: URL, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(title, systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, item: String, subject: Text? = nil, message: Text? = nil) {
        self.init(item: item, subject: subject, message: message) { SwiftUIWebCore.Label(title, systemImage: "square.and.arrow.up") }
    }

    /// Shares a `Transferable` item with a preview under the default label.
    @MainActor public init<I: Transferable, PreviewImage, PreviewIcon>(item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview<PreviewImage, PreviewIcon>) {
        self.init(item: item, subject: subject, message: message, preview: preview) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    @MainActor public init<I: Transferable, PreviewImage, PreviewIcon>(items: [I], subject: Text? = nil, message: Text? = nil, preview: (I) -> SharePreview<PreviewImage, PreviewIcon>) {
        self.init(items: items, subject: subject, message: message, preview: preview) { SwiftUIWebCore.Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
    }

    /// A titled share link for a `Transferable` item with a preview.
    @MainActor public init<I: Transferable, PreviewImage, PreviewIcon>(_ titleKey: LocalizedStringKey, item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview<PreviewImage, PreviewIcon>) {
        self.init(item: item, subject: subject, message: message, preview: preview) { SwiftUIWebCore.Label(titleKey, systemImage: "square.and.arrow.up") }
    }

    @_disfavoredOverload
    @MainActor public init<S: StringProtocol, I: Transferable, PreviewImage, PreviewIcon>(_ title: S, item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview<PreviewImage, PreviewIcon>) {
        self.init(item: item, subject: subject, message: message, preview: preview) { SwiftUIWebCore.Label(title, systemImage: "square.and.arrow.up") }
    }
}
