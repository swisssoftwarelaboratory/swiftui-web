#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// The app's own home screen widgets on the drawn iPhone (new-website#638, its look in #626): each
// is the app's widget code running live in a tree of its own (`_HostedTree`), at the top of the
// home screen across the width with the app's name under it, the apps moved down below. They sit
// on the home screen's grid as on iOS: a small widget takes two columns and two rows, a medium
// one four columns and two rows, a large one four columns and four rows. A tap opens the app out
// of the widget. An app without any shows none.

/// The sizes of a home screen widget, as WidgetKit's system families name them.
public enum _PhoneWidgetSize: Sendable {
    case small, medium, large
}

/// One of the app's home screen widgets, as WidgetKit hands it to the drawn iPhone.
@MainActor
public struct _PhoneWidget {
    public let tree: _HostedTree
    public let size: _PhoneWidgetSize
    public init(tree: _HostedTree, size: _PhoneWidgetSize) {
        self.tree = tree
        self.size = size
    }
}

extension _DrawnPhoneSystem {
    /// Makes the app's widgets for the phone the first time it needs them: its home screen
    /// widgets and its lock screen widgets (set by WidgetKit when the app has a widget extension).
    nonisolated(unsafe) public static var widgetSource: (@MainActor () -> (home: [_PhoneWidget], lock: [_HostedTree]))?
}

extension DrawnPhone {
    /// The widget sizes on the iPhone 16's 393 point wide screen.
    static func widgetSize(_ size: _PhoneWidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 338, height: 158)
        case .large: CGSize(width: 338, height: 354)
        }
    }

    static let widgetCorner: CGFloat = 22
    /// The home screen has six rows; the dock's four sit below them.
    static let homeRows = 6

    /// The app's home screen widgets, made the first time the phone needs them.
    var homeWidgets: [_PhoneWidget] {
        loadWidgets()
        return loadedHomeWidgets
    }

    func loadWidgets() {
        guard !widgetsLoaded else { return }
        widgetsLoaded = true
        guard let made = _DrawnPhoneSystem.widgetSource?() else { return }
        loadedHomeWidgets = made.home
        for widget in made.home {
            widget.tree.onNeedsRepaint = { [weak self] in
                guard let self, self.homeIsSeen else { return }
                self.runtime.requestRepaint()
            }
        }
        if !made.lock.isEmpty { setLockScreenWidgets(made.lock) }
        layoutWidgets()
    }

    /// Whether any of the home screen shows this frame.
    var homeIsSeen: Bool { mode == .home || behind == .home || !cardShown || !appIsFull }

    /// Places the widgets on the grid, in the app's order, filling each row pair left to right
    /// (two small widgets side by side); returns how many rows they take.
    func layoutWidgets() {
        var rects: [CGRect] = []
        var row = 0
        var column = 0          // 0 or 2: where the next small widget goes in the current pair
        var pairRows = 0        // rows the current pair takes
        for widget in loadedHomeWidgets {
            let size = Self.widgetSize(widget.size)
            if widget.size == .small {
                if column == 2 {
                    rects.append(widgetRect(size: size, row: row, column: 2))
                    row += pairRows
                    column = 0
                    pairRows = 0
                    continue
                }
                guard row + 2 <= Self.homeRows - 1 else { break }
                rects.append(widgetRect(size: size, row: row, column: 0))
                column = 2
                pairRows = 2
                continue
            }
            if column == 2 { row += pairRows; column = 0; pairRows = 0 }
            let rows = widget.size == .large ? 4 : 2
            guard row + rows <= Self.homeRows - 1 else { break }
            rects.append(widgetRect(size: size, row: row, column: 0))
            row += rows
        }
        if column == 2 { row += pairRows }
        widgetRects = rects
        widgetRows = row
    }

    private func widgetRect(size: CGSize, row: Int, column: Int) -> CGRect {
        CGRect(x: Self.iconColumns[column] * width / 393, y: Self.iconTop + Double(row) * Self.iconRowStep,
               width: size.width, height: size.height)
    }

    /// The home screen's widgets with where they stand.
    package var placedWidgets: [(widget: _PhoneWidget, rect: CGRect)] {
        loadWidgets()
        return zip(loadedHomeWidgets, widgetRects).map { ($0, $1) }
    }

    /// How many icons fit under the widgets (the app's first, then the made-up ones), up to 12.
    package var homeIconCount: Int {
        loadWidgets()
        return min(12, max(1, (Self.homeRows - widgetRows) * 4))
    }

    /// The widget under a point on the home screen.
    func widget(at point: CGPoint) -> CGRect? {
        placedWidgets.first { $0.rect.contains(point) }?.rect
    }

    /// Moves the widgets' own animations on; returns whether any still moves.
    func advanceWidgets(elapsed: Double) -> Bool {
        var moving = false
        for widget in loadedHomeWidgets where widget.tree.advance(elapsed: elapsed) { moving = true }
        if moving, homeIsSeen { runtime.requestRepaint() }
        return moving && homeIsSeen
    }

    /// Paints each widget, live, with the app's name under it.
    func paintWidgets(into list: inout DisplayList) {
        let label = phoneFont(size: 12, weight: .regular)
        for (widget, rect) in placedWidgets {
            widget.tree.setFixedSize(rect.size)
            widget.tree.layout(width: rect.width)
            list.append(.save)
            list.append(.clipRRect(rect, cornerRadius: Self.widgetCorner))
            list.append(.fillRect(rect, Self.white))
            widget.tree.paint(into: &list, at: rect.origin, scale: 3)
            list.append(.restore)
            drawHomeLabel(homeName, font: label, centerX: rect.midX, baseline: rect.maxY + 17, maxWidth: rect.width, into: &list)
        }
    }

    private func drawHomeLabel(_ text: String, font: ResolvedFont, centerX: CGFloat, baseline: CGFloat, maxWidth: CGFloat, into list: inout DisplayList) {
        let layout = runtime.layoutText(text, font: font, width: nil)
        let width = layout.lines.first?.inkWidth ?? layout.size.width
        list.append(.drawText(text, DisplayFont(font), origin: CGPoint(x: centerX - min(width, maxWidth) / 2, y: baseline), Self.ink))
    }
}
