#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// The drawn iPhone around an app (new-website#651, its look in #618, its moves in #628): the
// phone's own places as layers over and under the app (the home screen behind it, the lock
// screen that is also the pull-down, banners over it, the screen off), and the moves between
// them. Every move follows the finger and settles on the physics system's springs started at
// the finger's speed (#261), with the rubber band past its ends. The app keeps running behind
// them and hears of it through its scene phase, as on iOS.

/// The phone's moves and places, in the scene's points (the screen is the layout size).
@MainActor
package final class DrawnPhone {
    /// What the phone shows.
    package enum Mode: Equatable, Sendable {
        /// The app, full screen.
        case app
        /// The home screen.
        case home
        /// The lock screen over what was open.
        case locked
        /// The lock screen's view pulled down from the top over what was open.
        case pullDown
        /// The screen dark, on its lock screen.
        case off
    }

    /// A press the phone took, and what it moves.
    package enum DragKind: Equatable, Sendable {
        /// Up from the bottom edge of the app: the app shrinks into a card under the finger.
        case leaveApp
        /// Down from the top edge: the lock screen's view comes down with the finger.
        case pullDown
        /// Up from the bottom of the lock screen or the pull-down: it lifts with the finger.
        case lift
        /// The banner, dragged or tapped.
        case banner
        /// A press on the home screen: a tap on the app's icon opens it.
        case home
        /// A press on the lock screen or pull-down away from its bottom: a tap on a notification
        /// opens the app; anything else does nothing.
        case cover
        /// A press in the app's bottom edge that has not shown which way it goes: a move up
        /// leaves the app, anything else (a tap on a tab bar, a sideways drag) is the app's.
        case bottomEdge
    }

    struct Drag {
        var kind: DragKind
        var start: CGPoint
        var startTime: Double
        var type: PointerType
        var tracker = VelocityTracker(window: 0.08, restInterval: 0.1)
        var moved = false
        /// Where the lifted cover started (`lift`).
        var coverStart: Double = 0
    }

    unowned let runtime: Runtime

    package private(set) var mode: Mode = .app
    /// What the lock screen, the pull-down or the dark screen has over it.
    package private(set) var behind: Mode = .app
    /// Whether the app's card is on screen (full, or flying to or from its icon).
    package private(set) var cardShown = true
    /// Whether the cover is the pull-down (nothing behind zooms) rather than the lock screen.
    private(set) var coverIsPullDown = false

    // The moving values. The cover's top edge: 0 over the screen, -height gone above it.
    var cover = Motion(position: 0, restDistance: 0.25, restSpeed: 5)
    /// The screen's darkness, 0 lit to 1 off.
    var dark = Motion(position: 0, restDistance: 0.002, restSpeed: 0.05)
    /// The lock screen's zoom as it wakes, 1 at 5 % larger, settling to 0.
    var wake = Motion(position: 0, restDistance: 0.002, restSpeed: 0.05)
    /// The app's card: its centre and size.
    var cardX = Motion(position: 0, restDistance: 0.25, restSpeed: 5)
    var cardY = Motion(position: 0, restDistance: 0.25, restSpeed: 5)
    var cardWidth = Motion(position: 0, restDistance: 0.25, restSpeed: 5)
    var cardHeight = Motion(position: 0, restDistance: 0.25, restSpeed: 5)
    /// The banner's offset from where it rests below the island (negative is up, out of sight).
    var banner = Motion(position: DrawnPhone.bannerAway, restDistance: 0.25, restSpeed: 5)
    package private(set) var bannerShown = false
    private var bannerTime: Double = 0
    /// Seconds until a pressed side button puts the lock screen behind the dark (iOS goes dark
    /// first, then the phone is on its lock screen).
    private var lockDelay: Double?

    var drag: Drag?
    /// A bottom-edge press held back from the app until it shows which way it goes.
    private var heldPress: (point: CGPoint, type: PointerType, time: Double)?
    /// Set while the phone hands a press on to the app, so the runtime's own handlers run.
    package private(set) var forwarding = false

    /// The clock and date the host reads from the viewer's own clock.
    package var clock: (@MainActor @Sendable () -> (time: String, date: String))?
    package private(set) var clockText = (time: "", date: "")
    package var appName = ""

    package init(runtime: Runtime) {
        self.runtime = runtime
    }

    // MARK: Numbers

    /// The screen's size in points (the iPhone 16's 393 by 852 in the drawn phone).
    var width: Double { max(1, Double(runtime.layoutSize.width)) }
    var height: Double { max(1, Double(runtime.layoutSize.height)) }

    /// Presses starting this close to the top go to the pull-down, to the bottom to leaving.
    static let topEdge: Double = 54
    static let bottomEdge: Double = 34
    /// The lock screen's bottom part where a drag up unlocks (or closes the pull-down).
    static let liftZone: Double = 140
    /// A press that travels this far is a drag, not a tap.
    static let slop: Double = 8
    static let bannerAway: Double = -170
    static let bannerHeight: Double = 76
    static let bannerTop: Double = 54
    static let bannerSeconds: Double = 6

    // Springs: iOS's, from #628 (the prototype's starting values from iOS's known springs).
    static let darken = SpringModel(response: 0.18, dampingFraction: 1)
    static let brighten = SpringModel(response: 0.35, dampingFraction: 1)
    static let wakeZoom = SpringModel(response: 0.5, dampingFraction: 1)
    static let coverSpring = SpringModel(response: 0.4, dampingFraction: 1)
    static let cardSpring = SpringModel(response: 0.5, dampingFraction: 0.86)
    static let cardBack = SpringModel(response: 0.4, dampingFraction: 0.9)
    static let bannerIn = SpringModel(response: 0.5, dampingFraction: 0.78)
    static let bannerBack = SpringModel(response: 0.4, dampingFraction: 0.86)
    static let bannerOut = SpringModel(response: 0.4, dampingFraction: 1)

    /// The app's icon on the home screen: first in the top row (#626).
    static let iconSize: Double = 60
    static let iconColumns: [Double] = [27, 120, 213, 306]
    static let iconTop: Double = 72
    static let iconRowStep: Double = 98
    var iconRect: CGRect {
        CGRect(x: Self.iconColumns[0] * width / 393, y: Self.iconTop, width: Self.iconSize, height: Self.iconSize)
    }

    // MARK: State

    /// The card's rectangle now.
    var cardRect: CGRect {
        CGRect(x: cardX.position - cardWidth.position / 2, y: cardY.position - cardHeight.position / 2,
               width: cardWidth.position, height: cardHeight.position)
    }

    /// How far the card is open, 0 at the icon's size to 1 full width.
    var cardOpen: Double {
        min(1, max(0, (cardWidth.position - Self.iconSize) / (width - Self.iconSize)))
    }

    /// Whether the app fills the screen, still, nothing over it but the banner.
    var appIsFull: Bool {
        cardShown && !cardMoving && abs(cardWidth.position - width) < 0.5 && abs(cardHeight.position - height) < 0.5
            && abs(cardX.position - width / 2) < 0.5 && abs(cardY.position - height / 2) < 0.5
    }

    var cardMoving: Bool { cardX.isMoving || cardY.isMoving || cardWidth.isMoving || cardHeight.isMoving }

    /// How much of the screen the cover hides, 0 to 1.
    var coverAmount: Double { min(1, max(0, 1 + cover.position / height)) }

    /// Whether the app is what the viewer sees and presses: full screen, nothing over it.
    package var appTakesInput: Bool {
        mode == .app && appIsFull && coverAmount == 0 && drag == nil && dark.position < 0.5
    }

    /// Whether the app is painted at all this frame.
    var appIsSeen: Bool {
        cardShown && !(coverAmount >= 1 && !cover.isMoving && wake.position == 0) && dark.position < 1
    }

    /// Whether anything moves on screen.
    package var isMoving: Bool {
        cover.isMoving || dark.isMoving || wake.isMoving || cardMoving || banner.isMoving
    }

    /// Whether the phone needs the clock to run: a move, the dark's lock delay, a banner's time.
    package var needsTime: Bool { isMoving || lockDelay != nil || bannerShown }

    /// The app's scene phase as the phone sees it: active while it fills the screen, inactive
    /// while something covers part of it or it is on its way out or in, background once it is
    /// gone (on the home screen, locked, dark).
    package var scenePhase: ScenePhase {
        switch mode {
        case .off, .locked:
            return .background
        case .home:
            return cardShown ? .inactive : .background
        case .pullDown:
            return behind == .app ? .inactive : .background
        case .app:
            return appIsFull && coverAmount == 0 && drag == nil ? .active : .inactive
        }
    }

    /// Starts on the app, full screen.
    package func reset() {
        mode = .app
        behind = .app
        cardShown = true
        coverIsPullDown = false
        setCardFull()
        cover.hold(at: -height)
        dark.hold(at: 0)
        wake.hold(at: 0)
        banner.hold(at: Self.bannerAway)
        bannerShown = false
        lockDelay = nil
        drag = nil
        heldPress = nil
    }

    /// The screen took a new size (the first layout): every place stands where its mode puts it.
    package func screenResized() {
        drag = nil
        heldPress = nil
        if cardShown { setCardFull() }
        if mode == .locked || mode == .pullDown || mode == .off { cover.hold(at: 0) } else { cover.hold(at: -height) }
    }

    func setCardFull() {
        cardX.hold(at: width / 2)
        cardY.hold(at: height / 2)
        cardWidth.hold(at: width)
        cardHeight.hold(at: height)
    }

    func setCard(_ rect: CGRect) {
        cardX.hold(at: rect.midX)
        cardY.hold(at: rect.midY)
        cardWidth.hold(at: rect.width)
        cardHeight.hold(at: rect.height)
    }

    func cardTo(_ rect: CGRect, spring: SpringModel, velocity: CGSize? = nil) {
        cardX.animate(to: rect.midX, spring: spring, velocity: velocity.map { $0.width })
        cardY.animate(to: rect.midY, spring: spring, velocity: velocity.map { $0.height })
        cardWidth.animate(to: rect.width, spring: spring, velocity: velocity == nil ? nil : 0)
        cardHeight.animate(to: rect.height, spring: spring, velocity: velocity == nil ? nil : 0)
    }

    var fullRect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    // MARK: Moves

    /// The side button: dark almost at once, on the lock screen behind the dark; pressed again
    /// (or the dark screen pressed), it wakes.
    package func sideButton() {
        if mode == .off { wakeUp(); return }
        hideBanner(atOnce: true)
        switch mode {
        case .app, .home: behind = mode
        case .pullDown: break
        case .locked, .off: break
        }
        drag = nil
        heldPress = nil
        mode = .off
        dark.animate(to: 1, spring: Self.darken)
        lockDelay = 0.2
        changed()
    }

    func wakeUp() {
        mode = .locked
        coverIsPullDown = false
        lockDelay = nil
        cover.hold(at: 0)
        dark.animate(to: 0, spring: Self.brighten)
        wake.hold(at: 1)
        wake.animate(to: 0, spring: Self.wakeZoom)
        changed()
    }

    /// Behind the dark the phone is on its lock screen over whatever was open.
    private func lockBehindTheDark() {
        lockDelay = nil
        guard mode == .off else { return }
        coverIsPullDown = false
        cover.hold(at: 0)
        if behind == .app {
            cardShown = true
            setCardFull()
        } else {
            cardShown = false
        }
        changed()
    }

    func unlock(velocity: Double) {
        mode = behind
        cover.animate(to: -height, spring: Self.coverSpring, velocity: velocity)
        changed()
    }

    func relock(velocity: Double) {
        cover.animate(to: 0, spring: Self.coverSpring, velocity: velocity)
    }

    func openPullDown(velocity: Double) {
        mode = .pullDown
        cover.animate(to: 0, spring: Self.coverSpring, velocity: velocity)
        changed()
    }

    func closePullDown(velocity: Double) {
        mode = behind
        cover.animate(to: -height, spring: Self.coverSpring, velocity: velocity)
        changed()
    }

    /// Grows the app's card out of its icon to the full screen.
    package func openApp(fromIcon: Bool = true) {
        mode = .app
        behind = .app
        if !cardShown || fromIcon && cardWidth.position < Self.iconSize + 1 { setCard(iconRect) }
        cardShown = true
        cardTo(fullRect, spring: Self.cardSpring)
        changed()
    }

    /// The card flies into its icon, the finger's speed carried in.
    func leaveApp(velocity: CGSize) {
        mode = .home
        behind = .home
        cardTo(iconRect, spring: Self.cardSpring, velocity: velocity)
        changed()
    }

    func backToApp(velocity: CGSize) {
        mode = .app
        cardTo(fullRect, spring: Self.cardBack, velocity: velocity)
        changed()
    }

    /// A banner drops in below the island and goes up by itself after 6 s.
    package func showBanner() {
        guard mode == .app || mode == .home else { return }
        bannerShown = true
        bannerTime = 0
        banner.hold(at: Self.bannerAway)
        banner.animate(to: 0, spring: Self.bannerIn)
        changed()
    }

    func hideBanner(atOnce: Bool, velocity: Double = 0) {
        guard bannerShown || banner.position != Self.bannerAway else { return }
        if atOnce {
            banner.hold(at: Self.bannerAway)
            bannerShown = false
        } else {
            banner.animate(to: Self.bannerAway, spring: Self.bannerOut, velocity: velocity)
            bannerShown = false
        }
        changed()
    }

    /// Something changed: paint again and let the app hear of its new phase.
    func changed() {
        runtime.phoneDidChange()
    }

    /// Advances every move by `elapsed` seconds. Returns whether anything still moves.
    package func advance(elapsed: Double) -> Bool {
        let wasMoving = isMoving
        if let delay = lockDelay {
            let left = delay - elapsed
            if left <= 0 { lockBehindTheDark() } else { lockDelay = left }
        }
        cover.step(elapsed)
        dark.step(elapsed)
        wake.step(elapsed)
        let cardWasMoving = cardMoving
        cardX.step(elapsed)
        cardY.step(elapsed)
        cardWidth.step(elapsed)
        cardHeight.step(elapsed)
        if cardWasMoving, !cardMoving, mode == .home, drag == nil { cardShown = false }
        banner.step(elapsed)
        if bannerShown, drag?.kind != .banner {
            bannerTime += elapsed
            if bannerTime >= Self.bannerSeconds { hideBanner(atOnce: false) }
        }
        if !cover.isMoving, cover.position <= -height + 0.5 { coverIsPullDown = false }
        if wasMoving || isMoving { runtime.phoneDidChange() }
        return needsTime
    }

    // MARK: The finger

    /// A press: returns whether the phone takes it (the app never sees it).
    package func pointerDown(at point: CGPoint, type: PointerType, time: Double) -> Bool {
        let y = Double(point.y)
        if mode == .off {
            wakeUp()
            return true
        }
        if dark.position > 0.5 { return true }
        func begin(_ kind: DragKind) -> Bool {
            var d = Drag(kind: kind, start: point, startTime: time, type: type)
            d.tracker.add(point, at: time)
            d.coverStart = cover.position
            drag = d
            switch kind {
            case .pullDown:
                coverIsPullDown = true
                if mode == .app || mode == .home { behind = mode }
                cover.hold(at: cover.position)
            case .lift:
                cover.hold(at: cover.position)
            case .leaveApp:
                for index in 0..<4 { holdCard(index) }
            case .banner:
                banner.hold(at: banner.position)
            case .home, .cover, .bottomEdge:
                break
            }
            changed()
            return true
        }
        if bannerShown || banner.isMoving, mode == .app || mode == .home, bannerRect.contains(point) {
            return begin(.banner)
        }
        switch mode {
        case .locked, .pullDown:
            if y > height - Self.liftZone { return begin(.lift) }
            return begin(.cover)
        case .home:
            if y < Self.topEdge { return begin(.pullDown) }
            return begin(.home)
        case .app:
            if !appIsFull {
                // The card is on its way in: the app takes presses once it is there.
                return true
            }
            if y < Self.topEdge { return begin(.pullDown) }
            if y > height - Self.bottomEdge {
                heldPress = (point, type, time)
                return begin(.bottomEdge)
            }
            return false
        case .off:
            return true
        }
    }

    private func holdCard(_ index: Int) {
        switch index {
        case 0: cardX.hold(at: cardX.position)
        case 1: cardY.hold(at: cardY.position)
        case 2: cardWidth.hold(at: cardWidth.position)
        default: cardHeight.hold(at: cardHeight.position)
        }
    }

    /// A move: returns whether the phone takes it.
    package func pointerMoved(to point: CGPoint, time: Double) -> Bool {
        guard var d = drag else { return false }
        d.tracker.add(point, at: time)
        let dx = Double(point.x - d.start.x), dy = Double(point.y - d.start.y)
        if (dx * dx + dy * dy).squareRoot() > Self.slop { d.moved = true }
        drag = d
        switch d.kind {
        case .bottomEdge:
            guard d.moved else { return true }
            if -dy > abs(dx) {
                // Up: the app leaves.
                d.kind = .leaveApp
                d.start = CGPoint(x: d.start.x, y: CGFloat(height))
                drag = d
                heldPress = nil
                for index in 0..<4 { holdCard(index) }
                followLeave(dx: dx, dy: Double(point.y) - height)
                changed()
                return true
            }
            // Anything else is the app's: the held press goes first.
            drag = nil
            releaseHeldPress()
            forward { runtime.pointerMoved(to: point, time: time) }
            return true
        case .leaveApp:
            followLeave(dx: dx, dy: dy)
        case .pullDown:
            let top = Double(point.y)
            cover.hold(at: top < height ? -height + max(0, top) : RubberBand.offset(forOvershoot: top - height, dimension: height))
        case .lift:
            let moved = d.coverStart + dy
            cover.hold(at: min(0, moved) + (moved > 0 ? RubberBand.offset(forOvershoot: moved, dimension: height) : 0))
        case .banner:
            banner.hold(at: dy < 0 ? dy : RubberBand.offset(forOvershoot: dy, dimension: 120))
        case .home, .cover:
            break
        }
        changed()
        return true
    }

    /// The app shrinks as the finger goes up and follows it sideways, its bottom under the finger.
    private func followLeave(dx: Double, dy: Double) {
        let up = max(0, -dy)
        let progress = min(1, up / (height * 0.7))
        let scale = 1 - 0.62 * progress
        let w = width * scale, h = height * scale * (1 - 0.15 * progress)
        cardWidth.hold(at: w)
        cardHeight.hold(at: h)
        cardX.hold(at: width / 2 + dx * 0.85)
        cardY.hold(at: height + (dy < 0 ? dy : RubberBand.offset(forOvershoot: dy, dimension: 80)) - h / 2)
    }

    /// A lift: returns whether the phone took the press.
    package func pointerUp(at point: CGPoint, time: Double) -> Bool {
        guard let d = drag else { return false }
        drag = nil
        var tracker = d.tracker
        tracker.add(point, at: time)
        let v = tracker.velocity(at: time)
        let dy = Double(point.y - d.start.y)
        switch d.kind {
        case .bottomEdge:
            // A tap in the bottom edge (a tab bar's lower half): the app's.
            releaseHeldPress()
            forward { runtime.pointerUp(at: point, time: time) }
        case .leaveApp:
            let travelled = height - Double(point.y)
            if (travelled > 80 || v.height < -400) && v.height < 200 {
                leaveApp(velocity: v)
            } else {
                backToApp(velocity: v)
            }
        case .pullDown:
            if (cover.position > -height * 0.7 || v.height > 500) && v.height > -300 {
                openPullDown(velocity: Double(v.height))
            } else {
                cover.animate(to: -height, spring: Self.coverSpring, velocity: Double(v.height))
                if mode == .pullDown { mode = behind }
            }
        case .lift:
            let goes = (cover.position < -height / 4 || v.height < -500) && v.height < 300
            if mode == .locked {
                if goes { unlock(velocity: Double(v.height)) } else { relock(velocity: Double(v.height)) }
            } else {
                if goes { closePullDown(velocity: Double(v.height)) } else { openPullDown(velocity: Double(v.height)) }
            }
        case .banner:
            if !d.moved {
                hideBanner(atOnce: false)
                if mode == .home { openApp() }
            } else if dy < -20 || v.height < -300 {
                hideBanner(atOnce: false, velocity: Double(v.height))
            } else {
                banner.animate(to: 0, spring: Self.bannerBack, velocity: Double(v.height))
                bannerTime = 0
            }
        case .home:
            if !d.moved, iconRect.insetBy(dx: -8, dy: -8).contains(point) { openApp() }
        case .cover:
            if !d.moved, notificationRect.contains(point) {
                // A tapped notification slides the cover away and opens the app.
                let wasHome = behind == .home || !cardShown
                behind = .app
                cover.animate(to: -height, spring: Self.coverSpring)
                if wasHome { openApp() } else { mode = .app }
            }
        }
        changed()
        return true
    }

    /// The pointer left mid-press: a drag the phone has goes back where it was.
    package func pointerCancelled() {
        guard let d = drag else { return }
        drag = nil
        heldPress = nil
        switch d.kind {
        case .leaveApp: backToApp(velocity: .zero)
        case .pullDown:
            cover.animate(to: -height, spring: Self.coverSpring)
            if mode == .pullDown { mode = behind }
        case .lift:
            if mode == .locked { relock(velocity: 0) } else { openPullDown(velocity: 0) }
        case .banner: banner.animate(to: 0, spring: Self.bannerBack)
        case .home, .cover, .bottomEdge: break
        }
        changed()
    }

    private func releaseHeldPress() {
        guard let held = heldPress else { return }
        heldPress = nil
        forward { runtime.pointerDown(at: held.point, type: held.type, time: held.time) }
    }

    private func forward(_ body: () -> Void) {
        forwarding = true
        body()
        forwarding = false
    }

    /// Whether a scroll wheel over the screen reaches the app.
    package var appTakesWheel: Bool { appTakesInput }

    // MARK: Places on screen

    var bannerRect: CGRect {
        CGRect(x: 8, y: Self.bannerTop + banner.position, width: width - 16, height: Self.bannerHeight)
    }

    /// The stand-in notification on the lock screen (its own ticket draws the real ones, #643).
    var notificationRect: CGRect {
        CGRect(x: 8, y: height * 0.42 + cover.position, width: width - 16, height: Self.bannerHeight)
    }

    /// Where the phone stands, as `key=value` lines (`phoneDebug`).
    package var debugDescription: String {
        func f(_ value: Double) -> String { String(Int((value * 10).rounded())) }
        let card = cardRect
        return [
            "mode=\(mode)", "behind=\(behind)", "cardShown=\(cardShown)",
            "card=\(f(card.minX)),\(f(card.minY)),\(f(card.width)),\(f(card.height))",
            "cover=\(f(cover.position))", "pullDown=\(coverIsPullDown)",
            "dark=\(f(dark.position * 100))", "wake=\(f(wake.position * 100))",
            "banner=\(f(banner.position))", "bannerShown=\(bannerShown)",
            "moving=\(isMoving)", "drag=\(drag.map { "\($0.kind)" } ?? "none")",
            "clock=\(clockText.time)",
        ].joined(separator: "\n")
    }

    // MARK: Clock

    /// Reads the viewer's clock; returns whether its text changed.
    @discardableResult
    package func readClock() -> Bool {
        guard let clock else { return false }
        let now = clock()
        guard now.time != clockText.time || now.date != clockText.date else { return false }
        clockText = now
        return true
    }
}
