// The runtime's frame: the laid-out tree painted into a display list (`PaintContext` is in
// WebGraphics/Display/PaintContext.swift).

extension Runtime {
    /// Paints the laid-out tree into a display list at `scale` pixels per point.
    public func render(scale: CGFloat = 2) -> DisplayList { render(scale: scale, keepingSegments: false) }

    /// `render(scale:)` for a host whose painter keeps segments: each clipping scroll view's
    /// content is stored as one, and painted again moved (`reuseSegment`) while it only scrolled
    /// (new-website#286). The host paints every list this returns, in order.
    public func renderKeepingSegments(scale: CGFloat) -> DisplayList {
        segmentFrame &+= 1
        return render(scale: scale, keepingSegments: true)
    }

    private func render(scale: CGFloat, keepingSegments: Bool) -> DisplayList {
        guard let phone = drawnPhone else { return renderApp(scale: scale, keepingSegments: keepingSegments) }
        // Inside the drawn iPhone: the app's own list among the phone's places. Stored segments
        // only while the app fills the screen unmoved (a card or a zoom moves what they hold).
        let still = phone.appIsFull && phone.coverAmount == 0
        let app = phone.appIsSeen ? renderApp(scale: scale, keepingSegments: keepingSegments && still) : DisplayList()
        var list = DisplayList()
        phone.compose(app: app, into: &list)
        return list
    }

    private func renderApp(scale: CGFloat, keepingSegments: Bool) -> DisplayList {
        recordingSegments = keepingSegments
        defer { recordingSegments = false }
        // The root's profile is current from the first node on: a node whose paint override
        // skips the base selection (pickers) otherwise reads whatever table was last used.
        let previousMetrics = PlatformMetrics.select(rootEnvironment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        hostElementsThisFrame = []
        defer { hostElementsLastFrame = hostElementsThisFrame }
        if paintsWindowBackground {
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: layoutSize)), rootEnvironment._windowBackground))
        }
        for node in root.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
        toolbar?.paint(into: &list, context: context)
        paintPresentations(into: &list, context: context)
        if systemKeyboard.isVisible { systemKeyboard.paint(into: &list, context: context) }
        paintFocusRing(into: &list, context: context)
        paintTooltip(into: &list, context: context)
        // The dragged copy paints its views a second time, elsewhere: never as their segments.
        recordingSegments = false
        paintDragPreview(into: &list, context: context)
        return list
    }
}
