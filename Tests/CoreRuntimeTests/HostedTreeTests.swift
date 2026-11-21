// A live view tree the drawn iPhone hosts (new-website#643): a countdown shown once keeps ticking.
import SwiftUI
import SwiftUIWebCore
import Testing

#if !os(WASI)
extension NotificationCentreSuites {
@Suite @MainActor struct HostedTreeTests {
    @Test func aLiveTextAsksForRepaints() async throws {
        let host = Runtime()
        let end = Date().addingTimeInterval(90)
        let tree = _HostedTree(AnyView(Text(timerInterval: Date()...end, countsDown: true)), host: host)
        var asks = 0
        tree.onNeedsRepaint = { asks += 1 }
        tree.layout(width: 300)
        var list = DisplayList()
        tree.paint(into: &list, at: .zero, scale: 2)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        #expect(asks > 0)
        #expect(tree.needsFrame)
    }
}
}
#endif
