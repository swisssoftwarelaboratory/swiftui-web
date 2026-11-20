// The keyboard's region of the safe area (new-website#648), against the iOS 27 simulator
// (iPhone 16, 393 × 852, safe area 59 / 34, keyboard 328 with its top at 524; probe app and
// numbers in the ticket's research): the regions combine as the deeper one, a reader reports the
// depth from the screen's edge, and ignoring a region leaves the other.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct KeyboardSafeAreaTests {
    static let screen = CGSize(width: 393, height: 852)

    private final class Reading: @unchecked Sendable {
        var insets = EdgeInsets()
        var frame = CGRect.zero
    }

    /// Lays a reader out (inside a plain root `ZStack`, as an app's shell) with the keyboard
    /// down or up, and returns its frame and the insets it read.
    private func measure<V: View>(keyboardUp: Bool, _ modify: (AnyView) -> V) -> (frame: CGRect, insets: EdgeInsets) {
        let reading = Reading()
        let reader = AnyView(GeometryReader { proxy in
            let _ = { reading.insets = proxy.safeAreaInsets; reading.frame = proxy.frame(in: .global) }()
            Color.clear
        })
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.hostSafeAreaInsets = [59, 0, 34, 0]
        r.keyboardInset = keyboardUp ? 328 : 0
        r.mount(ZStack(alignment: .bottom) { modify(reader) })
        r.layout(in: Self.screen)
        return (reading.frame, reading.insets)
    }

    private func expect(_ m: (frame: CGRect, insets: EdgeInsets), y: CGFloat, maxY: CGFloat, top: CGFloat, bottom: CGFloat,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(m.frame.minY == y && m.frame.maxY == maxY, "frame \(m.frame)", sourceLocation: sourceLocation)
        #expect(m.insets.top == top && m.insets.bottom == bottom, "insets \(m.insets)", sourceLocation: sourceLocation)
    }

    @Test func plainReader() {
        expect(measure(keyboardUp: false) { $0 }, y: 59, maxY: 818, top: 59, bottom: 34)
        expect(measure(keyboardUp: true) { $0 }, y: 59, maxY: 524, top: 59, bottom: 328)
    }

    @Test func ignoringTheContainerKeepsTheKeyboard() {
        expect(measure(keyboardUp: false) { $0.ignoresSafeArea(.container) }, y: 0, maxY: 852, top: 0, bottom: 0)
        expect(measure(keyboardUp: true) { $0.ignoresSafeArea(.container) }, y: 0, maxY: 524, top: 0, bottom: 328)
    }

    @Test func ignoringTheKeyboardIsAsIfItNeverCameUp() {
        expect(measure(keyboardUp: false) { $0.ignoresSafeArea(.keyboard) }, y: 59, maxY: 818, top: 59, bottom: 34)
        expect(measure(keyboardUp: true) { $0.ignoresSafeArea(.keyboard) }, y: 59, maxY: 818, top: 59, bottom: 34)
    }

    @Test func ignoringEverything() {
        expect(measure(keyboardUp: true) { $0.ignoresSafeArea() }, y: 0, maxY: 852, top: 0, bottom: 0)
    }

    @Test func ignoringTheContainersBottomOnly() {
        expect(measure(keyboardUp: false) { $0.ignoresSafeArea(.container, edges: .bottom) }, y: 59, maxY: 852, top: 59, bottom: 0)
        expect(measure(keyboardUp: true) { $0.ignoresSafeArea(.container, edges: .bottom) }, y: 59, maxY: 524, top: 59, bottom: 328)
    }

    @Test func aBarIgnoringTheBottomStaysBehindTheKeyboard() {
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.hostSafeAreaInsets = [59, 0, 34, 0]
        r.keyboardInset = 328
        r.mount(ZStack(alignment: .bottom) { Color.clear; Color.red.frame(height: 50)._probe("bar").ignoresSafeArea(edges: .bottom) })
        r.layout(in: Self.screen)
        #expect(r.probeFrames["bar"].map { $0.minY == 802 && $0.maxY == 852 } == true, "\(String(describing: r.probeFrames["bar"]))")
    }
}
#endif
