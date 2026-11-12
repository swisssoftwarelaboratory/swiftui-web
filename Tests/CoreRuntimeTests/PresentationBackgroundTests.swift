// presentationBackground: a full-screen cover or sheet fills with the content's style instead
// of the system background, and a clear one shows what is behind (an app that draws its own
// dim and card in a cover: the screen under it stays visible).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PresentationBackgroundTests {
    private struct Screen<Cover: View>: View {
        let cover: Cover
        var body: some View {
            Color(red: 1, green: 0, blue: 0)
                .fullScreenCover(isPresented: .constant(true)) { cover }
        }
    }

    private func painted<V: View>(_ view: V) -> [String] {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(view)
        for _ in 0..<3 { r.layout(in: CGSize(width: 393, height: 852)); r.advanceAnimations(elapsed: 1) }
        return r.render(scale: 1).commands.map(\.description)
    }

    /// The commands painted after the screen's red: what covers it.
    private func over(_ commands: [String]) -> [String] {
        guard let red = commands.lastIndex(where: { $0.contains("#FF0000") }) else { return commands }
        return Array(commands[(red + 1)...])
    }

    @Test func aClearCoverShowsTheScreenBehind() {
        let commands = over(painted(Screen(cover: Text("Sheet").presentationBackground(.clear))))
        // Nothing fills the window over the red: no system ground, no floating card.
        #expect(!commands.contains { $0.hasPrefix("fill") && $0.contains("393") && $0.contains("852") }, "\(commands)")
    }

    @Test func aCoverWithoutABackgroundHasTheSystemGroundAndNoCard() {
        let commands = over(painted(Screen(cover: Text("Sheet"))))
        let fills = commands.filter { $0.hasPrefix("fill") && $0.contains("393") && $0.contains("852") }
        #expect(fills.count == 1 && fills[0].hasPrefix("fillRect"), "\(fills)")
    }

    @Test func aColoredCoverFillsWithItsColor() {
        let commands = over(painted(Screen(cover: Text("Sheet").presentationBackground(Color(red: 0, green: 0, blue: 1)))))
        #expect(commands.contains { $0.hasPrefix("fill") && $0.contains("#0000FF") }, "\(commands)")
    }
}
#endif
