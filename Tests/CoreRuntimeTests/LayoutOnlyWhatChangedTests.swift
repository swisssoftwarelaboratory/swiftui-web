// A change lays out what it touches, not the screen around it (new-website#216: a real app laid
// out 10,000 views on every keystroke and scroll step). A geometry reader builds its content
// again only when its size, safe area, value or the state its closure read changed, or on every
// pass when the content asked where the reader is; a reader of its size alone leaves a scroll
// view on the fast path; actions queued by `onGeometryChange` run before the frame decides to lay
// out; a navigation stack works its bars out once until something under it changes; a moved
// caret or focus ring keeps every memoised size.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)

@MainActor private final class Count { var value = 0 }
@MainActor private final class Seen { var label = ""; var ys: [CGFloat] = [] }

@Observable private final class Field { var text = "" }
@Observable private final class Labels { var label = "a"; var unread: CGFloat = 0 }

/// Reads only the field: typing re-evaluates this view alone.
private struct Typing: View {
    let field: Field
    var body: some View { Text(field.text.isEmpty ? "empty" : field.text) }
}

/// A screen wrapped in a geometry reader that reads its size only (an app's tab).
private struct SizedScreen: View {
    let builds: Count
    var body: some View {
        GeometryReader { proxy in
            let _ = { builds.value += 1 }()
            VStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { row in
                    Text("row \(row)").frame(width: proxy.size.width / 2, height: 10)
                }
            }
        }
    }
}

/// The same screen asking where it is.
private struct PlacedScreen: View {
    let builds: Count
    var body: some View {
        GeometryReader { proxy in
            let _ = { builds.value += 1; _ = proxy.frame(in: .global) }()
            Color.red
        }
    }
}

private struct Labelled: View {
    let label: String
    let builds: Count
    let seen: Seen
    var body: some View {
        GeometryReader { _ in
            let _ = { builds.value += 1; seen.label = label }()
            Color.red
        }
    }
}

private struct LabelledRoot: View {
    let labels: Labels
    let builds: Count
    let seen: Seen
    var body: some View { Labelled(label: labels.label, builds: builds, seen: seen).frame(width: 50, height: 50) }
}

/// A search field with its own query (a real app's meal search, a tab away from its home screen).
private struct SearchField: View {
    @State var query = ""
    var body: some View {
        TextField("Search", text: $query)
        Text(query.isEmpty ? "all" : query)
    }
}

/// The field over a screen wrapped in a size reader.
private struct SearchOverScreen: View {
    let builds: Count
    var body: some View {
        VStack(spacing: 0) {
            SearchField()
            SizedScreen(builds: builds).frame(height: 400)
        }
    }
}

/// Pages sized to their pager (a real app's swipe pagers on its home screen), inside a vertical scroll.
private struct Pagers: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    // Beside a flexible view, the stack asks the pager for its least and most
                    // height before the one it gets: three visible sizes in one pass.
                    VStack(spacing: 0) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { page in
                                    VStack { Text("page \(page)"); Color.blue.frame(minHeight: 20) }
                                        .containerRelativeFrame(.horizontal)
                                }
                            }
                        }
                        Color.red
                    }
                    .frame(height: 100)
                }
            }
        }
    }
}

/// A screen that hides its bar, reading a field's text (a real app's meal search).
private struct BarlessSearch: View {
    let field: Field
    var body: some View {
        VStack { Text(field.text.isEmpty ? "all" : field.text); ForEach(0..<30, id: \.self) { Text("row \($0)") } }
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// A button style with no stored properties (a real app's press style).
private struct DimmingStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.5 : 1) }
}

/// A screen whose body reads the query and styles its rows (a real app's meal search).
private struct StyledRows: View {
    let field: Field
    var body: some View {
        VStack {
            Text(field.text.isEmpty ? "all" : field.text)
            ForEach(0..<20, id: \.self) { row in
                Button {} label: {
                    HStack { Text("row \(row)").foregroundStyle(.secondary); Spacer(); Text("\(row * 10) g").foregroundColor(.orange) }
                }
                .buttonStyle(DimmingStyle())
            }
            .foregroundStyle(Color.blue)
            .font(.headline)
            .disabled(false)
            .contentMargins(.horizontal, 8)
            .scrollIndicators(.never)
            .environment(\.lineLimit, 2)
        }
    }
}

/// A sub-screen column wrapped in a reader, with an equal scroll anchor written inside it each
/// time (a real app's sub-screen column), around rows that read nothing from the query.
private struct ReaderColumn: View {
    let field: Field
    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack {
                    Text(field.text.isEmpty ? "all" : field.text)
                    ForEach(0..<20, id: \.self) { row in HStack { Text("row \(row)"); Spacer(); Text("\(row) g") } }
                }
            }
            .defaultScrollAnchor(.top)
        }
    }
}

private struct TitledRoot: View {
    let labels: Labels
    var body: some View { Text("Body").navigationTitle(labels.label) }
}

@Suite @MainActor struct LayoutOnlyWhatChangedTests {
    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 600)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func aChangeBesideASizeReaderKeepsItsContent() {
        let field = Field(), builds = Count()
        let r = runtime(VStack(spacing: 0) { Typing(field: field); SizedScreen(builds: builds).frame(height: 400) })
        #expect(builds.value == 1)
        let full = r.lastLayoutComputes
        field.text = "c"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutReason.hasPrefix("update"))
        #expect(builds.value == 1, "the reader's size did not change, so its content is kept")
        #expect(r.lastLayoutComputes < 15, "only the typed text and its ancestors are measured again, not the \(full) of the first pass")
    }

    @Test func aNewSizeBuildsTheContentAgain() {
        let builds = Count()
        let r = runtime(SizedScreen(builds: builds).frame(height: 400))
        r.layout(in: CGSize(width: 300, height: 600))
        #expect(builds.value == 2)
    }

    @Test func aNewValueFromTheParentBuildsTheContentAgain() {
        let labels = Labels(), builds = Count(), seen = Seen()
        let r = runtime(LabelledRoot(labels: labels, builds: builds, seen: seen))
        #expect(seen.label == "a")
        labels.label = "b"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(seen.label == "b")
        #expect(builds.value == 2)
    }

    @Test func stateReadInTheClosureBuildsTheContentAgain() {
        let labels = Labels(), seen = Seen()
        let r = runtime(GeometryReader { _ in
            let _ = { seen.label = labels.label }()
            Color.red
        })
        labels.label = "b"
        #expect(r.needsFrame, "the closure's read of the label is observed")
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(seen.label == "b")
    }

    @Test func aPositionReaderBuildsItsContentOnEveryPass() {
        let field = Field(), builds = Count()
        let r = runtime(VStack(spacing: 0) { Typing(field: field); PlacedScreen(builds: builds).frame(height: 100) })
        field.text = "c"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(builds.value == 2)
    }

    @Test func aSizeReaderInScrolledContentKeepsTheFastPath() {
        let r = runtime(ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { _ in Color.blue.frame(width: 100, height: 20) }
                GeometryReader { proxy in Color.red.frame(width: proxy.size.width / 2) }.frame(height: 20)
            }
        }, size: CGSize(width: 100, height: 100))
        let layouts = r.fullLayoutCount
        r.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 50, y: 50))
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(r.lastLayoutReason == "moved")
        #expect(r.fullLayoutCount == layouts)
    }

    /// An app reporting its views' screen positions (a guided tour's targets) into state no view
    /// reads: scrolling stays a move, and the positions still arrive.
    @Test func geometryChangesFollowMovedContentWithoutLayingOut() {
        let labels = Labels(), seen = Seen()
        let r = runtime(ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { _ in Color.blue.frame(width: 100, height: 20) }
                Color.red.frame(height: 20)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { y in
                        seen.ys.append(y)
                        labels.unread = y
                    }
            }
        }, size: CGSize(width: 100, height: 100))
        r.layout(in: CGSize(width: 100, height: 100))   // the first report's action
        let layouts = r.fullLayoutCount
        r.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 50, y: 50))
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(r.lastLayoutReason == "moved")
        #expect(r.needsFrame, "the moved position queued the action")
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(r.fullLayoutCount == layouts, "the action changed nothing a view reads")
        #expect(seen.ys.first == 400 && seen.ys.last == 350, "\(seen.ys)")
        #expect(!r.needsFrame)
    }

    @Test func queuedActionsThatChangeAViewStillLayOut() {
        let field = Field()
        let r = runtime(VStack { Typing(field: field) }, size: CGSize(width: 200, height: 100))
        let layouts = r.fullLayoutCount
        r.scheduler.enqueue { field.text = "typed" }
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.lastLayoutReason.hasPrefix("update"))
        #expect(r.fullLayoutCount == layouts + 1)
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"typed\"") })
    }

    /// A keystroke moves the caret too: that repaint keeps every memoised size, so the frame
    /// measures the field and the text that shows the query, not the screen beside them.
    @Test func typingMeasuresWhatTheTextChanged() {
        let builds = Count()
        let r = runtime(SearchOverScreen(builds: builds))
        let field = r.semanticsTree().first { $0.role == .textField }!
        let full = r.lastLayoutComputes
        // Focusing (once per visit to the field) may still measure everything.
        r.focus(semanticsIdentifier: field.identifier)
        r.layout(in: CGSize(width: 200, height: 600))
        let focusedBuilds = builds.value
        r.textField(field.identifier, didChange: "c")
        r.textField(field.identifier, selectionStart: 1, end: 1)
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutComputes < 25, "a keystroke measured \(r.lastLayoutComputes) of \(full)")
        #expect(builds.value == focusedBuilds)
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"c\"") })
        r.textField(field.identifier, selectionStart: 0, end: 0)
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutComputes == 0, "the caret alone measures nothing")
    }

    /// A pager is measured for several heights in a pass (a stack asks for its least and most
    /// height): pages as wide as the pager ignore the heights, so asking again for the same
    /// heights measures nothing, where each change of height made the pages and every view above
    /// them forget their sizes.
    @Test func pagesIgnoreThePagersHeights() {
        let field = Field()
        let r = runtime(VStack(spacing: 0) { Typing(field: field); Pagers().frame(height: 500) })
        let pages = r.root.descendants(where: { $0.nodeDescription == "ContainerRelativeFrame" })
        #expect(pages.count == 12 && pages.allSatisfy { $0.frame.width == 200 })
        let scroll = sequence(first: pages[0], next: { $0.parent }).first { $0 is any _Scrollable && $0 !== pages[0] }!
        let heights: [CGFloat?] = [0, 40, .infinity, nil]
        for height in heights { _ = scroll.sizeThatFits(ProposedViewSize(width: 200, height: height)) }
        r.computeCount = 0
        for height in heights { _ = scroll.sizeThatFits(ProposedViewSize(width: 200, height: height)) }
        #expect(r.computeCount == 0, "asking again measured \(r.computeCount)")
        field.text = "c"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutComputes < 15, "a change beside the pagers measured \(r.lastLayoutComputes)")
    }

    /// The screen sets its bar's visibility again with every update; unchanged, it keeps every
    /// memoised size (it made each keystroke measure the whole app).
    @Test func anUnchangedBarVisibilityKeepsTheSizes() {
        let field = Field()
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.textEngine = MetricsTextEngine()
        r.mount(NavigationStack { BarlessSearch(field: field) })
        r.layout(in: CGSize(width: 320, height: 800))
        let full = r.lastLayoutComputes
        field.text = "c"
        r.layout(in: CGSize(width: 320, height: 800))
        #expect(!r.lastLayoutReason.contains("sizes invalidated"), "\(r.lastLayoutReason)")
        #expect(r.lastLayoutComputes < full / 2, "a change of the text measured \(r.lastLayoutComputes) of \(full)")
    }

    /// An update places what it changed and the path to it; the rest keeps its placement, and
    /// the window draws exactly as when everything is placed again.
    @Test func anUpdateKeepsThePlacementsBesideIt() {
        func run(keeping: Bool) -> (kept: Int, drawn: [String]) {
            let field = Field(), builds = Count()
            let r = Runtime()
            r.textEngine = MetricsTextEngine()
            r.keepsPlacements = keeping
            r.mount(VStack(spacing: 0) {
                Typing(field: field)
                SizedScreen(builds: builds).frame(height: 300)
                ScrollView { VStack { ForEach(0..<30, id: \.self) { Text("item \($0)") } } }.frame(height: 200)
            })
            r.layout(in: CGSize(width: 200, height: 600))
            r.scrollWheel(by: CGSize(width: 0, height: 40), at: CGPoint(x: 100, y: 500))
            r.layout(in: CGSize(width: 200, height: 600))
            field.text = "a much longer typed text"
            r.layout(in: CGSize(width: 200, height: 600))
            return (r.keptPlacements, r.render(scale: 2).commands.map(\.description))
        }
        let kept = run(keeping: true), all = run(keeping: false)
        #expect(kept.kept > 0)
        #expect(all.kept == 0)
        #expect(kept.drawn == all.drawn)
    }

    /// The body runs again with the same `.font`, `.environment`, foreground, `disabled`,
    /// `contentMargins`, `scrollIndicators` and button style: the rows under them keep their sizes.
    @Test func equalEnvironmentWritesKeepTheSizes() {
        let field = Field()
        let r = runtime(StyledRows(field: field))
        let full = r.lastLayoutComputes
        field.text = "c"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutComputes < full / 4, "the query measured \(r.lastLayoutComputes) of \(full)")
    }

    /// The reader builds its content again when its parent's body runs, by force; an equal
    /// environment write inside keeps its content's generation, so the rows keep their sizes.
    @Test func aForcedRebuildKeepsEqualEnvironments() {
        let field = Field()
        let r = runtime(ReaderColumn(field: field))
        let full = r.lastLayoutComputes
        field.text = "c"
        r.layout(in: CGSize(width: 200, height: 600))
        #expect(r.lastLayoutComputes < full / 4, "the query measured \(r.lastLayoutComputes) of \(full)")
    }

    @Test func aRememberedBarFollowsItsTitle() {
        let labels = Labels()
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.textEngine = MetricsTextEngine()
        r.mount(NavigationStack { TitledRoot(labels: labels) })
        r.layout(in: CGSize(width: 320, height: 480))
        let drawn = { r.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(") } }
        #expect(drawn().contains { $0.hasPrefix("drawText(\"a\"") })
        // A frame with nothing new paints the same bar.
        r.setNeedsDisplay()
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(drawn().contains { $0.hasPrefix("drawText(\"a\"") })
        labels.label = "Second"
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(drawn().contains { $0.hasPrefix("drawText(\"Second\"") }, "\(drawn())")
        #expect(!drawn().contains { $0.hasPrefix("drawText(\"a\"") })
    }
}
#endif
