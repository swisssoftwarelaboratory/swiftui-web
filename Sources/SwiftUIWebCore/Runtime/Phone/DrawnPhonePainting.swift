#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// What the drawn iPhone paints (new-website#618): the island, the status bar (the viewer's own
// time, full signal, wifi and battery, all drawn by us), the home indicator, and the places
// around the app. The home screen is #626's plain greys (#638); the lock screen is a plain grey
// stand-in until its own ticket draws it (#643). Never Apple's artwork or fonts: text is the
// viewer's system font.

extension DrawnPhone {
    static let island = CGSize(width: 126, height: 37)
    static let islandTop: CGFloat = 11
    static let indicator = CGSize(width: 134, height: 5)
    static let indicatorBottom: CGFloat = 8
    /// The screen's corners (the iPhone 16's 55).
    static let screenCorner: CGFloat = 55

    // The home screen's plain greys (#626, frame "Home screen: plain greys"): a light grey
    // wallpaper, grey made-up apps, a light dock.
    static let homeGround = RGBA(r: 233, g: 233, b: 233)
    static let lockGround = RGBA(r: 233, g: 233, b: 233)
    static let iconGrey = RGBA(r: 210, g: 210, b: 210)
    /// The app's icon when its build has none.
    static let appIconGrey = RGBA(r: 142, g: 142, b: 147)
    static let dockGrey = RGBA(r: 214, g: 214, b: 219)
    static let dockGround = RGBA(r: 255, g: 255, b: 255, a: 0.45)
    static let iconCorner: CGFloat = 0.2237
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
        let underZoom = coverIsPullDown ? 1 : 1 + 0.12 * amount
        let underFade = coverIsPullDown ? 1 : Double(1 - amount)
        let underSeen = !(amount >= 1 && !cover.isMoving && wake.position == 0)
        if underSeen {
            list.append(.save)
            if underFade < 1 { list.append(.fillRect(screen, Self.ink)) }
            if underFade < 1 { list.append(.beginGroup(opacity: underFade)) }
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
            if underFade < 1 { list.append(.endGroup) }
            list.append(.restore)
        }
        if cardShown, appIsFull { paintFaceID(into: &list) }
        if banner.position > Self.bannerAway + 1 { paintBanner(into: &list) }
        let darkStatus = statusBarIsDark(amount: amount)
        paintStatusBar(into: &list, dark: darkStatus && amount < 0.5)
        if amount > 0 {
            let fade = coverIsPullDown ? 1 : Double(amount)
            if fade < 1 { list.append(.beginGroup(opacity: fade)) }
            paintCover(into: &list, screen: screen)
            if fade < 1 { list.append(.endGroup) }
        }
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
            list.append(.beginGroup(opacity: Double(1 - content)))
            paintAppIcon(rect, into: &list)
            list.append(.endGroup)
        }
        list.append(.restore)
    }

    // MARK: Home screen (#626)

    /// The home screen: the app top left with its own icon and name, the made-up apps around it
    /// (they don't open), three rows of four and four in the dock, one page.
    private func paintHome(into list: inout DisplayList, hidingIcon: Bool) {
        let w = CGFloat(width), h = CGFloat(height)
        list.append(.fillRect(CGRect(x: 0, y: 0, width: w, height: h), Self.homeGround))
        let size = CGFloat(Self.iconSize)
        let label = font(size: 12, weight: .regular)
        paintWidgets(into: &list)
        for index in 0..<homeIconCount {
            let rect = iconRect(at: index)
            let isApp = index == 0
            if isApp {
                if !hidingIcon { paintAppIcon(rect, into: &list) }
            } else {
                list.append(.fillRRect(rect, cornerRadius: size * Self.iconCorner, Self.iconGrey))
            }
            let name = isApp ? homeName : Self.otherNames[index - 1]
            drawCentered(name, font: label, centerX: rect.midX, baseline: rect.maxY + 17, maxWidth: size + 20, color: Self.ink, into: &list)
        }
        let dock = dockRect
        list.append(.fillRRect(dock, cornerRadius: 38, Self.dockGround))
        for index in 0..<4 {
            let x = CGFloat(Self.iconColumns[index]) * w / 393
            list.append(.fillRRect(CGRect(x: x, y: dock.midY - size / 2, width: size, height: size), cornerRadius: size * Self.iconCorner, Self.iconGrey))
        }
    }

    /// The dock: light, rounded, low on the screen above the home indicator (#626).
    var dockRect: CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        return CGRect(x: 12, y: h - 19 - 94, width: w - 24, height: 94)
    }

    /// The app's own icon (its `AppIcon` set, as its Info names it), rounded like iOS's; a grey
    /// square when the build has none.
    func paintAppIcon(_ rect: CGRect, into list: inout DisplayList) {
        let corner = rect.width * Self.iconCorner
        guard let icon = appIcon(scale: 3) else {
            list.append(.fillRRect(rect, cornerRadius: corner, Self.appIconGrey))
            return
        }
        list.append(.save)
        list.append(.clipRRect(rect, cornerRadius: corner))
        list.append(.drawImage(ImageDraw(file: icon.file, scale: icon.scale, pixelSize: CGSize(width: icon.pixelWidth, height: icon.pixelHeight), rect: rect)))
        list.append(.restore)
    }

    private func appIcon(scale: CGFloat) -> ImageVariant? {
        let catalog = runtime.assetCatalog
        return catalog.image(named: appIconName)?.variant(scale: scale, scheme: .light, idiom: "iphone")
    }

    // MARK: Lock screen and pull-down (#627, built in #643)

    static let stackEdgeGrey = RGBA(r: 246, g: 246, b: 246)
    static let greyText = RGBA(red: 0, green: 0, blue: 0, alpha: 0.55)

    private func paintCover(into list: inout DisplayList, screen: CGRect) {
        let top = CGFloat(cover.position)
        list.append(.save)
        list.append(.concat(CGAffineTransform(translationX: 0, y: top)))
        let zoom = 1 + 0.05 * CGFloat(wake.position)
        list.append(.save)
        if zoom != 1 { list.append(.concat(Self.zoom(zoom, in: screen))) }
        list.append(.fillRect(screen.insetBy(dx: -20, dy: -20), Self.lockGround))
        list.append(.restore)
        // The date over a large clock, in the system font, the viewer's own time.
        drawCentered(clockText.date, font: font(size: 21, weight: .semibold), centerX: screen.midX, baseline: 95, maxWidth: screen.width - 40, color: Self.ink, into: &list)
        drawCentered(clockText.time, font: font(size: 96, weight: .medium), centerX: screen.midX, baseline: 187, maxWidth: screen.width - 20, color: Self.ink, into: &list)
        paintLockWidgets(into: &list, screen: screen)
        paintColumn(into: &list, screen: screen)
        list.append(.restore)
    }

    /// The app's lock screen widgets in one row under the clock, centred, 14 apart.
    private func paintLockWidgets(into list: inout DisplayList, screen: CGRect) {
        guard !lockWidgets.isEmpty else { return }
        let sizes = lockWidgets.map { $0.layout(width: $0.size.width > 0 ? $0.size.width : 64) }
        let total = sizes.reduce(0) { $0 + $1.width } + 14 * CGFloat(sizes.count - 1)
        var x = screen.midX - total / 2
        for (tree, size) in zip(lockWidgets, sizes) {
            tree.paint(into: &list, at: CGPoint(x: x, y: 214), scale: runtime.hostDisplayScale)
            x += size.width + 14
        }
    }

    /// The Live Activities, then the notifications (a stack or the list), clipped to the room
    /// between the clock and the bottom once they scroll.
    private func paintColumn(into list: inout DisplayList, screen: CGRect) {
        let layout = columnLayout()
        guard !layout.entries.isEmpty else { return }
        let clips = layout.overflow > 0 || listScroll.isMoving
        if clips {
            let room = columnRoom
            list.append(.save)
            list.append(.clipRect(CGRect(x: 0, y: room.top, width: screen.width, height: room.bottom - room.top)))
        }
        let pressedNote: CoverItem? = activityTookPress ? nil : pressedItem
        for entry in layout.entries {
            let rect = entry.rect
            switch entry.item {
            case .activity(let index):
                guard index < activities.count else { continue }
                // The app's own view on a white card (its `activityBackgroundTint` over it).
                list.append(.save)
                list.append(.clipRRect(rect, cornerRadius: Self.cardCorner))
                list.append(.fillRect(rect, Self.white))
                activities[index].tree.paint(into: &list, at: rect.origin, scale: runtime.hostDisplayScale)
                list.append(.restore)
            case .note(let index):
                guard index < notes.count else { continue }
                paintNote(notes[index], in: rect, more: nil, pressed: pressedNote == entry.item, into: &list)
            case .stack:
                guard let first = notes.first else { continue }
                // Edges of the notifications behind, under the newest one.
                let edges = notes.count > 2 ? 2 : 1
                let card = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.stackEdge * CGFloat(edges))
                for edge in stride(from: edges, through: 1, by: -1) {
                    let inset = 14 * CGFloat(edge)
                    let edgeRect = CGRect(x: card.minX + inset, y: card.maxY - Self.cardCorner, width: card.width - 2 * inset,
                                          height: Self.cardCorner + Self.stackEdge * CGFloat(edge))
                    list.append(.fillRRect(edgeRect, cornerRadius: Self.cardCorner, edge == 1 ? Self.white : Self.stackEdgeGrey))
                }
                let others = notes.count - 1
                paintNote(first, in: card, more: "\(others) more notification\(others == 1 ? "" : "s")", pressed: pressedNote == .stack, into: &list)
            }
        }
        if clips { list.append(.restore) }
    }

    /// A notification's flat white card: the app's icon and name, title, when, and its text.
    private func paintNote(_ note: Note, in rect: CGRect, more: String?, pressed: Bool, into list: inout DisplayList) {
        list.append(.fillRRect(rect, cornerRadius: Self.cardCorner, pressed ? RGBA(r: 236, g: 236, b: 238) : Self.white))
        let icon = CGRect(x: rect.minX + Self.notePad.width, y: rect.minY + Self.notePad.height + 1, width: Self.noteIcon, height: Self.noteIcon)
        paintAppIcon(in: icon, cornerRadius: 9, into: &list)
        let left = rect.minX + noteTextLeft
        let right = rect.maxX - Self.notePad.width
        // The title line: the title (or the app's name), "now" on its right.
        let when = whenText(note.date)
        let whenFont = font(size: 13, weight: .regular)
        let whenWidth = runtime.layoutText(when, font: whenFont, width: nil).size.width
        let lineTop = rect.minY + Self.notePad.height
        list.append(.drawText(when, DisplayFont(whenFont), origin: CGPoint(x: right - whenWidth, y: lineTop + 15), Self.greyText))
        let title = note.title.isEmpty ? (appName.isEmpty ? "App" : appName) : note.title
        let titleFont = font(size: 15, weight: .semibold)
        let titleLayout = runtime.layoutText([StyledRun(title, font: titleFont)], options: TextLayoutOptions(lineLimit: 1),
                                             width: max(10, right - whenWidth - 8 - left))
        drawLines(titleLayout, font: titleFont, origin: CGPoint(x: left, y: lineTop), lineHeight: Self.noteLine, color: Self.ink, into: &list)
        let body = noteBodyLayout(note, width: rect.width)
        let bodyFont = font(size: 15, weight: .regular)
        drawLines(body, font: bodyFont, origin: CGPoint(x: left, y: lineTop + Self.noteLine), lineHeight: Self.noteLine, color: Self.ink, into: &list)
        if let more {
            let y = lineTop + Self.noteLine * CGFloat(1 + body.lines.count)
            list.append(.drawText(more, DisplayFont(whenFont), origin: CGPoint(x: left, y: y + 16), Self.greyText))
        }
    }

    /// The app's icon (its own picture once the home screen draws it, #638; grey until then).
    func paintAppIcon(in rect: CGRect, cornerRadius: CGFloat, into list: inout DisplayList) {
        list.append(.fillRRect(rect, cornerRadius: cornerRadius, Self.appIconGrey))
    }

    /// Draws a laid-out text one line every `lineHeight`, each line's baseline where a 15 pt
    /// line of that height puts it.
    private func drawLines(_ layout: TextLayout, font: ResolvedFont, origin: CGPoint, lineHeight: CGFloat, color: RGBA, into list: inout DisplayList) {
        let display = DisplayFont(font)
        for (index, line) in layout.lines.enumerated() {
            let baseline = origin.y + CGFloat(index) * lineHeight + 15
            for fragment in line.fragments {
                list.append(.drawText(fragment.text, display, origin: CGPoint(x: origin.x + fragment.x, y: baseline), color))
            }
        }
    }

    private func paintBanner(into list: inout DisplayList) {
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.18), radius: 16, offset: CGSize(width: 0, height: 4)))
        let rect = bannerRect
        if let note = bannerNote {
            paintNote(note, in: rect, more: nil, pressed: false, into: &list)
        } else {
            list.append(.fillRRect(rect, cornerRadius: Self.cardCorner, Self.white))
        }
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
