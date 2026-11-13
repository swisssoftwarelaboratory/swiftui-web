// Responder commands (Docs/elements/Keyboard.md): `onCommand` runs an action for a named
// command reaching the focused view or one of its ancestors (the edit keys map to the standard
// selectors: ⌘C `copy:`, ⌘X `cut:`, ⌘V `paste:`, ⌘A `selectAll:`, ⌘Z `undo:`, ⇧⌘Z `redo:`;
// hosts and tests send any through `Runtime.performCommand`); `onCopyCommand`, `onCutCommand`
// and `onPasteCommand` exchange `NSItemProvider`s with the pasteboard.
import WebFoundation

/// A command handler (a class so field reflection ignores the closures).
package final class _EditCommandBox {
    package enum Kind {
        case selector(Selector, (@MainActor () -> Void)?)
        case copy(@MainActor () -> [NSItemProvider])
        case cut(@MainActor () -> [NSItemProvider])
        /// Pastes items of the supported types; returns whether anything was taken.
        case paste(types: [String], run: @MainActor ([NSItemProvider]) -> Bool)
    }
    package let kind: Kind
    package init(_ kind: Kind) { self.kind = kind }
}

public struct _EditCommandModifier {
    package let box: _EditCommandBox
}

extension _EditCommandModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EditCommandNode(context)
    }
}

extension View {
    /// Performs `action` when the command named by `selector` reaches the view (nil disables it).
    nonisolated public func onCommand(_ selector: Selector, perform action: (@MainActor () -> Void)?) -> some View {
        modifier(_EditCommandModifier(box: _EditCommandBox(.selector(selector, action))))
    }

    /// Puts the returned items on the pasteboard for the Copy command (⌘C) while the view is in
    /// the focused chain.
    nonisolated public func onCopyCommand(perform payload: @escaping @MainActor () -> [NSItemProvider]) -> some View {
        modifier(_EditCommandModifier(box: _EditCommandBox(.copy(payload))))
    }

    /// Puts the returned items on the pasteboard for the Cut command (⌘X).
    nonisolated public func onCutCommand(perform payload: @escaping @MainActor () -> [NSItemProvider]) -> some View {
        modifier(_EditCommandModifier(box: _EditCommandBox(.cut(payload))))
    }

    /// Takes the pasteboard's items of the supported types for the Paste command (⌘V).
    nonisolated public func onPasteCommand(of supportedContentTypes: [UTType], perform payloadAction: @escaping @MainActor ([NSItemProvider]) -> Void) -> some View {
        nonisolated(unsafe) let payloadAction = payloadAction   // Swift 5 mode (decision 0027)
        return modifier(_EditCommandModifier(box: _EditCommandBox(.paste(types: supportedContentTypes.map(\.identifier), run: { payloadAction($0); return true }))))
    }

    /// Takes the pasteboard's items the validator accepts for the Paste command.
    nonisolated public func onPasteCommand<Payload>(of supportedContentTypes: [UTType], validator: @escaping @MainActor ([NSItemProvider]) -> Payload?,
                                                     perform payloadAction: @escaping @MainActor (Payload) -> Void) -> some View {
        nonisolated(unsafe) let validator = validator, payloadAction = payloadAction   // Swift 5 mode (decision 0027)
        return modifier(_EditCommandModifier(box: _EditCommandBox(.paste(types: supportedContentTypes.map(\.identifier), run: { items in
            guard let payload = validator(items) else { return false }
            payloadAction(payload)
            return true
        }))))
    }

    /// The older form naming the types by identifier.
    nonisolated public func onPasteCommand(of supportedTypes: [String], perform payloadAction: @escaping @MainActor ([NSItemProvider]) -> Void) -> some View {
        nonisolated(unsafe) let payloadAction = payloadAction   // Swift 5 mode (decision 0027)
        return modifier(_EditCommandModifier(box: _EditCommandBox(.paste(types: supportedTypes, run: { payloadAction($0); return true }))))
    }

    nonisolated public func onPasteCommand<Payload>(of supportedTypes: [String], validator: @escaping @MainActor ([NSItemProvider]) -> Payload?,
                                                     perform payloadAction: @escaping @MainActor (Payload) -> Void) -> some View {
        nonisolated(unsafe) let validator = validator, payloadAction = payloadAction   // Swift 5 mode (decision 0027)
        return modifier(_EditCommandModifier(box: _EditCommandBox(.paste(types: supportedTypes, run: { items in
            guard let payload = validator(items) else { return false }
            payloadAction(payload)
            return true
        }))))
    }
}
