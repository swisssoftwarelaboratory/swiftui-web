#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// What the drawn iPhone paints (new-website#618): the island, the status bar (the viewer's own
// time, full signal, wifi and battery, all drawn by us), the home indicator, and the places
// around the app. The home screen and the lock screen are plain grey stand-ins until their own
// tickets draw them (#638, #643). Never Apple's artwork or fonts: text is the viewer's system
// font.

extension DrawnPhone {
    static let island = CGSize(width: 126, height: 37)
    static let islandTop: CGFloat = 11
    static let indicator = CGSize(width: 134, height: 5)
    static let indicatorBottom: CGFloat = 8
    /// The screen's corners (the iPhone 16's 55).
    static let screenCorner: CGFloat = 55

    static let homeGround = RGBA(r: 229, g: 229, b: 234)
    static let lockGround = RGBA(r: 209, g: 209, b: 214)
    static let iconGrey = RGBA(r: 199, g: 199, b: 204)
    static let appIconGrey = RGBA(r: 142, g: 142, b: 147)
    static let dockGrey = RGBA(r: 214, g: 214, b: 219)
    static let ink = RGBA(r: 0, g: 0, b: 0)
    static let white = RGBA(r: 255, g: 255, b: 255)
    static let otherNames = ["Tide", "Ledger", "Pebble", "Orbit", "Fern", "Atlas", "Quill", "Harbor", "Marble", "Lantern", "Drift"]

    /// Paints the phone's places around the app's own list (`app`, as the runtime painted it).
    package func compose(app: DisplayList, into list: inout DisplayList) {
        let w = CGFloat(width), h = CGFloat(height)
        let screen = CGRect(x: 0, y: 0, width: w, height: h)
        let amount = CGFloat(coverAmount)
        // What lies under the cover: the home screen, the app's card over it. Everything under
        // zooms in a touch as the lock screen lifts (not under the pull-down).
        let underZoom = coverIsPullDown ? 1 : 1 + 0.06 * amount
        let underSeen = !(amount >= 1 && !cover.isMoving && wake.position == 0)
        if underSeen {
            list.append(.save)
            if underZoom != 1 { list.append(.concat(Self.zoom(underZoom, in: screen))) }
            let homeSeen = mode == .home || behind == .home || !cardShown || !appIsFull
            if homeSeen {
                // The home screen settles back from 10 % larger as the app leaves.
                let homeZoom = cardShown ? 1 + 0.1 * CGFloat(cardOpen) : 1
                list.append(.save)
                if homeZoom != 1 { list.append(.concat(Self.zoom(homeZoom, in: screen))) }
                paintHome(into: &list, hidingIcon: cardShown)
                list.append(.restore)
            }
            if cardShown { paintCard(app: app, into: &list) }
            list.append(.restore)
        }
        if banner.position > Self.bannerAway + 1 { paintBanner(into: &list) }
        let darkStatus = statusBarIsDark(amount: amount)
        paintStatusBar(into: &list, dark: darkStatus && amount < 0.5)
        if amount > 0 { paintCover(into: &list, screen: screen) }
        if amount >= 0.5 { paintStatusBar(into: &list, dark: true, clock: false) }
        let indicatorSeen = (mode == .app && cardShown && cardOpen > 0.98) || amount > 0
        if indicatorSeen {
            let overCover = amount > 0.5
            paintIndicator(into: &list, dark: overCover ? true : darkStatus, screen: screen)
        }
        paintIsland(into: &list, screen: screen)
        if dark.position > 0 {
            list.append(.fillRect(screen, RGBA(red: 0, green: 0, blue: 0, alpha: min(1, max(0, dark.position)))))
        }
    }

    static func zoom(_ factor: CGFloat, in rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: factor, y: factor).translatedBy(x: -rect.midX, y: -rect.midY)
    }

    /// Black over a light app or the grey places, white over a dark app (its own colour scheme).
    private func statusBarIsDark(amount: CGFloat) -> Bool {
        if mode == .home || !cardShown || cardOpen < 0.9 { return true }
        return runtime.rootEnvironment.colorScheme != .dark
    }

    // MARK: The app's card

    private func paintCard(app: DisplayList, into list: inout DisplayList) {
        let rect = cardRect
        let w = CGFloat(width)
        if appIsFull {
            list.commands.append(contentsOf: app.commands)
            return
        }
        let open = CGFloat(cardOpen)
        let corner: CGFloat = open > 0.995 ? 0 : 14 + 41 * open
        let content = min(1, max(0, (rect.width - 70) / 90))
        list.append(.save)
        list.append(.clipRRect(rect, cornerRadius: min(corner, rect.width / 2, rect.height / 2)))
        list.append(.fillRect(rect, Self.white))
        if content > 0 {
            let scale = rect.width / w
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)))
            if content < 1 { list.append(.beginGroup(opacity: Double(content))) }
            list.commands.append(contentsOf: app.commands)
            if content < 1 { list.append(.endGroup) }
            list.append(.restore)
        }
        if content < 1 {
            // The app's picture gives way to its icon as it lands.
            list.append(.fillRect(rect, Self.appIconGrey.multiplyingAlpha(by: Double(1 - content))))
        }
        list.append(.restore)
    }

    // MARK: Home screen (stand-in, #638 draws it)

    private func paintHome(into list: inout DisplayList, hidingIcon: Bool) {
        let w = CGFloat(width), h = CGFloat(height)
        list.append(.fillRect(CGRect(x: 0, y: 0, width: w, height: h), Self.homeGround))
        let size = CGFloat(Self.iconSize)
        let label = font(size: 12, weight: .regular)
        for index in 0..<12 {
            let x = CGFloat(Self.iconColumns[index % 4]) * w / 393
            let y = CGFloat(Self.iconTop) + CGFloat(index / 4) * CGFloat(Self.iconRowStep)
            let rect = CGRect(x: x, y: y, width: size, height: size)
            let isApp = index == 0
            if !(isApp && hidingIcon) {
                list.append(.fillRRect(rect, cornerRadius: size * 0.2237, isApp ? Self.appIconGrey : Self.iconGrey))
            }
            let name = isApp ? (appName.isEmpty ? "App" : appName) : Self.otherNames[index - 1]
            drawCentered(name, font: label, centerX: rect.midX, baseline: rect.maxY + 17, maxWidth: size + 20, color: Self.ink, into: &list)
        }
        let dock = CGRect(x: 12, y: h - 12 - 92, width: w - 24, height: 92)
        list.append(.fillRRect(dock, cornerRadius: 34, Self.dockGrey))
        for index in 0..<4 {
            let x = CGFloat(Self.iconColumns[index]) * w / 393
            list.append(.fillRRect(CGRect(x: x, y: dock.minY + 16, width: size, height: size), cornerRadius: size * 0.2237, Self.iconGrey))
        }
    }

    // MARK: Lock screen and pull-down (stand-in, #643 draws them)

    private func paintCover(into list: inout DisplayList, screen: CGRect) {
        let top = CGFloat(cover.position)
        list.append(.save)
        list.append(.concat(CGAffineTransform(translationX: 0, y: top)))
        let zoom = 1 + 0.05 * CGFloat(wake.position)
        if zoom != 1 { list.append(.concat(Self.zoom(zoom, in: screen))) }
        list.append(.fillRect(screen, Self.lockGround))
        let date = font(size: 20, weight: .semibold)
        let time = font(size: 92, weight: .bold)
        drawCentered(clockText.date, font: date, centerX: screen.midX, baseline: 118, maxWidth: screen.width - 40, color: Self.ink, into: &list)
        drawCentered(clockText.time, font: time, centerX: screen.midX, baseline: 214, maxWidth: screen.width - 20, color: Self.ink, into: &list)
        // One notification from the app, as a stand-in card.
        let note = notificationRect.offsetBy(dx: 0, dy: -top)
        paintNotificationCard(note, into: &list)
        list.append(.restore)
    }

    private func paintNotificationCard(_ rect: CGRect, into list: inout DisplayList) {
        list.append(.fillRRect(rect, cornerRadius: 24, Self.white))
        let icon = CGRect(x: rect.minX + 14, y: rect.minY + 18, width: 38, height: 38)
        list.append(.fillRRect(icon, cornerRadius: 9, Self.appIconGrey))
        list.append(.fillRRect(CGRect(x: icon.maxX + 12, y: rect.minY + 22, width: rect.width * 0.45, height: 10), cornerRadius: 5, Self.iconGrey))
        list.append(.fillRRect(CGRect(x: icon.maxX + 12, y: rect.minY + 42, width: rect.width * 0.6, height: 10), cornerRadius: 5, Self.dockGrey))
    }

    private func paintBanner(into list: inout DisplayList) {
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.18), radius: 16, offset: CGSize(width: 0, height: 4)))
        paintNotificationCard(bannerRect, into: &list)
        list.append(.endGroup)
    }

    // MARK: Status bar, island, home indicator

    private func paintIsland(into list: inout DisplayList, screen: CGRect) {
        let size = Self.island
        let rect = CGRect(x: screen.midX - size.width / 2, y: Self.islandTop, width: size.width, height: size.height)
        list.append(.fillRRect(rect, cornerRadius: size.height / 2, Self.ink))
    }

    private func paintIndicator(into list: inout DisplayList, dark: Bool, screen: CGRect) {
        let size = Self.indicator
        let rect = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - Self.indicatorBottom - size.height, width: size.width, height: size.height)
        list.append(.fillRRect(rect, cornerRadius: size.height / 2, dark ? Self.ink : Self.white))
    }

    /// The time left of the island, signal, wifi and battery right of it, all full.
    private func paintStatusBar(into list: inout DisplayList, dark: Bool, clock: Bool = true) {
        let w = CGFloat(width)
        let color = dark ? Self.ink : Self.white
        let islandLeft = w / 2 - Self.island.width / 2
        let islandRight = w / 2 + Self.island.width / 2
        let middle = Self.islandTop + Self.island.height / 2
        if clock, !clockText.time.isEmpty {
            drawCentered(clockText.time, font: font(size: 17, weight: .semibold), centerX: islandLeft / 2 + 6, baseline: middle + 6, maxWidth: islandLeft - 16, color: color, into: &list)
        }
        // Right ear: signal bars, wifi, battery, centred together.
        let total: CGFloat = 18 + 6 + 17 + 7 + 27
        var x = (islandRight + w) / 2 - total / 2 - 4
        let bottom = middle + 5.5
        // Signal: four bars rising.
        for index in 0..<4 {
            let barHeight = 4 + CGFloat(index) * 2.6
            list.append(.fillRRect(CGRect(x: x + CGFloat(index) * 4.8, y: bottom - barHeight, width: 3.2, height: barHeight), cornerRadius: 1, color))
        }
        x += 18 + 6
        // Wifi: a dot's sector and two arcs above it, from one centre.
        let centre = CGPoint(x: x + 8.5, y: bottom)
        var wedge = Path()
        wedge.move(to: centre)
        wedge.addArc(center: centre, radius: 4.2, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
        wedge.closeSubpath()
        list.append(.fillPath(wedge, color))
        for radius in [7.6, 11.0] as [CGFloat] {
            var arc = Path()
            arc.addArc(center: centre, radius: radius, startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            list.append(.strokePath(arc, style: StrokeStyle(lineWidth: 2.1, lineCap: .round), color))
        }
        x += 17 + 7
        // Battery: an outline, full inside, and its cap.
        let body = CGRect(x: x, y: bottom - 11.5, width: 24.5, height: 12)
        list.append(.strokePath(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3.6), style: StrokeStyle(lineWidth: 1), color.multiplyingAlpha(by: 0.4)))
        list.append(.fillRRect(body.insetBy(dx: 2, dy: 2), cornerRadius: 2, color))
        list.append(.fillRRect(CGRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4), cornerRadius: 0.75, color.multiplyingAlpha(by: 0.4)))
    }

    // MARK: Text

    private func font(size: CGFloat, weight: Font.Weight) -> ResolvedFont {
        Font.system(size: size, weight: weight).resolve(profile: runtime.rootEnvironment.platformProfile)
    }

    private func drawCentered(_ text: String, font: ResolvedFont, centerX: CGFloat, baseline: CGFloat, maxWidth: CGFloat, color: RGBA, into list: inout DisplayList) {
        guard !text.isEmpty else { return }
        let layout = runtime.layoutText(text, font: font, width: nil)
        let width = layout.lines.first?.inkWidth ?? layout.size.width
        let x = centerX - min(width, maxWidth) / 2
        list.append(.drawText(text, DisplayFont(font), origin: CGPoint(x: x, y: baseline), color))
    }
}
