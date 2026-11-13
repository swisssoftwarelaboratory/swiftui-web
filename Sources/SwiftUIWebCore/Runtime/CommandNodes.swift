// Responder commands (API/Commands.swift): `Runtime.performCommand` walks the focused node's
// ancestors (then the tree) for a handler of the selector; the edit keys map to the standard
// selectors; copy and cut hand `NSItemProvider` text to the pasteboard (and the host's
// clipboard), paste offers the pasteboard's text as a provider.
import WebFoundation

/// A selector by name (a string literal passed to `Selector` directly is checked against the
/// Objective-C methods the module declares, which has none).
package func _selector(_ name: String) -> Selector { Selector(name) }

/// The standard edit selectors.
package enum _StandardSelector {
    package static let copy = _selector("copy:")
    package static let cut = _selector("cut:")
    package static let paste = _selector("paste:")
    package static let selectAll = _selector("selectAll:")
    package static let undo = _selector("undo:")
    package static let redo = _selector("redo:")
}

@MainActor
package protocol _EditCommandHandling: AnyObject {
    /// Performs the command if this node handles it; returns whether it did.
    func performCommand(_ selector: Selector, runtime: Runtime) -> Bool
}

@MainActor
package final class EditCommandNode<Content: View>: UnaryLayoutModifierNode<Content, _EditCommandModifier>, _EditCommandHandling {
    package func performCommand(_ selector: Selector, runtime: Runtime) -> Bool {
        switch modifier.box.kind {
        case .selector(let own, let action):
            guard own == selector, let action else { return false }
            action()
            return true
        case .copy(let payload):
            guard selector == _StandardSelector.copy else { return false }
            let providers = payload()
            guard !providers.isEmpty else { return false }
            runtime.setPasteboard(providers: providers)
            return true
        case .cut(let payload):
            guard selector == _StandardSelector.cut else { return false }
            let providers = payload()
            guard !providers.isEmpty else { return false }
            runtime.setPasteboard(providers: providers)
            runtime.requestLayout()
            return true
        case .paste(let types, let run):
            guard selector == _StandardSelector.paste else { return false }
            let providers = runtime.pasteboardProviders(for: types)
            guard !providers.isEmpty, run(providers) else { return false }
            runtime.requestLayout()
            return true
        }
    }
    override package var nodeDescription: String { "Command" }
}

/// The type identifiers that carry text.
private let textTypeIdentifiers: Set<String> = ["public.utf8-plain-text", "public.plain-text", "public.text", "public.item", "public.data", "public.content"]

extension Runtime {
    /// Sends a command to the focused view and its ancestors, then (nothing focused, or none of
    /// them handling it) to the first handler in the tree. Returns whether one performed it.
    @discardableResult
    public func performCommand(_ selector: Selector) -> Bool {
        if let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) {
            var current: ViewNode? = focused
            while let node = current {
                if let handler = node as? any _EditCommandHandling, handler.performCommand(selector, runtime: self) { setNeedsDisplay(); return true }
                current = node.parent
            }
        }
        for handler in root.descendants(where: { $0 is any _EditCommandHandling }).compactMap({ $0 as? any _EditCommandHandling }) {
            if handler.performCommand(selector, runtime: self) { setNeedsDisplay(); return true }
        }
        return false
    }

    /// The standard selector an edit key stands for (⌘C copy:, ⌘X cut:, ⌘V paste:, ⌘A
    /// selectAll:, ⌘Z undo:, ⇧⌘Z redo:).
    package func standardSelector(for press: KeyPress) -> Selector? {
        let modifiers = press.modifiers.shortcutModifiers
        switch (press.key, modifiers) {
        case (KeyEquivalent("c"), [.command]): return _StandardSelector.copy
        case (KeyEquivalent("x"), [.command]): return _StandardSelector.cut
        case (KeyEquivalent("v"), [.command]): return _StandardSelector.paste
        case (KeyEquivalent("a"), [.command]): return _StandardSelector.selectAll
        case (KeyEquivalent("z"), [.command]): return _StandardSelector.undo
        case (KeyEquivalent("z"), [.command, .shift]), (KeyEquivalent("Z"), [.command, .shift]): return _StandardSelector.redo
        default: return nil
        }
    }

    /// Puts the providers' text on the pasteboard (loaded asynchronously on Apple platforms).
    package func setPasteboard(providers: [NSItemProvider]) {
        _loadText(from: providers) { [weak self] text in
            guard let self, let text else { return }
            self.setPasteboard([_TransferItem(text)])
        }
    }

    /// The pasteboard's text as a provider, when `types` (empty for any) include a text type.
    package func pasteboardProviders(for types: [String]) -> [NSItemProvider] {
        guard let text = pasteboardText, types.isEmpty || types.contains(where: textTypeIdentifiers.contains) else { return [] }
        #if !canImport(Darwin)
        return [NSItemProvider(object: text)]
        #else
        return [NSItemProvider(object: text as NSString)]
        #endif
    }
}

/// The first string the providers carry, to `completion` on the main actor.
@MainActor
package func _loadText(from providers: [NSItemProvider], completion: @escaping @MainActor (String?) -> Void) {
    #if !canImport(Darwin)
    completion(providers.lazy.compactMap { $0._text }.first)
    #else
    nonisolated(unsafe) let completion = completion   // runs on the main actor; Swift 5 mode (decision 0027)
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { completion(nil); return }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        let text = (object as? NSString).map { $0 as String }
        Task { @MainActor in completion(text) }
    }
    #endif
}
