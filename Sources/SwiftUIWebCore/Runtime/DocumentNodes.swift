// Document windows (API/DocumentGroup.swift, sw-windows): the runtime's New, Open…, Save and
// Save As… for a `DocumentGroup`, through the host's panels (`documentOpenHandler`,
// `documentSaveHandler`: the browser's file input and downloads, AppKit's open and save panels).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

extension Runtime {
    /// The main window's value box (a document group's document; `App._rootView`).
    @MainActor public static var mainWindowBox: _WindowValueBox?

    /// The document group among the scenes, if any.
    public var documentDescriptor: _WindowDescriptor? { windowDescriptors.first { $0.documentType != nil } }

    /// Shows the host's open panel for the types and hands back the chosen file's bytes, name
    /// and URL (nil in a browser). Installed by hosts.
    public var documentOpenHandler: ((_ types: [UTType], _ completion: @escaping @MainActor @Sendable (Data, String, URL?) -> Void) -> Void)? {
        get { documentOpen }
        set { documentOpen = newValue }
    }

    /// Writes a document's bytes: to `existing` when given and not asking "as", else through
    /// the host's save panel (a download in a browser); returns where it went (nil in a
    /// browser). Installed by hosts.
    public var documentSaveHandler: ((_ data: Data, _ name: String, _ type: UTType, _ existing: URL?) -> URL?)? {
        get { documentSave }
        set { documentSave = newValue }
    }

    /// The frontmost document's state: the key window's, else the main window's.
    public var frontmostDocument: (any _AnyDocumentState)? {
        if let keyWindow, let window = openWindows.first(where: { $0.node === keyWindow }), let state = window.box?.value as? any _AnyDocumentState { return state }
        if let state = Self.mainWindowBox?.value as? any _AnyDocumentState { return state }
        return openWindows.reversed().lazy.compactMap { $0.box?.value as? any _AnyDocumentState }.first
    }

    /// File > New: a window with a new document. False without a document group that makes one.
    @discardableResult
    public func newDocument() -> Bool {
        guard let descriptor = documentDescriptor, let make = descriptor.documentType?.makeNew else { return false }
        let state = make()
        return openWindow(id: descriptor.id, value: state.windowValue)
    }

    /// File > Open…: the host's panel, then a window with the file's document.
    @discardableResult
    public func openDocument() -> Bool {
        guard let descriptor = documentDescriptor, let box = descriptor.documentType, let handler = documentOpenHandler else { return false }
        handler(box.readableTypes) { [weak self] data, name, url in
            guard let self else { return }
            let type = box.readableTypes.first { type in name.lowercased().hasSuffix("." + (type.preferredFilenameExtension ?? "\u{0}")) } ?? box.readableTypes.first ?? .data
            guard let state = try? box.read(data, type, url, name) else { return }
            self.openWindow(id: descriptor.id, value: state.windowValue)
            self.setNeedsDisplay()
        }
        return true
    }

    /// File > Save (or Save As…): the frontmost document through the host's save handler.
    @discardableResult
    public func saveDocument(as asking: Bool = false) -> Bool {
        guard let state = frontmostDocument, let handler = documentSaveHandler else { return false }
        guard let serialized = try? state.serialized() else { return false }
        let url = handler(serialized.data, serialized.name, serialized.type, asking ? nil : state.fileURL)
        if let url { state.setFileURL(url) }
        return true
    }

    /// The standard File commands a document group adds to the menu bar and the keyboard:
    /// New ⌘N, Open… ⌘O, Save ⌘S, Save As… ⇧⌘S (`installWindows` registers them).
    package func documentCommands() -> [_CommandMenuData] {
        guard let descriptor = documentDescriptor, let box = descriptor.documentType else { return [] }
        weak let runtime = self
        var items: [AnyView] = []
        if box.makeNew != nil { items.append(AnyView(Button("New") { _ = runtime?.newDocument() }.keyboardShortcut("n"))) }
        items.append(AnyView(Button("Open\u{2026}") { _ = runtime?.openDocument() }.keyboardShortcut("o")))
        items.append(AnyView(Divider()))
        items.append(AnyView(Button("Save") { _ = runtime?.saveDocument() }.keyboardShortcut("s")))
        items.append(AnyView(Button("Save As\u{2026}") { _ = runtime?.saveDocument(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift])))
        let content = AnyView(_DocumentCommands(items: items))
        return [_CommandMenuData(title: nil, placement: .newItem, position: .replacing, content: content)]
    }
}

/// The document commands as one menu's content.
struct _DocumentCommands: View {
    let items: [AnyView]
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { $0.element }
    }
}
