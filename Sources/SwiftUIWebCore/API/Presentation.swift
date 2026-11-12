// `LocalizedError` for the error alerts: WebFoundation's on wasm, Foundation's elsewhere.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// Sheets, popovers, alerts and menus: presented over the window by the runtime's presentation
/// layer (`Docs/elements/Presentation.md`). The looks are approximations: on macOS these are
/// separate windows the hosted golden window cannot capture.

/// An action that dismisses a presentation (or pops the enclosing navigation stack).
public struct DismissAction {
    package let action: @MainActor () -> Void
    package init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

package struct DismissKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = DismissAction {}
}

package struct IsPresentedKey: EnvironmentKey {
    package static let defaultValue = false
}

/// The presentation a view is in, read through `@Environment(\.presentationMode)`.
public struct PresentationMode {
    /// Whether the view is in a presentation.
    public private(set) var isPresented: Bool
    let dismissAction: DismissAction

    init(isPresented: Bool, dismissAction: DismissAction) {
        self.isPresented = isPresented
        self.dismissAction = dismissAction
    }

    /// Dismisses the presentation the view is in (or pops its navigation destination).
    @MainActor public mutating func dismiss() {
        guard isPresented else { return }
        dismissAction()
        isPresented = false
    }
}

package struct DismissesOnActivationKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// An action that dismisses the current presentation.
    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }

    /// Whether the view is in a presentation: a sheet, popover, alert or window, or a
    /// destination pushed onto a navigation stack.
    public package(set) var isPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }

    /// The presentation the view is in, as a binding (the API before `dismiss`, iOS 13).
    public var presentationMode: Binding<PresentationMode> {
        let mode = PresentationMode(isPresented: isPresented, dismissAction: dismiss)
        return Binding(get: { mode }, set: { _ in })
    }

    /// Whether buttons in this environment dismiss the presentation after their action (alerts).
    package var _dismissesOnActivation: Bool {
        get { self[DismissesOnActivationKey.self] }
        set { self[DismissesOnActivationKey.self] = newValue }
    }
}

/// How a presentation is shown.
public enum _PresentationKind: Sendable, Equatable {
    case sheet
    case popover(arrowEdge: Edge, anchor: PopoverAttachmentAnchor)
    case alert
    /// A confirmation dialog: an alert on macOS; on iOS a glass panel above its source.
    case dialog
    case menu
    /// A menu beside the row of a parent menu.
    case submenu
    /// A secondary window (`openWindow`): a floating panel with a title bar, non-modal.
    case window(title: String?, size: CGSize?)

    package var isMenu: Bool { self == .menu || self == .submenu }
    package var isWindow: Bool { if case .window = self { return true } else { return false } }
}

/// Where a popover attaches to its source view.
public enum PopoverAttachmentAnchor: Sendable, Equatable {
    case rect(_AnchorSource)
    case point(UnitPoint)
}

public enum _AnchorSource: Sendable, Equatable {
    case bounds
    case rect(CGRect)
}

/// The modifier behind `sheet`, `popover`, `alert` and friends: its body reads the binding so
/// observation tracks it; `_PresentationSync` presents and dismisses.
public struct _PresentationModifier {
    package let kind: _PresentationKind
    package let isPresented: Binding<Bool>
    package let onDismiss: _DismissBox?
    package let content: _PresentationContentBox
    /// `fullScreenCover`: the sheet fills the window (no card, no dimming) on every profile.
    package var fullScreen = false

    package init(kind: _PresentationKind, isPresented: Binding<Bool>, onDismiss: (() -> Void)?, fullScreen: Bool = false, content: @escaping () -> AnyView) {
        self.kind = kind
        self.isPresented = isPresented
        self.onDismiss = onDismiss.map { _DismissBox($0) }
        self.fullScreen = fullScreen
        self.content = _PresentationContentBox(content)
    }
}

/// Holds an `onDismiss` callback (a class so the runtime's field reflection ignores it).
package final class _DismissBox {
    package let run: () -> Void
    package init(_ run: @escaping () -> Void) { self.run = run }
}

/// Holds a presentation's content builder (a class so the runtime's field reflection ignores
/// it); the runtime calls it on the main actor.
package final class _PresentationContentBox {
    package let make: () -> AnyView
    package init(_ make: @escaping () -> AnyView) { self.make = make }
}

extension _PresentationModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content.modifier(_PresentationSync(kind: kind, presented: isPresented.wrappedValue, binding: isPresented, onDismiss: onDismiss, content: self.content, fullScreen: fullScreen))
    }
}

public struct _PresentationSync {
    package let kind: _PresentationKind
    package let presented: Bool
    package let binding: Binding<Bool>
    package let onDismiss: _DismissBox?
    package let content: _PresentationContentBox
    package var fullScreen = false

    package init(kind: _PresentationKind, presented: Bool, binding: Binding<Bool>, onDismiss: _DismissBox?, content: _PresentationContentBox, fullScreen: Bool = false) {
        self.kind = kind
        self.presented = presented
        self.binding = binding
        self.onDismiss = onDismiss
        self.content = content
        self.fullScreen = fullScreen
    }
}

extension _PresentationSync: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PresentationSyncNode(context)
    }
}

extension View {
    /// Presents a sheet when a binding to a Boolean value that you provide is true.
    nonisolated public func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: isPresented, onDismiss: onDismiss) { AnyView(content()) })
    }

    /// Presents a sheet using the given item as a data source for the sheet's content.
    /// Presents a modal view that covers as much of the screen as possible (iOS: the whole window).
    nonisolated public func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                                           @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: isPresented, onDismiss: onDismiss, fullScreen: true) { AnyView(content()) })
    }

    nonisolated public func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                                               @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: _itemBinding(item), onDismiss: onDismiss, fullScreen: true) {
            item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
        })
    }

    nonisolated public func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(_PresentationModifier(kind: .sheet, isPresented: _itemBinding(item), onDismiss: onDismiss) {
            item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
        })
    }

    /// Presents a popover when a given condition is true.
    nonisolated public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                   arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(_PresentationModifier(kind: .popover(arrowEdge: arrowEdge, anchor: attachmentAnchor), isPresented: isPresented, onDismiss: nil) { AnyView(content()) })
    }

    /// Presents a popover using the given item as a data source for the popover's content.
    nonisolated public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                                                       arrowEdge: Edge = .top, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(_PresentationModifier(kind: .popover(arrowEdge: arrowEdge, anchor: attachmentAnchor), isPresented: _itemBinding(item), onDismiss: nil) {
            item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
        })
    }

    /// Presents an alert with a message when a given condition is true.
    nonisolated public func alert<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A,
                                                    @ViewBuilder message: () -> M) -> some View {
        // Built now, as Apple's non-escaping builders are: the modifier keeps the views.
        let content = AnyView(_AlertContent(title: title, message: AnyView(message()), actions: AnyView(actions())))
        return modifier(_PresentationModifier(kind: .alert, isPresented: isPresented, onDismiss: nil) { content })
    }

    nonisolated public func alert<A: View>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        alert(title, isPresented: isPresented, actions: actions) { EmptyView() }
    }

    nonisolated public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A,
                                                    @ViewBuilder message: () -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    nonisolated public func alert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A,
                                                                        @ViewBuilder message: () -> M) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions) { EmptyView() }
    }

    // MARK: Alerts over data and errors (sw-app-api-gaps)

    /// Presents an alert using the given data to produce the alert's content.
    nonisolated public func alert<A: View, M: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A,
                                                       @ViewBuilder message: (T) -> M) -> some View {
        alert(title, isPresented: isPresented, actions: { if let data { actions(data) } }, message: { if let data { message(data) } })
    }
    nonisolated public func alert<A: View, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        alert(title, isPresented: isPresented, actions: { if let data { actions(data) } })
    }
    nonisolated public func alert<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A,
                                                       @ViewBuilder message: (T) -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }
    nonisolated public func alert<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions)
    }
    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A,
                                                                           @ViewBuilder message: (T) -> M) -> some View {
        alert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }
    @_disfavoredOverload
    nonisolated public func alert<S: StringProtocol, A: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        alert(Text(title), isPresented: isPresented, presenting: data, actions: actions)
    }

    /// Presents an alert when an error is present: the title is the error's description.
    nonisolated public func alert<E: LocalizedError, A: View, M: View>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: (E) -> A,
                                                                       @ViewBuilder message: (E) -> M) -> some View {
        alert(Text(error?.errorDescription ?? ""), isPresented: isPresented, presenting: error, actions: actions, message: message)
    }
    nonisolated public func alert<E: LocalizedError, A: View>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: () -> A) -> some View {
        alert(Text(error?.errorDescription ?? ""), isPresented: isPresented, actions: actions)
    }

    /// Presents a confirmation dialog using the given data to produce its content.
    nonisolated public func confirmationDialog<A: View, M: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
                                                                    @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: { if let data { actions(data) } }, message: { if let data { message(data) } })
    }
    nonisolated public func confirmationDialog<A: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
                                                           @ViewBuilder actions: (T) -> A) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: { if let data { actions(data) } })
    }
    nonisolated public func confirmationDialog<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
                                                                    @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, presenting: data, actions: actions, message: message)
    }
    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
                                                                                        @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, presenting: data, actions: actions, message: message)
    }

    /// Presents a confirmation dialog when a given condition is true: an alert-like panel on
    /// macOS, a glass panel above the source on iOS (`titleVisibility` hides the title).
    nonisolated public func confirmationDialog<A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                 @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        let content = AnyView(_DialogContent(title: titleVisibility == .hidden ? nil : title, message: AnyView(message()), actions: AnyView(actions())))
        return modifier(_PresentationModifier(kind: .dialog, isPresented: isPresented, onDismiss: nil) { content })
    }

    nonisolated public func confirmationDialog<A: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                            @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    @_disfavoredOverload
    nonisolated public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                                     @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
    }

    nonisolated public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                        @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) { EmptyView() }
    }

    nonisolated public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                                                 @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented, titleVisibility: titleVisibility, actions: actions, message: message)
    }

    /// Adds an action to dismiss the presentation from buttons in a subtree (alerts).
    package func _dismissesOnActivation() -> some View { environment(\._dismissesOnActivation, true) }
}

/// A presence binding derived from an optional item: true while the item is non-nil, and
/// setting it to false clears the item.
nonisolated package func _itemBinding<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

/// The alert panel's content: bold title, message, actions in a row; buttons dismiss.
package struct _AlertContent {
    package let title: Text
    package let message: AnyView
    package let actions: AnyView

    package init(title: Text, message: AnyView, actions: AnyView) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

extension _AlertContent: View {
    package var body: some View {
        _AlertBody(title: title, message: message, actions: actions)
    }
}

/// The alert's layout per platform: macOS centres a 13 pt title, an 11 pt secondary message
/// and the buttons in a row inside 20 pt; iOS (ios/alert/basic) left-aligns a 17 pt bold title
/// and a 15 pt message 15 in from the capsule buttons, which share the width, the cancel button
/// first (Docs/elements/iOS.md).
private struct _AlertBody: View {
    let title: Text
    let message: AnyView
    let actions: AnyView
    @Environment(\.platformProfile) private var profile

    var body: some View {
        let m = profile.metrics
        if profile.isIOS {
            VStack(alignment: .leading, spacing: 0) {
                title.font(.system(size: m.alertTitleSize, weight: .bold)).lineSpacing(m.alertTitleLineSpacing).padding(.horizontal, m.alertTextInset).padding(.bottom, m.alertTitleMessageGap)
                message.font(.system(size: m.alertMessageSize)).foregroundStyle(m.alertPlainButtonColorIsAccent ? Color.primary : Color.secondary).padding(.horizontal, m.alertTextInset)
                // Two buttons share a row (4 further in on iOS 27); one or three or more stack.
                _AlertActionsLayout(vertical: false, spacing: m.alertButtonGap, stackedSpacing: m.alertStackedButtonGap, rowInset: m.alertRowButtonInset, height: m.alertButtonHeight) { actions }
                    .buttonStyle(_AlertButtonStyle(height: m.alertButtonHeight, fillAlpha: m.alertButtonFillAlpha, destructive: m.alertDestructiveColor, size: m.alertTitleSize, dialog: false,
                                                   cancelFilled: m.alertCancelFilled, plainIsAccent: m.alertPlainButtonColorIsAccent))
                    ._dismissesOnActivation()
                    .padding(.top, m.alertMessageButtonsGap)
            }
            .padding(m.alertInsets)
            .frame(width: m.alertWidth)
        } else {
            // macOS 27 (presentation/mac-alert): the 13 pt bold title 20.5 from the top, the 13 pt
            // message 13 below it, both centred; 17.5 below, 28 pt capsule buttons sharing the
            // width 8 apart 16 from the sides (the cancel role first, the destructive one on a
            // pink fill with red text), 16.5 from the bottom.
            VStack(spacing: 0) {
                title.font(.system(size: 13).bold()).multilineTextAlignment(.center).padding(.bottom, m.alertMacTitleMessageGap)
                message.font(.system(size: 13)).multilineTextAlignment(.center)
                _AlertActionsLayout(vertical: false, spacing: m.alertMacButtonGap, stackedSpacing: m.alertMacButtonGap, rowInset: 0, height: m.alertMacButtonHeight) { actions }
                    .buttonStyle(_MacAlertButtonStyle(height: m.alertMacButtonHeight))
                    ._dismissesOnActivation()
                    .padding(.top, m.alertMacMessageButtonsGap)
            }
            .padding(EdgeInsets(top: m.alertMacTopInset, leading: m.alertMacSideInset, bottom: m.alertMacBottomInset, trailing: m.alertMacSideInset))
            .frame(width: m.alertWidth)
        }
    }
}

/// macOS 27 alert buttons: capsules on a grey fill, the destructive role on pink with red text.
package struct _MacAlertButtonStyle: ButtonStyle {
    let height: CGFloat
    @Environment(\.platformProfile) private var profile

    package func makeBody(configuration: Configuration) -> some View {
        let m = profile.metrics
        let destructive = configuration.role == .destructive
        let fill = destructive ? m.alertMacDestructiveFill : m.alertMacButtonFill
        let color: Color = destructive ? Color(red: m.alertDestructiveColor.red, green: m.alertDestructiveColor.green, blue: m.alertDestructiveColor.blue) : .primary
        return configuration.label
            .font(.system(size: 13))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Capsule().fill(Color(red: fill.red, green: fill.green, blue: fill.blue)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A confirmation dialog's content: the alert's on macOS; on iOS (ios/dialog/basic) a 17 pt
/// bold title, a 17 pt message and the actions stacked as full-width capsules, cancel buttons
/// left out (the panel dismisses on a tap outside).
package struct _DialogContent {
    package let title: Text?
    package let message: AnyView
    package let actions: AnyView
    @Environment(\.platformProfile) private var profile

    package init(title: Text?, message: AnyView, actions: AnyView) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

extension _DialogContent: View {
    package var body: some View {
        let m = profile.metrics
        if profile.isIOS {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    title.font(.system(size: m.dialogTitleSize, weight: .bold)).padding(.horizontal, m.dialogTextInset).padding(.bottom, m.dialogTitleMessageGap)
                }
                message.font(.system(size: m.dialogMessageSize)).foregroundStyle(m.alertPlainButtonColorIsAccent ? Color.primary : Color.secondary).padding(.horizontal, m.dialogTextInset)
                _AlertActionsLayout(vertical: true, spacing: m.dialogButtonGap, stackedSpacing: m.dialogButtonGap, rowInset: 0, height: m.dialogButtonHeight) { actions }
                    .buttonStyle(_AlertButtonStyle(height: m.dialogButtonHeight, fillAlpha: m.dialogButtonFillAlpha, destructive: m.alertDestructiveColor, size: m.dialogTitleSize, dialog: true,
                                                   cancelFilled: m.alertCancelFilled, plainIsAccent: m.alertPlainButtonColorIsAccent))
                    ._dismissesOnActivation()
                    .padding(.top, m.dialogMessageButtonsGap)
            }
            .padding(m.dialogInsets)
            .frame(width: m.dialogWidth)
        } else {
            _AlertBody(title: title ?? Text(""), message: message, actions: actions)
        }
    }
}

/// The role of an alert action, read by `_AlertActionsLayout`.
package struct _ButtonRoleKey: LayoutValueKey {
    package static let defaultValue: ButtonRole? = nil
}

/// iOS alert and dialog buttons: capsules. The cancel role fills with the accent under a bold
/// white label, the destructive role shows red, the rest the accent (alerts) or the primary
/// colour (dialogs) on a grey fill.
package struct _AlertButtonStyle: ButtonStyle {
    let height: CGFloat
    let fillAlpha: Double
    let destructive: RGBA
    let size: CGFloat
    let dialog: Bool
    /// iOS 26 filled the cancel button with the accent under white and drew plain buttons in
    /// the accent; iOS 27 draws every button on the grey capsule, cancel bold, in the primary colour.
    var cancelFilled = true
    var plainIsAccent = true

    package func makeBody(configuration: Configuration) -> some View {
        let cancel = configuration.role == .cancel && !dialog
        let filled = cancel && cancelFilled
        let color: Color = configuration.role == .destructive ? Color(red: destructive.red, green: destructive.green, blue: destructive.blue)
            : filled ? .white : dialog || !plainIsAccent ? .primary : .accentColor
        return configuration.label
            .font(.system(size: size, weight: cancel ? .semibold : .regular))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Capsule().fill(filled ? Color.accentColor : Color.black.opacity(fillAlpha)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Places alert actions: in a row sharing the width with the cancel button first, or stacked
/// full width with cancel buttons left out (iOS dialogs).
package struct _AlertActionsLayout: Layout {
    /// Always stacked (dialogs); a row otherwise — but only for exactly two buttons: one, or
    /// three and more, stack too (iOS 27), the cancel button last.
    let vertical: Bool
    let spacing: CGFloat
    let stackedSpacing: CGFloat
    /// A row's extra inset at each side (iOS 27: 4).
    let rowInset: CGFloat
    let height: CGFloat

    private func shown(_ subviews: Subviews) -> [Subviews.Element] {
        let ordered = subviews.sorted { ($0[_ButtonRoleKey.self] == .cancel ? 0 : 1) < ($1[_ButtonRoleKey.self] == .cancel ? 0 : 1) }
        if vertical { return ordered.filter { $0[_ButtonRoleKey.self] != .cancel } }
        // A stack of three or more puts the cancel button last.
        return ordered.count == 2 ? ordered : Array(ordered.dropFirst(ordered.first.map { $0[_ButtonRoleKey.self] == .cancel } == true ? 1 : 0)) + ordered.prefix(ordered.first.map { $0[_ButtonRoleKey.self] == .cancel } == true ? 1 : 0)
    }

    private func stacks(_ count: Int) -> Bool { vertical || count != 2 }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = shown(subviews).count
        guard count > 0 else { return .zero }
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
        return CGSize(width: width, height: stacks(count) ? CGFloat(count) * height + CGFloat(count - 1) * stackedSpacing : height)
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let visible = shown(subviews)
        let hidden = subviews.filter { subview in !visible.contains { $0 == subview } }
        for subview in hidden { subview.place(at: bounds.origin, proposal: ProposedViewSize(width: 0, height: 0)) }
        guard !visible.isEmpty else { return }
        if stacks(visible.count) {
            var y = bounds.minY
            for subview in visible {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + stackedSpacing
            }
        } else {
            let available = bounds.width - 2 * rowInset
            let width = (available - spacing * CGFloat(visible.count - 1)) / CGFloat(visible.count)
            var x = bounds.minX + rowInset
            for subview in visible {
                subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: height))
                x += width + spacing
            }
        }
    }
}

/// A pop-up picker's menu: one row per option, the selected one checked; a press selects and dismisses.
package struct _MenuList: View {
    /// A row of a pop-up's menu: an option (by its index among the options), a separator or a
    /// section header.
    package enum Entry: Hashable {
        case option(title: String, index: Int)
        case divider
        case header(String)
    }

    package let entries: [Entry]
    package let selected: Int?
    package let select: _MenuSelection

    package init(titles: [String], selected: Int?, select: _MenuSelection) {
        entries = titles.enumerated().map { .option(title: $1, index: $0) }
        self.selected = selected
        self.select = select
    }

    package init(entries: [Entry], selected: Int?, select: _MenuSelection) {
        self.entries = entries
        self.selected = selected
        self.select = select
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .option(let title, let index): _MenuRow(title: title, checked: index == selected, index: index, select: select)
                case .divider: Divider()
                case .header(let title): _MenuSectionHeader(header: AnyView(Text(title)))
                }
            }
        }
        .padding(.vertical, PlatformMetrics.menuVerticalPadding)
        .environment(\._inMenu, true)
    }
}

package struct _MenuRow: View {
    package let title: String
    package let checked: Bool
    package let index: Int
    package let select: _MenuSelection
    @Environment(\.dismiss) private var dismiss

    package var body: some View {
        Button(action: { select.select(index); dismiss() }) {
            HStack(spacing: 0) {
                Text("✓").font(.system(size: 12)).opacity(checked ? 1 : 0).frame(width: PlatformMetrics.menuCheckWidth)
                Text(title).font(.system(size: PlatformMetrics.buttonLabelSize))
            }
            .padding(.trailing, PlatformMetrics.menuTrailingPadding)
            .frame(minWidth: PlatformMetrics.menuMinimumWidth, minHeight: PlatformMetrics.menuRowHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Type-erased menu selection (a class so the runtime's field reflection ignores it).
package final class _MenuSelection {
    package let select: @MainActor (Int) -> Void
    package init(_ select: @escaping @MainActor (Int) -> Void) { self.select = select }
}

// MARK: - Sheet options

/// A height a sheet can rest at (iOS): the full height, half of it, a fraction or a point
/// height. The runtime honours `medium` and `large`; the others resolve to their heights.
public enum PresentationDetent: Hashable, Sendable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

/// How a presentation adapts when the size class is compact (`presentationCompactAdaptation`).
/// As in SwiftUI, only `Sendable`; its cases are told apart by a tag.
public struct PresentationAdaptation: Sendable {
    package let tag: UInt8
    public static let automatic = PresentationAdaptation(tag: 0)
    public static let none = PresentationAdaptation(tag: 1)
    public static let popover = PresentationAdaptation(tag: 2)
    public static let sheet = PresentationAdaptation(tag: 3)
    public static let fullScreenCover = PresentationAdaptation(tag: 4)
}

/// `presentationDetents` and `presentationDragIndicator`: the sheet's options, told to the
/// presentation node above (`PresentationOptionsNode`).
public struct _PresentationOptionsModifier {
    package let detents: Set<PresentationDetent>?
    package let dragIndicator: Visibility?
    package let interactiveDismissDisabled: Bool?
    package let background: AnyShapeStyle?

    package init(detents: Set<PresentationDetent>? = nil, dragIndicator: Visibility? = nil, interactiveDismissDisabled: Bool? = nil,
                 background: AnyShapeStyle? = nil) {
        self.detents = detents
        self.dragIndicator = dragIndicator
        self.interactiveDismissDisabled = interactiveDismissDisabled
        self.background = background
    }
}

extension _PresentationOptionsModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PresentationOptionsNode(context)
    }
}

extension View {
    /// Sets the heights the sheet presenting this view can rest at.
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(_PresentationOptionsModifier(detents: detents, dragIndicator: nil))
    }

    /// Sets the heights and a binding to the selected one (the binding is not written here).
    nonisolated public func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View {
        modifier(_PresentationOptionsModifier(detents: detents, dragIndicator: nil))
    }

    /// Shows or hides the sheet's drag indicator.
    nonisolated public func presentationDragIndicator(_ visibility: Visibility) -> some View {
        modifier(_PresentationOptionsModifier(dragIndicator: visibility))
    }

    /// How a popover or sheet showing this view adapts at compact sizes. The runtime keeps a
    /// popover a popover and a sheet a sheet at every size, which is what `.popover` and
    /// `.none` ask for; the other adaptations show the presentation unchanged.
    nonisolated public func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View { self }

    /// The adaptations for compact widths and heights separately (see the one-argument form).
    nonisolated public func presentationCompactAdaptation(horizontal: PresentationAdaptation, vertical: PresentationAdaptation) -> some View { self }

    /// An inspector: on iOS at compact width a sheet over the content while the binding is
    /// true, which is how the runtime always shows it.
    nonisolated public func inspector<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> V) -> some View {
        sheet(isPresented: isPresented, content: content)
    }

    /// The inspector column's width when it shows as a column; a sheet ignores it.
    nonisolated public func inspectorColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View { self }

    /// The inspector column's width when it shows as a column; a sheet ignores it.
    nonisolated public func inspectorColumnWidth(_ width: CGFloat) -> some View { self }

    /// Keeps the presentation this view is in from being dismissed by a press outside it or
    /// Escape (a swipe on iOS); programmatic dismissal still works.
    nonisolated public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        modifier(_PresentationOptionsModifier(interactiveDismissDisabled: isDisabled))
    }
}

// MARK: - Sheet background and interaction

/// Whether people can interact with the view behind a presentation: always, never, or while
/// the sheet rests at or below a detent.
public struct PresentationBackgroundInteraction: Sendable {
    package enum Kind: Sendable { case automatic, enabled, disabled, enabledUpThrough(PresentationDetent) }
    package let kind: Kind

    /// The default behaviour: the view behind a sheet is disabled.
    public static let automatic = PresentationBackgroundInteraction(kind: .automatic)
    /// People can interact with the view behind the presentation.
    public static let enabled = PresentationBackgroundInteraction(kind: .enabled)
    /// People can't interact with the view behind the presentation.
    public static let disabled = PresentationBackgroundInteraction(kind: .disabled)
    /// People can interact with the view behind the presentation while it rests at or below
    /// `detent`.
    public static func enabled(upThrough detent: PresentationDetent) -> PresentationBackgroundInteraction {
        PresentationBackgroundInteraction(kind: .enabledUpThrough(detent))
    }
}

/// Which behaviour a swipe in a resizable sheet's content has: resizing the sheet or scrolling
/// the content.
public struct PresentationContentInteraction: Equatable, Sendable {
    package let tag: UInt8
    public static let automatic = PresentationContentInteraction(tag: 0)
    public static let resizes = PresentationContentInteraction(tag: 1)
    public static let scrolls = PresentationContentInteraction(tag: 2)
}

extension View {
    /// Sets the presentation background of the enclosing sheet or full-screen cover: the style
    /// fills the card (the cover's whole window) in place of the system background, and `.clear`
    /// lets what is behind show through (an app drawing its own dim and card in a cover).
    nonisolated public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        modifier(_PresentationOptionsModifier(background: AnyShapeStyle(style)))
    }

    /// Sets the presentation background of the enclosing sheet to a custom view. Stored only:
    /// the runtime's sheet keeps its own background.
    nonisolated public func presentationBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }

    /// Controls whether people can interact with the view behind a presentation. The runtime's
    /// sheet always takes the presses outside it, which is the automatic behaviour.
    nonisolated public func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> some View { self }

    /// Configures the behaviour of swipe gestures on a presentation. The runtime's sheet does
    /// not resize by swiping, so its content always scrolls.
    nonisolated public func presentationContentInteraction(_ behavior: PresentationContentInteraction) -> some View { self }

    /// Requests that the presentation have a specific corner radius. Stored only: the runtime's
    /// sheet keeps the platform's radius.
    nonisolated public func presentationCornerRadius(_ cornerRadius: CGFloat?) -> some View { self }
}
