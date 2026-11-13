// Gauge: the linear capacity layout (label, bar, value and bounds labels at the stack spacings),
// value normalisation and the tint, the accessory linear row (8 pt, labels centred on the
// track, the knob), the accessory capacity capsule, and the rings (arc, trim, marker,
// capacity). Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct GaugeTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let value17 = ResolvedFont(family: "system", size: 17, weight: .semibold, italic: false, textStyle: nil)
    static let ring24 = ResolvedFont(family: "system", size: 24, weight: .medium, italic: false, textStyle: nil)
    static let small11 = ResolvedFont(family: "system", size: 11, weight: .regular, italic: false, textStyle: nil)
    static let value12 = ResolvedFont(family: "system", size: 12, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Battery", 44.0), ("60%", 27.0), ("0", 8.5), ("100", 22.5), ("Level", 31.0), ("40", 15.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        for (word, width) in [("40", 22.0), ("0", 11.0), ("100", 31.0)] {
            entries[RecordedTextEngine.key(font: Self.value17, width: nil, string: word)] = .init(width: width, height: 20, firstBaseline: 16, lastBaseline: 16)
        }
        entries[RecordedTextEngine.key(font: Self.ring24, width: nil, string: "40")] = .init(width: 30.5, height: 28, firstBaseline: 23, lastBaseline: 23)
        entries[RecordedTextEngine.key(font: Self.value12, width: nil, string: "40")] = .init(width: 13.5, height: 15, firstBaseline: 12, lastBaseline: 12)
        for (word, width) in [("A", 7.5), ("0", 7.0), ("100", 19.5)] {
            entries[RecordedTextEngine.key(font: Self.small11, width: nil, string: word)] = .init(width: width, height: 14, firstBaseline: 11, lastBaseline: 11)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    @Test func linearCapacity() {
        let r = runtime(VStack(spacing: 14) {
            Gauge(value: 0.4) { Text("Battery")._probe("label") }._probe("bare")
            Gauge(value: 0.6) { Text("Battery") } currentValueLabel: { Text("60%")._probe("value") }._probe("valued")
            Gauge(value: 0.3) { Text("Battery") } currentValueLabel: { Text("60%") } minimumValueLabel: { Text("0")._probe("min") } maximumValueLabel: { Text("100")._probe("max") }
                ._probe("bounded")
            Gauge(value: 25, in: 0...50) { Text("Battery") }.tint(.red)._probe("total")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading), size: CGSize(width: 320, height: 400))
        // (400 tall: the four gauges take about 290, and a flexible frame is never shorter than
        // its child, so in 200 the column would overflow and centre, as in SwiftUI.)
        // The label sits over the 16 pt bar and the value label under it at the stack spacing
        // (the goldens prove the font-derived 8.15 and 4.74; this engine has no font table, so
        // 8); bounds labels flank the bar 8 apart; the bar fills the width.
        #expect(r.probeFrames["bare"] == CGRect(x: 20, y: 20, width: 280, height: 40))
        #expect(r.probeFrames["label"]?.midX == 160 && r.probeFrames["label"]?.minY == 20)
        #expect(r.probeFrames["valued"]?.height == 64)
        #expect(r.probeFrames["value"]?.midX == 160)
        #expect(r.probeFrames["min"]?.minX == 20 && r.probeFrames["max"]?.maxX == 300)
        let painted = commands(r)
        // Track black 18/255 with 1.5 corners, the fill 40 % of 280 in green; the red tint; 25 of 50 is half.
        #expect(painted.contains { $0.hasPrefix("fillRRect(20, 44, 280, 16) r=1.5") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(20, 44, 112, 16) r=1.5 #34C759") })
        #expect(painted.contains { $0.contains("140, 16) r=1.5 #FF383C") })
        // Bounds: the bar spans between the labels (8 + 8.5 + 8 … 300 − 22.5 − 8).
        #expect(painted.contains { $0.hasPrefix("fillRRect(36.5, ") && $0.contains(", 233, 16) r=1.5") })
    }

    @Test func accessoryLinear() {
        let r = runtime(VStack(spacing: 20) {
            Gauge(value: 0.4) { Text("Level") } currentValueLabel: { Text("40")._probe("value") }.gaugeStyle(.accessoryLinear)._probe("linear")
            Gauge(value: 0.3) { Text("Level") } currentValueLabel: { Text("40") } minimumValueLabel: { Text("0")._probe("min") } maximumValueLabel: { Text("100")._probe("max") }
                .gaugeStyle(.accessoryLinear)._probe("bounded")
            Gauge(value: 0.6) { Text("Level") }.gaugeStyle(.accessoryLinear)._probe("bare")
            Gauge(value: 0.4) { Text("Level")._probe("capLabel") } currentValueLabel: { Text("40")._probe("capValue") }.gaugeStyle(.accessoryLinearCapacity)._probe("capacity")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        // The row is 8 tall whatever its labels, which are centred on the track and overflow it.
        #expect(r.probeFrames["linear"] == CGRect(x: 20, y: 20, width: 280, height: 8))
        #expect(r.probeFrames["value"] == CGRect(x: 20, y: 14, width: 22, height: 20))
        #expect(r.probeFrames["min"]?.minX == 20 && r.probeFrames["max"]?.maxX == 300)
        let painted = commands(r)
        // The track after the label + 8; the knob at 4 + 0.4 × (track − 8) in an 8 pt white halo.
        #expect(painted.contains { $0.hasPrefix("fillRRect(50, 20, 250, 8) r=4") })
        let knobX = 50 + 4 + 0.4 * (250 - 8)
        #expect(painted.contains { $0.hasPrefix("fillRRect(\(knobX - 8), 16, 16, 16) r=8 #FFFFFF") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(\(knobX - 4), 20, 8, 8) r=4") })
        // Bare: the track spans the width; bounded: between the 17 pt labels.
        #expect(painted.contains { $0.hasPrefix("fillRRect(20, 76, 280, 8) r=4") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(39, 48, 222, 8) r=4") })
        // Capacity: label, capsule and the 12 pt secondary value 6 and 7 apart, leading-aligned; 52 tall.
        #expect(r.probeFrames["capacity"] == CGRect(x: 20, y: 104, width: 280, height: 52))
        #expect(r.probeFrames["capLabel"]?.origin == CGPoint(x: 20, y: 104))
        #expect(r.probeFrames["capValue"]?.origin == CGPoint(x: 20, y: 141))
        #expect(painted.contains { $0.hasPrefix("fillRRect(20, 126, 280, 8) r=4") })
        #expect(painted.contains { $0.hasPrefix("fillRRect(20, 126, 112, 8) r=4") })
    }

    @Test func rings() {
        let r = runtime(HStack(spacing: 14) {
            Gauge(value: 0.4) { Text("A")._probe("label") } currentValueLabel: { Text("40")._probe("value") }.gaugeStyle(.accessoryCircular)._probe("open")
            Gauge(value: 0.4) { Text("A") } currentValueLabel: { Text("40") }.gaugeStyle(.accessoryCircularCapacity)._probe("capacity")
            Gauge(value: 0.3) { Text("A") } currentValueLabel: { Text("40") } minimumValueLabel: { Text("0")._probe("min") } maximumValueLabel: { Text("100")._probe("max") }
                .gaugeStyle(.accessoryCircular)._probe("bounded")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        #expect(r.probeFrames["open"] == CGRect(x: 20, y: 20, width: 58, height: 58))
        // The value is centred; the label's line sits 18.385 under the centre; the bounds labels
        // start and end at the arc's ends.
        #expect(r.probeFrames["value"]?.midX == 49 && r.probeFrames["value"]?.midY == 49)
        // The label is offset 18.385 under the centre (a paint transform: its layout frame stays put).
        #expect(r.probeFrames["label"]?.midY == 49)
        #expect(r.probeFrames["min"]?.minX == 164 + 29 - 18.385)
        #expect(r.probeFrames["max"]?.maxX == 164 + 29 + 18.385)
        let rings = r.root.descendants(where: { $0 is GaugeRingNode }).compactMap { $0 as? GaugeRingNode }
        #expect(rings.count == 3)
        #expect(rings[0].arc.start == 135 && rings[0].arc.sweep == 270)
        #expect(rings[2].arc.start == 149 && rings[2].arc.sweep == 242)
        let painted = commands(r)
        // Open: one stroked arc, the marker halo and dot; capacity: track + arc, no marker.
        #expect(painted.filter { $0.contains("#FFFFFF") }.count == 2)
        #expect(painted.filter { $0.hasPrefix("strokePath") }.count == 4)
    }

    @Test func normalisationAndStyles() {
        // Values clamp to the bounds; an empty range is 0.
        #expect(Gauge<Text, EmptyView, EmptyView, EmptyView>.normalized(75.0, in: 50...100) == 0.5)
        #expect(Gauge<Text, EmptyView, EmptyView, EmptyView>.normalized(2.0, in: 0...1) == 1)
        #expect(Gauge<Text, EmptyView, EmptyView, EmptyView>.normalized(-1.0, in: 0...1) == 0)
        #expect(Gauge<Text, EmptyView, EmptyView, EmptyView>.normalized(3.0, in: 3...3) == 0)
        // A custom style receives the configuration.
        struct Bare: GaugeStyle {
            func makeBody(configuration: Configuration) -> some View {
                Text("\(Int(configuration.value * 100))")._probe("custom")
            }
        }
        let r = runtime(Gauge(value: 0.4) { Text("Level") }.gaugeStyle(Bare()))
        #expect(r.probeFrames["custom"]?.width == 15)
    }
}
#endif
