// A screen that focuses its field as it appears (`onAppear { focused = true }`, the field's
// `focused` modifier inside a view of its own and an optional modifier, as a search screen
// pushed with its keyboard up does): the text field takes the focus, so the host focuses its input.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct FocusOnAppearTests {
    private struct OptionalFocus: ViewModifier {
        let focused: FocusState<Bool>.Binding?
        func body(content: Content) -> some View {
            if let focused { content.focused(focused) } else { content }
        }
    }

    private struct SearchField: View {
        @Binding var text: String
        var focused: FocusState<Bool>.Binding?
        var body: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField(text: $text) { Text("Search").foregroundStyle(.gray) }
                    .font(.system(size: 17))
                    .tracking(-0.2)
                    .textCase(nil)
                    .lineSpacing(2)
                    .padding(.top, 1)
                    .padding(.bottom, 1)
                    .foregroundStyle(.black)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .modifier(OptionalFocus(focused: focused))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
    }

    private struct Screen: View {
        @State private var query = ""
        @FocusState private var fieldFocused: Bool
        var body: some View {
            ScrollView {
                SearchField(text: $query, focused: $fieldFocused)._probe("field")
            }
            .onAppear { fieldFocused = true }
        }
    }

    private struct Pushing: View {
        @State var path: [Int] = []
        var body: some View {
            NavigationStack(path: $path) {
                Button("Open") { withAnimation(.easeInOut(duration: 0.35)) { path = [1] } }._probe("open")
                    .navigationDestination(for: Int.self) { _ in Screen() }
            }
        }
    }

    /// The state is set before the field exists (the field appears with it): the field takes
    /// the focus as a text field as it mounts, so the host focuses its input, with no ring.
    private struct Late: View {
        @State private var query = ""
        @State private var shown = false
        @FocusState private var fieldFocused: Bool
        var body: some View {
            VStack {
                if shown { SearchField(text: $query, focused: $fieldFocused)._probe("field") }
            }
            .onAppear { fieldFocused = true; shown = true }
        }
    }

    @Test func stateSetBeforeTheFieldExistsFocusesItAsATextField() {
        let r = Runtime()
        r.mount(Late())
        for _ in 0..<3 { r.layout(in: CGSize(width: 393, height: 852)) }
        #expect(r.focusedTextFieldIdentifier != nil)
        #expect(!r.render(scale: 1).commands.map(\.description).contains { $0.contains("w=3 #0067F4") })
    }

    @Test func focusOnAppearFocusesTheField() {
        let r = Runtime()
        r.mount(Screen())
        r.layout(in: CGSize(width: 393, height: 852))
        r.layout(in: CGSize(width: 393, height: 852))
        #expect(r.focusedTextFieldIdentifier != nil)
    }

    @Test func focusOnAppearAfterAPushFocusesTheField() {
        let r = Runtime()
        r.mount(Pushing())
        r.layout(in: CGSize(width: 393, height: 852))
        let f = r.probeFrames["open"]!
        r.pointerDown(at: CGPoint(x: f.midX, y: f.midY)); r.pointerUp(at: CGPoint(x: f.midX, y: f.midY))
        r.layout(in: CGSize(width: 393, height: 852))
        // Focused as a text field while the screen still slides in, and no ring.
        #expect(r.focusedTextFieldIdentifier != nil)
        for _ in 0..<3 { r.advanceAnimations(elapsed: 0.5); r.layout(in: CGSize(width: 393, height: 852)) }
        #expect(r.focusedTextFieldIdentifier != nil)
        #expect(!r.render(scale: 1).commands.map(\.description).contains { $0.contains("w=3 #0067F4") })
    }
}
#endif
