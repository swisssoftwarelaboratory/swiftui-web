// An iPhone's safe area handed in by the host (`Runtime.safeAreaInsets`, the page's `?safeArea=`
// or `env(safe-area-inset-*)`): the status bar's 59 and the home indicator's 34 on an iPhone 16,
// laid out as iOS 27 does in Paulo's app on the simulator (sw-ios-safe-area).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DeviceSafeAreaTests {
    private let window = CGSize(width: 393, height: 852)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        r.mount(view)
        for _ in 0..<3 { r.layout(in: window); r.advanceAnimations(elapsed: 1) }
        return r
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 1).commands.map(\.description) }

    @Test func aStyleBackgroundReachesUnderTheBars() {
        let r = runtime(Text("Home").frame(maxWidth: .infinity, maxHeight: .infinity)._probe("screen").background(Color(red: 0, green: 0, blue: 1)))
        #expect(r.probeFrames["screen"] == CGRect(x: 0, y: 59, width: 393, height: 759))
        #expect(commands(r).contains("fillRect(0, 0, 393, 852) #0000FF"), "\(commands(r))")
    }

    @Test func aGeometryReaderReportsTheBarsAndIsTheSafeSize() {
        let r = runtime(GeometryReader { geo in
            Color.red.frame(width: geo.safeAreaInsets.top, height: geo.safeAreaInsets.bottom)._probe("depths")
        }._probe("reader"))
        #expect(r.probeFrames["reader"] == CGRect(x: 0, y: 59, width: 393, height: 759))
        #expect(r.probeFrames["depths"]?.size == CGSize(width: 59, height: 34))
    }

    @Test func aBottomBarIgnoringTheBottomSitsOnTheHomeIndicator() {
        // Paulo's tab bar: 25 above the screen's bottom, not the safe area's.
        let r = runtime(ZStack(alignment: .bottom) {
            Color.clear
            Color.red.frame(height: 50)._probe("bar").padding(.bottom, 25).ignoresSafeArea(edges: .bottom)
        })
        #expect(r.probeFrames["bar"] == CGRect(x: 0, y: 852 - 25 - 50, width: 393, height: 50))
    }

    @Test func aScrollViewShowsItsContentUnderTheBars() {
        let r = runtime(ZStack { ScrollView { Color.red.frame(height: 2000)._probe("content") } })
        // At rest the content starts at the safe top; the clip reaches the screen's edges.
        #expect(r.probeFrames["content"]?.minY == 59)
        #expect(commands(r).contains { $0.hasPrefix("clipRect(0, 0, 393, 852") }, "\(commands(r).filter { $0.hasPrefix("clip") })")
    }

    @Test func aFullScreenCoverLaysItsContentOutInTheSafeArea() {
        let r = runtime(Color.white.fullScreenCover(isPresented: .constant(true)) {
            VStack { Spacer(); Color.red.frame(height: 50)._probe("button") }
        })
        #expect(r.probeFrames["button"] == CGRect(x: 0, y: 852 - 34 - 50, width: 393, height: 50))
    }

    @Test func aSheetStartsAtTheSafeTopAndKeepsClearOfTheHomeIndicator() {
        let r = runtime(Color.white.sheet(isPresented: .constant(true)) { Color.red._probe("card") })
        // The card from 59 to the bottom; plain content stops 34 above it.
        #expect(r.probeFrames["card"] == CGRect(x: 0, y: 59, width: 393, height: 852 - 59 - 34))
        // A scroll view in the sheet reaches the card's bottom and insets its content instead.
        let scrolled = runtime(Color.white.sheet(isPresented: .constant(true)) {
            ScrollView { Color.red.frame(height: 2000) }._probe("scroll")
        })
        #expect(scrolled.probeFrames["scroll"] == CGRect(x: 0, y: 59, width: 393, height: 852 - 59))
        // Its `safeAreaInset` footer sits above the home indicator (Paulo's tall sheets).
        let footed = runtime(Color.white.sheet(isPresented: .constant(true)) {
            ScrollView { Color.red.frame(height: 2000) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.blue.frame(height: 50)._probe("footer") }
        })
        #expect(footed.probeFrames["footer"] == CGRect(x: 0, y: 852 - 34 - 50, width: 393, height: 50))
    }

    @Test func withoutASafeAreaASheetStillStartsAtItsMeasuredInset() {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(Color.white.sheet(isPresented: .constant(true)) { Color.red._probe("card") })
        for _ in 0..<3 { r.layout(in: window); r.advanceAnimations(elapsed: 1) }
        #expect(r.probeFrames["card"]?.minY == 21)
    }
}
#endif
