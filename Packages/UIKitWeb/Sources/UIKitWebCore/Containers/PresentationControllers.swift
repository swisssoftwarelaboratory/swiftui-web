// Presentation controllers (Docs/elements/UIKit/Presentation.md): `UISheetPresentationController`
// holds a sheet's detents, grabber and corner radius; `UIPopoverPresentationController` a
// popover's source and arrow directions (a popover adapts to a sheet on the iPhone unless its
// delegate says otherwise). The presentation container reads them when it lays the presented
// view out (Containers/UIAlertController.swift).

/// The delegate of an adaptive presentation (dismissal callbacks and the adapted style).
@preconcurrency @MainActor
public protocol UIAdaptivePresentationControllerDelegate: AnyObject {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController)
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController)
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController)
}

extension UIAdaptivePresentationControllerDelegate {
    public func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .automatic }
    public func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        adaptivePresentationStyle(for: controller)
    }
    public func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { true }
    public func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {}
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {}
    public func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {}
}

extension UIPresentationController {
    /// The presented view's container, once presented.
    public var containerView: UIView? { presentedViewController.presentationContainer }
    public var presentedView: UIView? { presentedViewController.viewIfLoaded }

    /// The delegate hearing of dismissals (a sheet's or a popover's).
    var adaptiveDelegate: (any UIAdaptivePresentationControllerDelegate)? { delegate }
}

/// A sheet's detents, grabber and corners.
@preconcurrency @MainActor
open class UISheetPresentationController: UIPresentationController {
    /// A height a sheet rests at.
    public struct Detent: Hashable, Sendable {
        public struct Identifier: Hashable, Sendable, RawRepresentable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public init(_ rawValue: String) { self.rawValue = rawValue }
            public static let medium = Identifier("com.apple.UIKit.medium")
            public static let large = Identifier("com.apple.UIKit.large")
        }
        public let identifier: Identifier
        /// The height for a custom detent, given the container's maximum detent value.
        /// `@Sendable` spelled out, as this module is in Swift 5 mode (decision 0027).
        package let resolver: (@MainActor @Sendable (CGFloat) -> CGFloat?)?

        package init(identifier: Identifier, resolver: (@MainActor @Sendable (CGFloat) -> CGFloat?)?) {
            self.identifier = identifier
            self.resolver = resolver
        }

        public static func medium() -> Detent { Detent(identifier: .medium, resolver: nil) }
        public static func large() -> Detent { Detent(identifier: .large, resolver: nil) }
        @MainActor
        public static func custom(identifier: Identifier? = nil, resolver: @escaping @MainActor (_ maximumDetentValue: CGFloat) -> CGFloat?) -> Detent {
            customCount += 1
            nonisolated(unsafe) let resolver = resolver
            return Detent(identifier: identifier ?? Identifier("custom-\(customCount)"), resolver: { resolver($0) })
        }
        @MainActor private static var customCount = 0

        public static func == (lhs: Detent, rhs: Detent) -> Bool { lhs.identifier == rhs.identifier }
        public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
    }

    open var detents: [Detent] = [.large()] { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var selectedDetentIdentifier: Detent.Identifier? { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var largestUndimmedDetentIdentifier: Detent.Identifier? { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var prefersGrabberVisible = false { didSet { presentedViewController.presentationContainer?.setNeedsDisplay() } }
    open var preferredCornerRadius: CGFloat? { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var prefersScrollingExpandsWhenScrolledToEdge = true
    open var prefersEdgeAttachedInCompactHeight = false
    open var widthFollowsPreferredContentSizeWhenEdgeAttached = false
    open var prefersPageSizing = true

    /// The detent the sheet rests at: the selected one, else the first.
    var currentDetent: Detent? {
        if let selectedDetentIdentifier, let detent = detents.first(where: { $0.identifier == selectedDetentIdentifier }) { return detent }
        return detents.first
    }

    /// Runs `changes` (detent selection and the like) and lays the sheet out again.
    open func animateChanges(_ changes: () -> Void) {
        changes()
        presentedViewController.presentationContainer?.setNeedsLayout()
    }
}

@preconcurrency @MainActor
public protocol UISheetPresentationControllerDelegate: UIAdaptivePresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController)
}

extension UISheetPresentationControllerDelegate {
    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {}
}

/// The directions a popover's arrow may point.
public struct UIPopoverArrowDirection: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let up = UIPopoverArrowDirection(rawValue: 1 << 0)
    public static let down = UIPopoverArrowDirection(rawValue: 1 << 1)
    public static let left = UIPopoverArrowDirection(rawValue: 1 << 2)
    public static let right = UIPopoverArrowDirection(rawValue: 1 << 3)
    public static let any: UIPopoverArrowDirection = [.up, .down, .left, .right]
    public static let unknown = UIPopoverArrowDirection(rawValue: UInt.max)
}

/// A popover's source and arrow.
@preconcurrency @MainActor
open class UIPopoverPresentationController: UIPresentationController {
    open weak var sourceView: UIView? { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var sourceRect = CGRect.null { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    /// A bar button item (or any item) the popover is anchored to.
    open weak var barButtonItem: UIBarButtonItem? { didSet { presentedViewController.presentationContainer?.setNeedsLayout() } }
    open var permittedArrowDirections: UIPopoverArrowDirection = .any
    open var canOverlapSourceViewRect = false
    open var passthroughViews: [UIView]?
    open var backgroundColor: UIColor?
    open var popoverLayoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    /// The direction the arrow points once presented.
    public internal(set) var arrowDirection: UIPopoverArrowDirection = .unknown

    /// The rectangle the popover points at, in the window.
    func sourceFrame(in window: UIView) -> CGRect? {
        if let sourceView {
            let rect = sourceRect.isNull ? sourceView.bounds : sourceRect
            return sourceView.convert(rect, to: window)
        }
        if let barButtonItem, let platter = window.firstDescendant(where: { ($0 as? BarPlatterButton)?.item === barButtonItem }) {
            return platter.convert(platter.bounds, to: window)
        }
        return nil
    }

    /// Whether the popover stays a popover on the iPhone (the delegate answers `.none`).
    var staysPopover: Bool {
        guard let delegate else { return false }
        return delegate.adaptivePresentationStyle(for: self, traitCollection: presentedViewController.traitCollection) == .none
    }
}

@preconcurrency @MainActor
public protocol UIPopoverPresentationControllerDelegate: UIAdaptivePresentationControllerDelegate {
    func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController)
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController)
}

extension UIPopoverPresentationControllerDelegate {
    public func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {}
    public func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool { true }
    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {}
}

extension UIView {
    /// The first view in the subtree (depth first) satisfying `predicate`.
    func firstDescendant(where predicate: (UIView) -> Bool) -> UIView? {
        for subview in subviews {
            if predicate(subview) { return subview }
            if let found = subview.firstDescendant(where: predicate) { return found }
        }
        return nil
    }
}
