// UIViewRepresentable / UIViewControllerRepresentable (decision 0014, Phase 2): a UIKit view
// tree hosted as a SwiftUI leaf. Sizing from the view's intrinsic size and priorities or the
// representable's own rule, painting at the node's position, presses turned into touches,
// bindings flowing both ways through the coordinator, the semantics tree, text input and focus
// through the host's callbacks, appearance callbacks, and dismantling.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

@Suite @MainActor struct RepresentableTests {
    /// Counters the tests read, outside observation: an update that wrote an observed property
    /// would invalidate itself (SwiftUI forbids state writes during an update too).
    final class Counts {
        var updates = 0
        var dismantled = 0
        var appearances: [String] = []
    }

    @Observable final class Model {
        var isOn = false
        var text = "Hello"
        var showsLabel = true
        @ObservationIgnored let counts = Counts()
        var updates: Int { counts.updates }
        var dismantled: Int { counts.dismantled }
        var appearances: [String] { counts.appearances }
    }

    /// A label: an intrinsic size on both axes.
    struct LabelView: UIViewRepresentable {
        let text: String
        let model: Model
        func makeUIView(context: Context) -> UILabel {
            let label = UILabel()
            label.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .vertical)
            return label
        }
        func updateUIView(_ uiView: UILabel, context: Context) {
            uiView.text = text
            model.counts.updates += 1
        }
        static func dismantleUIView(_ uiView: UILabel, coordinator: Void) {}
    }

    /// A plain view without an intrinsic size.
    struct PlainView: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
            return view
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// A view that sizes itself.
    struct SizedView: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ uiView: UIView, context: Context) {}
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
            CGSize(width: 44, height: 22)
        }
    }

    /// A switch bound to the model through its coordinator.
    struct SwitchView: UIViewRepresentable {
        @Bindable var model: Model

        final class Coordinator {
            var isOn: Binding<Bool>
            init(isOn: Binding<Bool>) { self.isOn = isOn }
        }

        func makeCoordinator() -> Coordinator { Coordinator(isOn: $model.isOn) }

        func makeUIView(context: Context) -> UISwitch {
            let toggle = UISwitch()
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            toggle.setContentHuggingPriority(.required, for: .vertical)
            let coordinator = context.coordinator
            toggle.addAction(UIAction { action in
                guard let toggle = action.sender as? UISwitch else { return }
                coordinator.isOn.wrappedValue = toggle.isOn
            }, for: .valueChanged)
            return toggle
        }

        func updateUIView(_ uiView: UISwitch, context: Context) {
            uiView.isOn = model.isOn
            context.coordinator.isOn = $model.isOn
            model.counts.updates += 1
        }
    }

    /// A text field bound to the model.
    struct FieldView: UIViewRepresentable {
        @Bindable var model: Model
        func makeUIView(context: Context) -> UITextField {
            let field = UITextField()
            field.borderStyle = .roundedRect
            field.setContentHuggingPriority(.required, for: .vertical)
            field.addAction(UIAction { action in
                if let field = action.sender as? UITextField { model.text = field.text ?? "" }
            }, for: .editingChanged)
            return field
        }
        func updateUIView(_ uiView: UITextField, context: Context) { uiView.text = model.text }
    }

    struct Dismantling: UIViewRepresentable {
        let model: Model
        final class Coordinator { let model: Model; init(_ model: Model) { self.model = model } }
        func makeCoordinator() -> Coordinator { Coordinator(model) }
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ uiView: UIView, context: Context) {}
        static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.model.counts.dismantled += 1 }
    }

    /// A view that records the safe area and traits it is laid out with.
    final class ObservingView: UIView {
        var seenInsets = UIEdgeInsets.zero
        var seenTraits = UITraitCollection()
        var seenSizes: [CGSize] = []
        override func layoutSubviews() {
            super.layoutSubviews()
            seenInsets = safeAreaInsets
            seenTraits = traitCollection
            seenSizes.append(bounds.size)
        }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            seenTraits = traitCollection
        }
    }

    struct Observing: UIViewRepresentable {
        let view: ObservingView
        let model: Model
        func makeUIView(context: Context) -> ObservingView { view }
        func updateUIView(_ uiView: ObservingView, context: Context) { model.counts.updates += 1 }
    }

    /// The same without safe-area propagation.
    struct Unpropagated: UIViewRepresentable {
        let view: ObservingView
        func makeUIView(context: Context) -> ObservingView { view }
        func updateUIView(_ uiView: ObservingView, context: Context) {}
        static func _layoutOptions(_ provider: ObservingView) -> LayoutOptions { [] }
    }

    /// The environment around the observing view follows the model.
    struct TraitScreen: View {
        let model: Model
        let view: ObservingView
        var body: some View {
            Observing(view: view, model: model).environment(\.colorScheme, model.isOn ? .dark : .light)
        }
    }

    final class LoggingController: UIViewController {
        /// No archive to decode on the web: nil, as for an archive this class cannot read.
        required init?(coder: NSCoder) { return nil }

        let model: Model
        init(_ model: Model) { self.model = model; super.init(nibName: nil, bundle: nil) }
        override func viewDidLoad() { super.viewDidLoad(); model.counts.appearances.append("load") }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); model.counts.appearances.append("willAppear") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); model.counts.appearances.append("didAppear") }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); model.counts.appearances.append("willDisappear") }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); model.counts.appearances.append("layout \(Int(view.bounds.width))x\(Int(view.bounds.height))") }
    }

    struct ControllerView: UIViewControllerRepresentable {
        let model: Model
        func makeUIViewController(context: Context) -> LoggingController { LoggingController(model) }
        func updateUIViewController(_ uiViewController: LoggingController, context: Context) {}
    }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack(spacing: 0) {
                if model.showsLabel {
                    LabelView(text: model.text, model: model)._probe("label")
                }
                PlainView().frame(width: 120, height: 40)._probe("plain")
                SizedView()._probe("sized")
                SwitchView(model: model)._probe("switch")
                FieldView(model: model).frame(width: 150)._probe("field")
                Dismantling(model: model).frame(width: 10, height: 10)._probe("dismantling")
                ControllerView(model: model).frame(width: 100, height: 30)._probe("controller")
            }
            .padding(10)
        }
    }

    private static let size = CGSize(width: 300, height: 400)

    private func runtime(_ model: Model) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let font = UIFont.systemFont(ofSize: 17).resolved
        for (word, width) in [("Hello", 41.5), ("Hello!", 46), ("Longer text", 90)] {
            for options in [TextLayoutOptions.default, TextLayoutOptions(lineLimit: 1)] {
                entries[TextMetricsKey.make(runs: [StyledRun(word, font: font)], options: options, width: nil)] =
                    .init(width: width, height: 20.5, firstBaseline: 16, lastBaseline: 16)
            }
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(Screen(model: model))
        runtime.layout(in: Self.size)
        return runtime
    }

    @Test func sizesFollowIntrinsicSizePrioritiesAndOverrides() {
        let model = Model()
        let r = runtime(model)
        let label = r.probeFrames["label"]!
        // The label hugs its text on both axes: the recorded 41.5 rounds up to the pixel (41.5)
        // and the height is UIFont's one-line label height for 17 pt.
        #expect(label.width == 41.5)
        #expect(label.height > 19 && label.height < 22)
        let centredX: CGFloat = 10 + (280 - 41.5) / 2
        #expect(label.minX == centredX)
        // A plain view fills what its frame proposes.
        #expect(r.probeFrames["plain"]!.size == CGSize(width: 120, height: 40))
        // The representable's own rule wins.
        #expect(r.probeFrames["sized"]!.size == CGSize(width: 44, height: 22))
        // A switch hugs its content: the iOS 26 switch's 68 × 30 intrinsic size less its 2 pt
        // alignment inset on the right.
        #expect(r.probeFrames["switch"]!.size == CGSize(width: 66, height: 30))
        // A text field hugging vertically has an intrinsic height but no width: the frame's 150
        // across, 34 tall.
        #expect(r.probeFrames["field"]!.size == CGSize(width: 150, height: 34))
    }

    @Test func paintsAtTheNodesPosition() {
        let model = Model()
        let r = runtime(model)
        let plain = r.probeFrames["plain"]!
        let commands = r.render(scale: 2).commands.map(\.description)
        // The plain view's blue background is a rect at its frame.
        let blueRects = commands.filter { $0.contains("fillRect") && $0.contains("#0000FF") }
        // (frames are painted on the pixel grid: the y rounds to the half point)
        #expect(blueRects.count == 1 && blueRects[0].hasPrefix("fillRect(\(Int(plain.minX)), ") && blueRects[0].hasSuffix("120, 40) #0000FF"), "\(commands)")
        // The label's text is drawn in UIKit's 17 pt system font.
        #expect(commands.contains { $0.contains("drawText(\"Hello\"") && $0.contains("17") })
    }

    @Test func pressesBecomeTouchesAndBindingsFlowBack() {
        let model = Model()
        let r = runtime(model)
        let toggle = r.probeFrames["switch"]!
        let updates = model.updates
        r.pointerDown(at: CGPoint(x: toggle.midX, y: toggle.midY))
        r.pointerUp(at: CGPoint(x: toggle.midX, y: toggle.midY))
        #expect(model.isOn == true)
        // The change comes back through updateUIView on the next frame.
        #expect(r.needsFrame)
        r.layout(in: Self.size)
        #expect(model.updates > updates)
        // And a model change reaches the view.
        model.isOn = false
        r.layout(in: Self.size)
        let semantics = r.semanticsTree()
        let element = semantics.first { $0.role == .switch }!
        #expect(element.isOn == false)
    }

    @Test func semanticsListTheTreesElementsAtTheirFrames() {
        let model = Model()
        let r = runtime(model)
        let semantics = r.semanticsTree()
        let toggle = semantics.first { $0.role == .switch }!
        // The element's frame is the UIKit view's: the alignment rect plus the switch's inset.
        let alignment = r.probeFrames["switch"]!
        #expect(toggle.frame == CGRect(x: alignment.minX, y: alignment.minY, width: alignment.width + 2, height: alignment.height))
        #expect(toggle.identifier >= 20_000_000)
        let label = semantics.first { $0.role == .text && $0.label == "Hello" }!
        #expect(label.frame == r.probeFrames["label"]!)
        // Activation through the accessibility overlay flips the switch.
        r.activate(semanticsIdentifier: toggle.identifier)
        #expect(model.isOn == true)
        // A field element carries its text input, with the text rect in window coordinates.
        let field = semantics.first { $0.role == .textField }!
        #expect(field.textInput?.text == "Hello")
        #expect(r.probeFrames["field"]!.contains(field.textInput!.textRect))
    }

    @Test func textInputAndFocusRouteThroughTheHost() {
        let model = Model()
        let r = runtime(model)
        let field = r.semanticsTree().first { $0.role == .textField }!
        r.textField(field.identifier, didChange: "Hello!")
        #expect(model.text == "Hello!")
        // The label follows the model: a wider text, a wider label.
        r.layout(in: Self.size)
        #expect(r.probeFrames["label"]!.width == 46)
        // Focus from the host's input makes the field the first responder and the runtime's
        // focused text field.
        r.textField(field.identifier, focused: true)
        #expect(r.focusedTextFieldIdentifier == field.identifier)
        #expect(r.focusedIdentifier == field.identifier)
        // A press elsewhere moves focus away: the field resigns.
        r.focus(semanticsIdentifier: nil)
        #expect(r.focusedTextFieldIdentifier == nil)
        #expect(r.semanticsTree().first { $0.role == .textField } != nil)
        r.textField(field.identifier, focused: true)
        #expect(r.focusedTextFieldIdentifier == field.identifier)
        r.textField(field.identifier, focused: false)
        #expect(r.focusedTextFieldIdentifier == nil)
    }

    private func iOSRuntime() -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        return Runtime(environment: environment)
    }

    /// ios/representable/safearea, safearea-ignored: a representable laid out inside the safe
    /// area sees no insets; one that ignores it is laid out under the bar and sees the bar as its
    /// top inset, unless its layout options do not propagate the safe area.
    @Test func safeAreaReachesTheViewWhereItExtendsIntoIt() {
        let model = Model()
        let size = CGSize(width: 200, height: 100)
        let plain = ObservingView()
        plain.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let r1 = iOSRuntime()
        r1.mount(ZStack { Observing(view: plain, model: model)._probe("box") }.safeAreaPadding(.top, 30))
        r1.layout(in: size)
        #expect(r1.probeFrames["box"] == CGRect(x: 0, y: 30, width: 200, height: 70))
        #expect(plain.seenInsets == .zero)
        #expect(r1.render(scale: 2).commands.map(\.description).contains("fillRect(0, 30, 200, 70) #0000FF"))

        let ignoring = ObservingView()
        ignoring.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let r2 = iOSRuntime()
        r2.mount(ZStack { Observing(view: ignoring, model: model).ignoresSafeArea()._probe("box") }.safeAreaPadding(.top, 30))
        r2.layout(in: size)
        // The modifier's frame stays the safe one; the view fills the window and sees 30 above.
        #expect(r2.probeFrames["box"] == CGRect(x: 0, y: 30, width: 200, height: 70))
        #expect(ignoring.seenInsets == UIEdgeInsets(top: 30, left: 0, bottom: 0, right: 0))
        #expect(r2.render(scale: 2).commands.map(\.description).contains("fillRect(0, 0, 200, 100) #0000FF"))

        let unpropagated = ObservingView()
        let r3 = iOSRuntime()
        r3.mount(ZStack { Unpropagated(view: unpropagated).ignoresSafeArea() }.safeAreaPadding(.top, 30))
        r3.layout(in: size)
        #expect(unpropagated.frame.height == 100)
        #expect(unpropagated.seenInsets == .zero)
    }

    /// ios/representable/traits: the environment is the hosted view's trait collection, and
    /// `updateUIView` runs when it changes.
    @Test func environmentBecomesTheTraitCollection() {
        let model = Model()
        let view = ObservingView()
        let r = iOSRuntime()
        r.mount(Observing(view: view, model: model)
            .environment(\.colorScheme, .dark).dynamicTypeSize(.xxxLarge)
            .environment(\.layoutDirection, .rightToLeft).environment(\.horizontalSizeClass, .regular))
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(view.seenTraits.userInterfaceStyle == .dark)
        #expect(view.seenTraits.preferredContentSizeCategory == .extraExtraExtraLarge)
        #expect(view.seenTraits.layoutDirection == .rightToLeft)
        #expect(view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(view.seenTraits.horizontalSizeClass == .regular)
        #expect(view.seenTraits.verticalSizeClass == .regular)

        // The iOS profile's defaults: light, large, left to right, compact × regular.
        let plain = ObservingView()
        let defaults = iOSRuntime()
        defaults.mount(Observing(view: plain, model: model))
        defaults.layout(in: CGSize(width: 200, height: 100))
        #expect(plain.seenTraits.userInterfaceStyle == .light)
        #expect(plain.seenTraits.preferredContentSizeCategory == .large)
        #expect(plain.seenTraits.layoutDirection == .leftToRight)
        #expect(plain.seenTraits.horizontalSizeClass == .compact)
        #expect(plain.seenTraits.verticalSizeClass == .regular)

        // A change of the environment updates the view and its traits.
        let following = ObservingView()
        let changing = iOSRuntime()
        changing.mount(TraitScreen(model: model, view: following))
        changing.layout(in: CGSize(width: 200, height: 100))
        #expect(following.seenTraits.userInterfaceStyle == .light)
        let updates = model.updates
        model.isOn = true
        changing.layout(in: CGSize(width: 200, height: 100))
        #expect(model.updates == updates + 1)
        #expect(following.seenTraits.userInterfaceStyle == .dark)
    }

    /// The calls a representable receives, recorded outside observation.
    final class CallLog { var entries: [String] = [] }

    @Observable final class LifecycleModel {
        var identity = 0
        var shows = true
        var tick = 0
        @ObservationIgnored let log = CallLog()
    }

    struct Logging: UIViewRepresentable {
        let log: CallLog
        final class Coordinator {
            let log: CallLog
            let number: Int
            init(log: CallLog, number: Int) { self.log = log; self.number = number; log.entries.append("coordinator\(number)") }
        }
        func makeCoordinator() -> Coordinator { Coordinator(log: log, number: log.entries.filter { $0.hasPrefix("coordinator") }.count + 1) }
        func makeUIView(context: Context) -> UIView { log.entries.append("make\(context.coordinator.number)"); return UIView() }
        func updateUIView(_ uiView: UIView, context: Context) { log.entries.append("update\(context.coordinator.number)") }
        static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.log.entries.append("dismantle\(coordinator.number)") }
    }

    struct LifecycleScreen: View {
        let model: LifecycleModel
        var body: some View {
            VStack {
                if model.shows { Logging(log: model.log).id(model.identity).frame(width: 100, height: 20) }
                Color.clear.frame(width: CGFloat(model.tick) + 1, height: 1)
            }
        }
    }

    /// ios/representable/lifecycle: the coordinator, the view and one update at first; every
    /// evaluation of the parent's body updates the view again; a new identity makes a new
    /// coordinator and view and updates them before the old view is dismantled; a removal
    /// dismantles.
    @Test func lifecycleOrderMatchesTheSimulator() {
        let model = LifecycleModel()
        let r = iOSRuntime()
        r.mount(LifecycleScreen(model: model))
        r.layout(in: Self.size)
        #expect(model.log.entries == ["coordinator1", "make1", "update1"])
        model.tick = 1
        r.layout(in: Self.size)
        #expect(model.log.entries == ["coordinator1", "make1", "update1", "update1"])
        model.identity = 1
        r.layout(in: Self.size)
        #expect(model.log.entries == ["coordinator1", "make1", "update1", "update1", "coordinator2", "make2", "update2", "dismantle1"])
        model.shows = false
        r.layout(in: Self.size)
        #expect(model.log.entries.suffix(1) == ["dismantle2"])
    }

    /// The coordinator is made once per node, outlives every update and dies with the node.
    @Test func coordinatorLivesWithTheNode() {
        let model = LifecycleModel()
        let r = iOSRuntime()
        r.mount(LifecycleScreen(model: model))
        r.layout(in: Self.size)
        model.tick = 1
        r.layout(in: Self.size)
        model.tick = 2
        r.layout(in: Self.size)
        #expect(model.log.entries.filter { $0.hasPrefix("coordinator") } == ["coordinator1"])
        #expect(model.log.entries.filter { $0.hasPrefix("update") }.count == 3)
        weak var coordinator: Logging.Coordinator?
        do {
            let holder = Logging(log: model.log).makeCoordinator()
            coordinator = holder
        }
        #expect(coordinator == nil)   // nothing else retains a coordinator made outside a node
        model.shows = false
        r.layout(in: Self.size)
        #expect(model.log.entries.last == "dismantle1")
    }

    @Observable final class AnimationModel {
        var wide = false
        var faded = false
        @ObservationIgnored var transactions: [Animation?] = []
    }

    struct AnimatedBox: UIViewRepresentable {
        let model: AnimationModel
        let view: ObservingView
        func makeUIView(context: Context) -> ObservingView { view }
        func updateUIView(_ uiView: ObservingView, context: Context) {
            model.transactions.append(context.transaction.animation)
            if model.faded, uiView.alpha == 1 { UIView.animate(withDuration: 1) { uiView.alpha = 0 } }
        }
    }

    struct AnimatedScreen: View {
        let model: AnimationModel
        let first: ObservingView
        let second: ObservingView
        var body: some View {
            HStack(spacing: 0) {
                AnimatedBox(model: model, view: first).frame(width: model.wide ? 200 : 100, height: 20)
                AnimatedBox(model: model, view: second).frame(width: 50, height: 20)
            }
        }
    }

    /// `context.transaction` carries the animation of the state change; a `withAnimation` that
    /// resizes the representable lays the UIKit view out at every interpolated size; a
    /// `UIView.animate` started in `updateUIView` runs on the host's clock, advanced once per
    /// frame however many representables share the scene.
    @Test func animationsCrossTheSeam() {
        let model = AnimationModel()
        let first = ObservingView(), second = ObservingView()
        let r = iOSRuntime()
        r.mount(AnimatedScreen(model: model, first: first, second: second))
        r.layout(in: Self.size)
        #expect(model.transactions == [nil, nil])
        #expect(first.bounds.width == 100)

        withAnimation(.linear(duration: 1)) { model.wide = true }
        r.layout(in: Self.size)
        #expect(model.transactions.last == .linear(duration: 1))
        _ = r.advanceFrame(elapsed: 0.5)
        r.layout(in: Self.size)
        _ = r.render(scale: 2)
        #expect(first.bounds.width == 150)
        _ = r.advanceFrame(elapsed: 0.6)
        r.layout(in: Self.size)
        _ = r.render(scale: 2)
        #expect(first.bounds.width == 200)

        model.faded = true
        r.layout(in: Self.size)
        #expect(model.transactions.last == .some(nil))
        #expect(UIKitScene.shared.isAnimating)
        #expect(r.advanceFrame(elapsed: 0.6))
        #expect(UIKitScene.shared.isAnimating, "a one-second fade is still running after 0.6 s with two representables")
        #expect(!r.advanceFrame(elapsed: 0.6) || !UIKitScene.shared.isAnimating)
        #expect(!UIKitScene.shared.isAnimating)
        #expect(first.alpha == 0)
    }

    /// A view whose intrinsic size the app changes on its own.
    final class GrowingView: UIView {
        var height: CGFloat = 40 { didSet { invalidateIntrinsicContentSize() } }
        override var intrinsicContentSize: CGSize { CGSize(width: 100, height: height) }
    }

    struct Growing: UIViewRepresentable {
        let view: GrowingView
        let model: Model
        func makeUIView(context: Context) -> GrowingView { view }
        func updateUIView(_ uiView: GrowingView, context: Context) { model.counts.updates += 1 }
    }

    struct GrowingScreen: View {
        let model: Model
        let view: GrowingView
        var body: some View {
            VStack(spacing: 0) {
                Growing(view: view, model: model)._probe("growing")
                Color.clear.frame(width: CGFloat(model.text.count), height: 1)
            }
        }
    }

    /// ios/representable/hostingsizing: SwiftUI measures a representable again only when its
    /// value, environment or proposal changes; a platform view growing on its own keeps the
    /// representable's frame, though the view is updated.
    @Test func sizesAreKeptUntilTheValueChanges() {
        let model = Model()
        let view = GrowingView()
        view.setContentHuggingPriority(.required, for: .vertical)
        let r = iOSRuntime()
        r.mount(GrowingScreen(model: model, view: view))
        r.layout(in: Self.size)
        #expect(r.probeFrames["growing"]?.height == 40)
        view.height = 80
        model.text = "Hello!"
        r.layout(in: Self.size)
        #expect(r.probeFrames["growing"]?.height == 40)
        #expect(model.updates == 2)
        // A new proposal measures again.
        r.layout(in: CGSize(width: 320, height: 500))
        #expect(r.probeFrames["growing"]?.height == 80)
    }

    /// ios/representable/renderedimage: an image an image context drew is replayed at its size,
    /// scaled when resizable, its silhouette in the foreground colour as a template; a tint set
    /// with `withTintColor` alone keeps the drawing's colours; `pngData()` goes through the
    /// host's rasteriser.
    /// An image made from bytes (`UIImage(data:)`, as a photo an app keeps) is the bytes' image
    /// at its pixel size, not a catalog name: a 2 × 3 PNG is 2 × 3 points and draws from its data URL.
    @Test func imagesFromBytesDrawFromTheirData() {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let image = UIImage(data: png)!
        let r = iOSRuntime()
        r.mount(VStack(spacing: 0) {
            Image(uiImage: image)._probe("photo")
            Image(uiImage: image).resizable().frame(width: 40, height: 60)._probe("resized")
        })
        r.layout(in: CGSize(width: 320, height: 300))
        #expect(r.probeFrames["photo"]?.size == CGSize(width: 2, height: 3))
        #expect(r.probeFrames["resized"]?.size == CGSize(width: 40, height: 60))
    }

    @Test func renderedImagesDrawAndRasterize() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
            UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        }
        let r = iOSRuntime()
        r.mount(VStack(spacing: 0) {
            Image(uiImage: image)._probe("natural")
            Image(uiImage: image).resizable().frame(width: 120, height: 80)._probe("resized")
            Image(uiImage: image.withTintColor(UIColor(red: 1, green: 0, blue: 0, alpha: 1)))._probe("tinted")
            Image(uiImage: image.withRenderingMode(.alwaysTemplate)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0))._probe("template")
        })
        r.layout(in: CGSize(width: 320, height: 300))
        #expect(r.probeFrames["natural"]?.size == CGSize(width: 60, height: 40))
        #expect(r.probeFrames["resized"]?.size == CGSize(width: 120, height: 80))
        let painted = r.render(scale: 2).commands.map(\.description)
        let fills = painted.filter { $0.hasPrefix("fill") }
        // The recording's rects, four times: blue and green twice in the original colours (the
        // resizable one under a 2× transform), then the template's two rects in orange.
        #expect(fills.filter { $0.contains("#0000FF") }.count == 3, "\(fills)")
        #expect(fills.filter { $0.contains("#00FF00") }.count == 3, "\(fills)")
        #expect(fills.filter { $0.contains("#FF8000") || $0.contains("#FF7F00") }.count == 2, "\(fills)")
        #expect(painted.contains { $0.hasPrefix("concat(2") }, "the resizable image is scaled twice")

        var rasterized: (commands: Int, size: CGSize, scale: CGFloat)?
        UIKitScene.shared.imageRasterizer = { list, size, scale in
            rasterized = (list.commands.count, size, scale)
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        let png = image.pngData()
        #expect(png?.count == 4)
        #expect(rasterized?.size == CGSize(width: 60, height: 40))
        #expect(rasterized?.commands == image.drawing?.commands.count)
        UIKitScene.shared.imageRasterizer = nil
        #expect(UIImage(systemName: "star")?.pngData() == nil)
    }

    final class Beam: UIPointerInteractionDelegate {
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            UIPointerStyle(shape: .horizontalBeam(length: 20))
        }
    }

    struct Hovering: UIViewRepresentable {
        let states: Counts
        let beam: Beam
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.addGestureRecognizer(UIHoverGestureRecognizer { recognizer in states.appearances.append("hover \(recognizer.state)") })
            view.addInteraction(UIPointerInteraction(delegate: beam))
            return view
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    /// ios/representable/hover: SwiftUI's pointer moves hover the hosted tree (a hover
    /// recognizer begins, changes and ends) and the hovered view's pointer interaction sets the
    /// runtime's pointer style.
    @Test func hoverReachesTheTreeAndItsPointerStyleTheHost() {
        let counts = Counts()
        let beam = Beam()
        let r = iOSRuntime()
        r.mount(VStack(spacing: 0) {
            Hovering(states: counts, beam: beam).frame(width: 100, height: 50)._probe("hover")
            Color.clear.frame(width: 100, height: 50)
        })
        r.layout(in: Self.size)
        let frame = r.probeFrames["hover"]!
        r.pointerMoved(to: CGPoint(x: frame.midX, y: frame.midY))
        #expect(counts.appearances == ["hover began"])
        #expect(r.pointerStyle?.css == "text")
        r.pointerMoved(to: CGPoint(x: frame.midX + 5, y: frame.midY))
        #expect(counts.appearances == ["hover began", "hover changed"])
        r.pointerMoved(to: CGPoint(x: frame.midX, y: frame.maxY + 20))
        #expect(counts.appearances == ["hover began", "hover changed", "hover ended"])
        #expect(r.pointerStyle == nil)
        r.pointerMoved(to: CGPoint(x: frame.midX, y: frame.midY))
        r.pointerLeft()
        #expect(counts.appearances.last == "hover ended")
    }

    @Test func controllersGetAppearanceCallbacksAndDismantlingRuns() {
        let model = Model()
        let r = runtime(model)
        let first: [String] = Array(model.appearances.prefix(2))
        #expect(first == ["load", "willAppear"], "\(model.appearances)")
        #expect(model.appearances.contains("didAppear"))
        #expect(model.appearances.contains("layout 100x30"))
        #expect(r.probeFrames["controller"]!.size == CGSize(width: 100, height: 30))
        // Removing the label from the tree dismantles nothing else; the dismantling view goes
        // when the whole screen does.
        model.showsLabel = false
        r.layout(in: Self.size)
        #expect(r.probeFrames["label"] == nil)
        #expect(model.dismantled == 0)
        r.mount(Text("gone"))
        r.layout(in: Self.size)
        #expect(model.dismantled == 1)
        #expect(model.appearances.contains("willDisappear"))
    }
}
#endif
