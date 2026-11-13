// UIViewController (Docs/elements/UIKit/UIViewController.md): view loading, the appearance
// and layout callbacks, and containment.
import WebFoundation   // NSCoder, for init?(coder:)

/// An object that manages a view hierarchy for your UIKit app.
@preconcurrency @MainActor
open class UIViewController: UIResponder, UITraitEnvironment, UITraitChangeObservable {
    /// Focus moved to or from a view of this controller (Events/Keyboard.swift).
    open func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {}

    public init(nibName: String? = nil, bundle: Any? = nil) {
        super.init()
    }

    public override convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    /// A controller from an archive. The web has no storyboards, so it is a controller with no
    /// nib, as `init(nibName: nil, bundle: nil)` makes. UIKit's own subclasses return nil here.
    public required init?(coder: NSCoder) {
        super.init()
    }

    // MARK: The view

    private var _view: UIView?

    /// The controller's view, loaded on first access.
    open var view: UIView! {
        get {
            loadViewIfNeeded()
            return _view
        }
        set {
            _view?.owningViewController = nil
            _view = newValue
            newValue?.owningViewController = self
        }
    }

    open var viewIfLoaded: UIView? { _view }
    open var isViewLoaded: Bool { _view != nil }

    open func loadViewIfNeeded() {
        guard _view == nil else { return }
        loadView()
        if _view == nil { _view = UIView(frame: UIScreen.main.bounds) }
        _view?.owningViewController = self
        viewDidLoad()
    }

    /// Creates the view the controller manages. The default makes a plain view.
    open func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view = view
    }

    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewIsAppearing(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    // `@objc dynamic` with the runtime: apps override it in an extension
    // (`extension UINavigationController { open override func viewWillLayoutSubviews() }`), as
    // UIKit's Objective-C methods allow; containers do their own layout in
    // `layoutContainedViews()`, so such an override replaces nothing of theirs.
    #if _runtime(_ObjC)
    @objc dynamic open func viewWillLayoutSubviews() {}
    #else
    open func viewWillLayoutSubviews() {}
    #endif
    /// A container's own layout of its bars and children, after `viewWillLayoutSubviews()`.
    func layoutContainedViews() {}
    open func viewDidLayoutSubviews() {}
    open func viewSafeAreaInsetsDidChange() {}
    open func viewLayoutMarginsDidChange() {}
    open func didReceiveMemoryWarning() {}

    open var title: String?
    open var preferredContentSize = CGSize.zero
    open var additionalSafeAreaInsets = UIEdgeInsets.zero
    /// The minimum margins of the root view (16 sideways on an iPhone, the safe area vertically)
    /// that its `layoutMarginsGuide` respects unless `viewRespectsSystemMinimumLayoutMargins` is off.
    open var systemMinimumLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    open var viewRespectsSystemMinimumLayoutMargins = true { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var edgesForExtendedLayout: UIRectEdge = .all
    open var modalPresentationStyle: UIModalPresentationStyle = .automatic
    open var modalTransitionStyle: UIModalTransitionStyle = .coverVertical
    /// Supplies custom animators for the controller's presentation and dismissal.
    open weak var transitioningDelegate: (any UIViewControllerTransitioningDelegate)?

    private var _presentationController: UIPresentationController?

    /// The controller managing the presentation: a sheet controller for the sheet styles (the
    /// iPhone's `automatic`), a popover controller for `popover` and action sheets.
    open var presentationController: UIPresentationController? {
        if let existing = _presentationController { return existing }
        let created: UIPresentationController?
        switch modalPresentationStyle {
        case .popover: created = UIPopoverPresentationController(presentedViewController: self, presenting: presentingViewController)
        case .pageSheet, .formSheet, .automatic: created = UISheetPresentationController(presentedViewController: self, presenting: presentingViewController)
        case .custom where self is UIAlertController: created = UIPopoverPresentationController(presentedViewController: self, presenting: presentingViewController)
        default: created = nil
        }
        _presentationController = created
        return created
    }

    open var sheetPresentationController: UISheetPresentationController? { presentationController as? UISheetPresentationController }
    open var popoverPresentationController: UIPopoverPresentationController? { presentationController as? UIPopoverPresentationController }
    open var isModalInPresentation = false
    open var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified {
        didSet { viewIfLoaded?.overrideUserInterfaceStyle = overrideUserInterfaceStyle }
    }

    /// The window the controller's view is in (set by the window for its root).
    weak var window: UIWindow?
    /// The container a presentation put this controller's view in (Containers/UIAlertController.swift).
    var presentationContainer: UIView?
    /// The bar items (Containers/BarItems.swift).
    var storedNavigationItem: UINavigationItem?
    var storedTabBarItem: UITabBarItem?
    open var hidesBottomBarWhenPushed = false
    /// The items a navigation controller's toolbar shows for this controller.
    open var toolbarItems: [UIBarButtonItem]? { didSet { (parent as? UINavigationController)?.toolbarItemsDidChange(for: self) } }
    open func setToolbarItems(_ items: [UIBarButtonItem]?, animated: Bool) { toolbarItems = items }

    override open var next: UIResponder? { _view?.superview ?? parent ?? window }

    open var traitCollection: UITraitCollection { _view?.traitCollection ?? UIScreen.main.traitCollection }
    /// Called with the view's when the view's traits change (the window's style, an override
    /// above it, the host's scheme or size).
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
    /// Observers registered with `registerForTraitChanges` (UITraitChangeObservable).
    public var traitChangeObservers: [TraitChangeObserver] = []

    // MARK: Appearance

    var hasAppeared = false
    var pendingAppearance = false

    /// Tells the controller its view is about to appear or disappear (containers call this).
    open func beginAppearanceTransition(_ isAppearing: Bool, animated: Bool) {
        if isAppearing {
            loadViewIfNeeded()
            viewWillAppear(animated)
            for child in children { child.beginAppearanceTransition(true, animated: animated) }
        } else {
            viewWillDisappear(animated)
            for child in children { child.beginAppearanceTransition(false, animated: animated) }
        }
        appearing = isAppearing
    }

    private var appearing = false

    open func endAppearanceTransition() {
        if appearing {
            hasAppeared = true
            viewDidAppear(false)
        } else {
            hasAppeared = false
            viewDidDisappear(false)
        }
        for child in children { child.endAppearanceTransition() }
    }

    func completeAppearanceIfPending() {
        guard pendingAppearance else { return }
        pendingAppearance = false
        viewIsAppearing(false)
        endAppearanceTransition()
    }

    // MARK: Containment

    public private(set) var children: [UIViewController] = []
    public private(set) weak var parent: UIViewController?

    open func addChild(_ child: UIViewController) {
        child.removeFromParent()
        child.willMove(toParent: self)
        children.append(child)
        child.parent = self
        if hasAppeared { child.beginAppearanceTransition(true, animated: false); child.pendingAppearance = true }
    }

    open func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        self.parent = nil
        didMove(toParent: nil)
    }

    open func willMove(toParent parent: UIViewController?) {}
    open func didMove(toParent parent: UIViewController?) {
        if parent != nil { completeAppearanceIfPending() }
    }

    open var shouldAutomaticallyForwardAppearanceMethods: Bool { true }

    /// Shows a controller the way the hierarchy wants: a navigation controller pushes it, a
    /// split view controller takes it (`UISplitViewController`), anything else asks its parent
    /// or presents it.
    open func show(_ vc: UIViewController, sender: Any?) {
        if let navigation = self as? UINavigationController { navigation.pushViewController(vc, animated: true); return }
        if let parent { parent.show(vc, sender: sender) } else { present(vc, animated: true) }
    }

    /// Shows a detail controller: a split view controller's secondary takes it.
    open func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        if let parent { parent.showDetailViewController(vc, sender: sender) } else { show(vc, sender: sender) }
    }

    // MARK: Presentation (Phase 3: sheets; the API is accepted so sources compile)

    public private(set) var presentedViewController: UIViewController?
    public private(set) weak var presentingViewController: UIViewController?

    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // UIKit refuses a second presentation from the same controller ("Attempt to present ...
        // which is already presenting ...") and leaves the first in place.
        if let presented = presentedViewController {
            print("UIKitWeb: attempt to present \(type(of: viewControllerToPresent)) on \(type(of: self)) which is already presenting \(type(of: presented)).")
            return
        }
        presentedViewController = viewControllerToPresent
        viewControllerToPresent.presentingViewController = self
        UIKitScene.shared.present(viewControllerToPresent, from: self, animated: flag, completion: completion)
    }

    /// `presentedViewController` clears at once; `completion` (and an alert action's handler)
    /// runs when the dismissal animation ends.
    open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if let presented = presentedViewController {
            presented.presentingViewController = nil
            presentedViewController = nil
            UIKitScene.shared.dismiss(presented, animated: flag, completion: completion)
            return
        } else if let presenter = presentingViewController {
            presenter.dismiss(animated: flag, completion: completion)
            return
        } else if let parent {
            parent.dismiss(animated: flag, completion: completion)
            return
        } else if let hosted = viewIfLoaded?.window as? HostedWindow, let dismiss = hosted.tree?.dismissHandler {
            // Hosted by another framework's presentation: that closes.
            dismiss()
        }
        completion?()
    }
}

public enum UIModalPresentationStyle: Int, Sendable {
    case fullScreen = 0, pageSheet, formSheet, currentContext, custom, overFullScreen, overCurrentContext, popover, none = -1, automatic = -2
}

public enum UIModalTransitionStyle: Int, Sendable {
    case coverVertical = 0, flipHorizontal, crossDissolve, partialCurl
}
