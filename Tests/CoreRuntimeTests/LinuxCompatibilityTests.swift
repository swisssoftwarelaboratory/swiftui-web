// The non-Apple host keeps Foundation's value types and supplies only the missing APIs.
// The geometry cases also exercise the same operations on CoreGraphics and the WASI shims.
import Testing
import SwiftUI
import SwiftUIWebCore
#if !os(WASI)
import Foundation
#endif

@Suite struct LinuxCompatibilityTests {
    #if !os(WASI)
    @Test func nativeGeometryKeepsFoundationTypeIdentity() {
        #expect(ObjectIdentifier(CGFloat.self) == ObjectIdentifier(Foundation.CGFloat.self))
        #expect(ObjectIdentifier(CGPoint.self) == ObjectIdentifier(Foundation.CGPoint.self))
        #expect(ObjectIdentifier(CGSize.self) == ObjectIdentifier(Foundation.CGSize.self))
        #expect(ObjectIdentifier(CGRect.self) == ObjectIdentifier(Foundation.CGRect.self))

        let point = Foundation.CGPoint(x: 2, y: 3)
        let size = Foundation.CGSize(width: 4, height: 5)
        let rect = Foundation.CGRect(origin: point, size: size)
        let transformed: Foundation.CGPoint = point.applying(CGAffineTransform(translationX: 7, y: 11))
        #expect(transformed == Foundation.CGPoint(x: 9, y: 14))
        #expect(Path(rect).boundingRect == rect)
    }
    #endif

    @Test func affineTransformAppliesToPointsAndSizes() {
        let transform = CGAffineTransform(a: 2, b: 3, c: 5, d: 7, tx: 11, ty: 13)
        let point = CGPoint(x: 17, y: 19)
        #expect(point.applying(transform) == CGPoint(x: 140, y: 197))
        // Translation affects positions, but must not affect dimensions.
        #expect(CGSize(width: 17, height: 19).applying(transform) == CGSize(width: 129, height: 184))
        #expect(point.applying(transform).applying(transform.inverted()) == point)

        let quarterTurn = CGPoint(x: 2, y: 3).applying(CGAffineTransform(rotationAngle: .pi / 2))
        #expect(abs(quarterTurn.x + 3) < 1e-12)
        #expect(abs(quarterTurn.y - 2) < 1e-12)
        #expect(CGAffineTransform.identity.isIdentity)
    }

    @Test func transformCompositionKeepsCoreGraphicsOrder() {
        let point = CGPoint(x: 4, y: 6)
        let translation = CGAffineTransform(translationX: 5, y: -7)
        let scale = CGAffineTransform(scaleX: 2, y: 3)
        #expect(point.applying(translation.concatenating(scale)) == CGPoint(x: 18, y: -3))
        #expect(point.applying(translation.concatenating(scale)) == point.applying(translation).applying(scale))
        #expect(point.applying(translation.scaledBy(x: 2, y: 3)) == CGPoint(x: 13, y: 11))
        #expect(point.applying(scale.translatedBy(x: 5, y: -7)) == CGPoint(x: 18, y: -3))
    }

    @Test func rectangleTransformBoundsAllCorners() {
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 10, ty: 20)
        let expected = CGRect(x: 4, y: 21, width: 4, height: 3)
        #expect(CGRect(x: 1, y: 2, width: 3, height: 4).applying(transform) == expected)
        #expect(CGRect(x: 4, y: 6, width: -3, height: -4).applying(transform) == expected)
        #expect(CGRect.null.applying(transform).isNull)
        #expect(CGRect.null.applying(CGAffineTransform(scaleX: 0, y: 0)).isNull)
        #expect(CGRect.infinite.applying(.identity).isInfinite)
    }

    @Test func vectorColorAndStrokeTypesAreAvailable() {
        let vector = CGVector(dx: 2, dy: -3)
        #expect(vector.dx == 2 && vector.dy == -3)
        #expect(CGVector.zero == CGVector(dx: 0, dy: 0))

        let color = RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
        #expect(RGBA(cgColor: color.cgColor) == color)
        #expect(color.cgColor.alpha == 0.5)
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .bevel, dash: [3, 4])
        #expect(stroke.lineCap == .round && stroke.lineJoin == .bevel)
        #expect(stroke.dash == [3, 4] && !stroke.isPlain)
        #expect(StrokeStyle().isPlain)

        #if !canImport(CoreGraphics) || os(WASI)
        let gray = CGColor(gray: 0.25, alpha: 0.5)
        #expect(gray.numberOfComponents == 4)
        #expect(RGBA(cgColor: gray) == RGBA(red: 0.25, green: 0.25, blue: 0.25, alpha: 0.5))
        #endif
    }

    #if !_runtime(_ObjC)
    @Test func responderShimsKeepSelectorAndTextProviderBehavior() {
        #expect(Selector("copy:") == Selector("copy:"))
        #expect(Selector("copy:") != Selector("paste:"))
        let provider = NSItemProvider(object: "copied")
        #expect(provider.hasItemConformingToTypeIdentifier("public.plain-text"))
        #expect(!provider.hasItemConformingToTypeIdentifier("public.image"))
        var loaded: String?
        provider.loadItem(forTypeIdentifier: "public.utf8-plain-text") { value, error in
            loaded = value as? String
            #expect(error == nil)
        }
        #expect(loaded == "copied")

        #if os(Linux)
        let bridged = NSItemProvider(object: "bridged" as NSString)
        #expect(bridged._text == "bridged")
        #endif
    }
    #endif

    @Test @MainActor func inlineIntentWorksWithNativeAttributedStrings() {
        #if !os(WASI)
        #expect(ObjectIdentifier(AttributedString.self) == ObjectIdentifier(Foundation.AttributedString.self))
        var content = Foundation.AttributedString("styled")
        #else
        var content = AttributedString("styled")
        #endif
        let intent: InlinePresentationIntent = [.stronglyEmphasized, .emphasized, .code, .strikethrough]
        content.inlinePresentationIntent = intent
        #expect(content.inlinePresentationIntent == intent)
        #expect(content.runs.first?[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] == intent)
        let parts = Text(content).parts()
        #expect(parts.count == 1)
        #expect(parts.first?.string == "styled")
        #expect(parts.first?.modifiers.bold == true)
        #expect(parts.first?.modifiers.italic == true)
        #expect(parts.first?.modifiers.monospaced == true)
        #expect(parts.first?.modifiers.strikethrough != nil)
    }

    @Test @MainActor func userActivitiesRetainPayloadWhenContinued() {
        let activity = NSUserActivity(activityType: "com.example.compatibility")
        activity.title = "Open item"
        activity.userInfo = ["item": 42]
        activity.webpageURL = URL(string: "https://example.com/items/42")
        activity.isEligibleForHandoff = false
        var continued: NSUserActivity?
        let runtime = Runtime()
        runtime.mount(Text("Activity").onContinueUserActivity(activity.activityType) { continued = $0 })
        runtime.layout(in: CGSize(width: 200, height: 100))

        #expect(runtime.continueUserActivity(activity))
        #expect(continued === activity)
        #expect(continued?.title == "Open item")
        #expect(continued?.userInfo?["item"] as? Int == 42)
        #expect(continued?.webpageURL?.absoluteString == "https://example.com/items/42")
        #expect(continued?.isEligibleForHandoff == false)
        #expect(!runtime.continueUserActivity(NSUserActivity(activityType: "com.example.other")))
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    @MainActor func lazyRowsNeedPositiveOverlapWithPrefetchWindow(axis: Axis) {
        let runtime = Runtime()
        let rows = ForEach(0..<40, id: \.self) { index in
            Color.blue.frame(width: 20, height: 20)._probe("boundary-row-\(index)")
        }
        if axis == .vertical {
            runtime.mount(ScrollView { LazyVStack(spacing: 0) { rows } })
        } else {
            runtime.mount(ScrollView(.horizontal) { LazyHStack(spacing: 0) { rows } })
        }
        let size = axis == .vertical ? CGSize(width: 100, height: 200) : CGSize(width: 200, height: 100)
        runtime.layout(in: size)
        // The prefetch window ends at 400: row 19 overlaps it, row 20 only touches its edge.
        #expect(runtime.probeFrames["boundary-row-19"] != nil)
        #expect(runtime.probeFrames["boundary-row-20"] == nil)
        let delta = axis == .vertical ? CGSize(width: 0, height: 1) : CGSize(width: 1, height: 0)
        runtime.scrollWheel(by: delta, at: CGPoint(x: size.width / 2, y: size.height / 2))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["boundary-row-20"] != nil)
    }

    enum EmptySeed: CaseIterable { case alongAxis, acrossAxis, bothDimensions, emptyView }

    @Test(arguments: [Axis.horizontal, .vertical], EmptySeed.allCases)
    @MainActor func zeroFirstChildStillMaterializesLaterRows(axis: Axis, seed: EmptySeed) {
        let runtime = Runtime()
        let rows = ForEach(0..<3, id: \.self) { index in
            if index == 0, seed == .emptyView {
                EmptyView()
            } else {
                Color.blue.frame(
                    width: index == 0 && (seed == .bothDimensions || (axis == .horizontal ? seed == .alongAxis : seed == .acrossAxis)) ? 0 : 20,
                    height: index == 0 && (seed == .bothDimensions || (axis == .vertical ? seed == .alongAxis : seed == .acrossAxis)) ? 0 : 20
                )._probe("zero-first-row-\(index)")
            }
        }
        if axis == .vertical {
            runtime.mount(ScrollView { LazyVStack(spacing: 0) { rows } })
        } else {
            runtime.mount(ScrollView(.horizontal) { LazyHStack(spacing: 0) { rows } })
        }
        runtime.layout(in: CGSize(width: 100, height: 100))
        if seed != .emptyView { #expect(runtime.probeFrames["zero-first-row-0"] != nil) }
        #expect(runtime.probeFrames["zero-first-row-1"]?.size == CGSize(width: 20, height: 20))
        #expect(runtime.probeFrames["zero-first-row-2"]?.size == CGSize(width: 20, height: 20))
        let second = runtime.probeFrames["zero-first-row-1"]
        let third = runtime.probeFrames["zero-first-row-2"]
        let firstExtent: CGFloat = seed == .acrossAxis ? 20 : 0
        if axis == .vertical {
            #expect(second?.minY == firstExtent && third?.minY == firstExtent + 20)
        } else {
            #expect(second?.minX == firstExtent && third?.minX == firstExtent + 20)
        }
    }

    #if !os(WASI)
    @Test @MainActor func numberFormatterEditsCommitValidValuesOnly() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        var value = 2.5
        let field = TextField("Amount", value: Binding(get: { value }, set: { value = $0 }), formatter: formatter)
        #expect(field.commitsOnSubmit)
        #expect(field.text.wrappedValue == "2.5")
        field.text.wrappedValue = "12.75"
        #expect(value == 12.75)
        field.text.wrappedValue = "not a number"
        #expect(value == 12.75)
        #expect(field.text.wrappedValue == "12.75")
    }

    @Test @MainActor func dateFormatterEditsCommitValidValuesOnly() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var value = Date(timeIntervalSince1970: 0)
        let field = TextField("Date", value: Binding(get: { value }, set: { value = $0 }), formatter: formatter)
        #expect(field.commitsOnSubmit)
        #expect(field.text.wrappedValue == "1970-01-01")
        field.text.wrappedValue = "1970-01-02"
        #expect(value == Date(timeIntervalSince1970: 86_400))
        field.text.wrappedValue = "not a date"
        #expect(value == Date(timeIntervalSince1970: 86_400))
        #expect(field.text.wrappedValue == "1970-01-02")
    }
    #endif
}
