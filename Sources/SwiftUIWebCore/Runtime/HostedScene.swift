#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
// The runtime as the hosts see it (WebGraphics `HostedScene`, decision 0014): the canvas,
// AppKit and headless hosts drive a SwiftUI runtime and a UIKit scene through the same calls.

extension Runtime: HostedScene {
    /// The host's frame request (the scheduler's flush hook).
    public var onNeedsFrame: (@MainActor @Sendable () -> Void)? {
        get { scheduler.onNeedsFlush }
        set { scheduler.onNeedsFlush = newValue }
    }

    /// Advances scroll momentum and the animation clock before a frame.
    public func advanceFrame(elapsed: Double) -> Bool {
        var animating = advanceScrollAnimations(elapsed: elapsed)
        if advanceAnimations(elapsed: elapsed) { animating = true }
        if !platformHosts.isEmpty, advancePlatformHosts(elapsed: elapsed) { animating = true }
        if let phone = drawnPhone, phone.advance(elapsed: elapsed) { animating = true }
        return animating
    }

    // MARK: The drawn iPhone (new-website#651)

    public var drawsPhone: Bool {
        get { drawnPhone != nil }
        set {
            guard newValue != (drawnPhone != nil) else { return }
            if newValue {
                let phone = DrawnPhone(runtime: self)
                drawnPhone = phone
                phone.reset()
            } else {
                drawnPhone = nil
            }
            phoneDidChange()
        }
    }

    public var phoneClock: (@MainActor @Sendable () -> (time: String, date: String))? {
        get { drawnPhone?.clock }
        set {
            drawnPhone?.clock = newValue
            drawnPhone?.readClock()
        }
    }

    public var phoneAppName: String {
        get { drawnPhone?.appName ?? "" }
        set { drawnPhone?.appName = newValue }
    }

    public func phoneSideButtonPressed() {
        drawnPhone?.sideButton()
    }

    public func phoneClockTick() {
        if drawnPhone?.readClock() == true { requestRepaint() }
    }

    public func phoneDebug(_ action: String) -> String {
        guard let phone = drawnPhone else { return "" }
        switch action {
        case "banner": phone.showBanner()
        case "side": phone.sideButton()
        default: break
        }
        return phone.debugDescription + "\nscenePhase=\(scenePhase)"
    }

    /// Animations begun in this frame start when it is shown (`HostedScene`).
    public func commitAnimations(lateness: Double) { beginAnimationsOnScreen(lateness: lateness) }

    /// The device's safe area as the host reports it (top, leading, bottom, trailing).
    public var hostSafeAreaInsets: [CGFloat] {
        get { [safeAreaInsets.top, safeAreaInsets.leading, safeAreaInsets.bottom, safeAreaInsets.trailing] }
        set {
            guard newValue.count == 4 else { return }
            safeAreaInsets = EdgeInsets(top: newValue[0], leading: newValue[1], bottom: newValue[2], trailing: newValue[3])
        }
    }

    /// The last `navigationTitle` applied in the tree.
    public var windowTitle: String? { navigationTitle }

    /// The host's URL: delivered to the `onOpenURL` handlers.
    public func handleOpenURL(_ url: String) {
        guard let parsed = URL(string: url) else { return }
        openURL(parsed)
    }

    /// The pointer style of the deepest hovered `pointerStyle` view, as a CSS cursor name.
    public var pointerCursor: String? { pointerStyle?.css }

    /// The host's colour chooser picked for a well: the well sets its binding.
    public func colorPanel(_ identifier: Int, didPick color: RGBA) {
        guard let well = colorWell(identifier) else { return }
        well.panelDidPick(color)
    }

    /// The host's colour chooser closed: the well is no longer active.
    public func colorPanelDidClose(_ identifier: Int) {
        colorWell(identifier)?.panelDidClose()
    }

    private func colorWell(_ identifier: Int) -> ColorWellNode? {
        root.descendants(where: { ($0 as? ColorWellNode)?.wellIdentifier == identifier }).first as? ColorWellNode
    }
}
