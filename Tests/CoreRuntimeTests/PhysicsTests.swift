// One physics for every motion (`Physics.swift`, Docs/elements/Physics.md): the spring, decay
// and rubber band against curves filmed in the iOS 27.2 simulator (iPhone 16, 60 frames a
// second, one sample per point), stepping by any frame time, velocity carried across an
// interruption, the finger's speed, and animations that start when their first frame shows.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PhysicsTests {
    // MARK: Measured curves: (milliseconds, points)

    /// A `Toggle`'s knob moving 19.7 pt under `.snappy`.
    static let toggleKnob: [(Double, Double)] = [(0, 19.67), (8.3, 19.66), (40, 18.49), (56.7, 17.07), (71.7, 15.58), (88.3, 13.84), (105, 12.08), (121.7, 10.51), (138.3, 8.92), (155, 7.55), (171.7, 6.2), (188.3, 5.07), (205, 4.07), (221.7, 3.23), (238.3, 2.6), (255, 1.93), (271.7, 1.5), (288.3, 1.06), (305, 0.81), (321.7, 0.56), (338.3, 0.36), (355, 0.23), (371.7, 0.14), (388.3, 0.08), (405, 0.04), (421.7, 0.01), (438.3, 0.01), (455, 0.01)]
    /// A system `.sheet` sliding up: its top edge above its resting place.
    static let sheetOpen: [(Double, Double)] = [(31.7, 608.83), (51.7, 517.79), (68.3, 435.24), (86.7, 360.51), (105, 294.75), (120, 238.6), (135, 191.66), (153.3, 152.73), (171.7, 119.92), (190, 95.08), (203.3, 76.98), (218.3, 62.74), (231.7, 51.15), (245, 41.66), (258.3, 33.85), (271.7, 27.71), (286.7, 22.49), (300, 18.06), (313.3, 14.87), (325, 11.95), (341.7, 9.76), (360, 7.49), (380, 5.58), (400, 4.08), (418.3, 2.98), (435, 2.17), (451.7, 1.68), (470, 1.22), (486.7, 0.95), (501.7, 0.89), (516.7, 0)]
    /// A list pulled 200 pt down past its top and held (93.08 pt of stretch), then released.
    static let bandReturn: [(Double, Double)] = [(798.3, 83.74), (808.3, 74.06), (823.3, 65.39), (838.3, 57.72), (855, 50.38), (871.7, 44.37), (886.7, 38.7), (903.3, 33.7), (925, 29.36), (938.3, 25.35), (956.7, 22.02), (961.7, 22.02), (971.7, 22.02), (978.3, 19.02), (988.3, 16.68), (1005, 14.35), (1021.7, 12.34), (1038.3, 10.68), (1055, 9.34), (1071.7, 8.01), (1088.3, 6.67), (1105, 6.01), (1120, 5), (1126.7, 5), (1135, 5), (1143.3, 4.34), (1156.7, 3.67), (1171.7, 3.34), (1188.3, 2.67), (1205, 2.34), (1221.7, 2), (1238.3, 1.67), (1255, 1.33), (1288.3, 1), (1325, 0.67), (1380, 0)]
    /// A list coasting after a 200 pt flick, from 0.6 s after the touch began.
    static let coast: [(Double, Double)] = [(605, -313.6), (620, -317.6), (636.7, -321.61), (651.7, -325.28), (670, -328.94), (686.7, -332.28), (705, -335.95), (721.7, -338.95), (738.3, -342.29), (746.7, -342.29), (751.7, -342.29), (756.7, -345.29), (770, -348.29), (785, -351.3), (803.3, -353.97), (821.7, -356.64), (836.7, -359.3), (855, -361.64), (871.7, -364.31), (888.3, -366.64), (903.3, -368.65), (906.7, -368.65), (910, -368.65), (920, -370.98), (935, -372.98), (955, -375.32), (971.7, -377.32), (986.7, -378.99), (1003.3, -380.99), (1020, -382.66), (1170, -396.67), (1253.3, -402.67), (1271.7, -403.67), (1286.7, -404.68), (1303.3, -405.68), (1320, -406.68), (1335, -407.68), (1353.3, -408.68), (1370, -409.68), (1385, -410.35), (1401.7, -411.35), (1420, -412.02), (1435, -412.68), (1453.3, -413.68), (1471.7, -414.35), (1485, -415.02), (1501.7, -415.68), (1518.3, -416.35), (1535, -417.02), (1553.3, -417.69), (1570, -418.35), (1585, -418.69), (1603.3, -419.35), (1620, -420.02), (1636.7, -420.36), (1655, -421.02), (1670, -421.36), (1688.3, -422.02)]

    /// The smallest root-mean-square distance between the curve and `model(t)` (t in seconds
    /// since the motion began) over start times in `starts` (seconds, 1 ms apart): the video
    /// doesn't show the instant a motion began, only its shape.
    private func bestFit(_ curve: [(Double, Double)], starts: ClosedRange<Double>, _ model: (Double) -> Double) -> Double {
        var best = Double.infinity
        var t0 = starts.lowerBound
        while t0 <= starts.upperBound {
            let sum = curve.reduce(0.0) { acc, sample in
                let d = model(max(0, sample.0 / 1000 - t0)) - sample.1
                return acc + d * d
            }
            best = min(best, (sum / Double(curve.count)).squareRoot())
            t0 += 0.001
        }
        return best
    }

    // MARK: Springs

    @Test func swiftUIParametersMapAsIOSMapsThem() {
        let response = SpringModel(response: 0.55, dampingFraction: 1)
        #expect(abs(response.omega - 2 * .pi / 0.55) < 1e-9 && response.zeta == 1)
        // stiffness = (2π/response)², damping = 4πζ/response (unit mass).
        #expect(abs(response.stiffness() - pow(2 * .pi / 0.55, 2)) < 1e-6)
        #expect(abs(response.damping() - 4 * .pi / 0.55) < 1e-6)
        #expect(abs(SpringModel(duration: 0.5, bounce: 0.15).zeta - 0.85) < 1e-12)
        #expect(abs(SpringModel(duration: 0.5, bounce: -0.5).zeta - 2) < 1e-12)
        #expect(abs(SpringModel(duration: 0.5, bounce: 0.3).bounce - 0.3) < 1e-12)
        // UIKit's push, pop and keyboard: mass 3, stiffness 1000, damping 500, not overdamped.
        #expect(abs(SpringModel.navigation.omega - 18.257) < 0.001 && SpringModel.navigation.zeta == 1)
        // Animation and Spring run on the same model.
        let snappy = Animation.snappy
        #expect(snappy.springModel == SpringModel(duration: 0.5, bounce: 0.15))
        #expect(Spring.snappy.model == snappy.springModel)
        let byMass = Spring(mass: 1, stiffness: 100, damping: 10)
        #expect(abs(byMass.stiffness - 100) < 1e-9 && abs(byMass.damping - 10) < 1e-9)
        #expect(abs(Spring(response: 0.4, dampingRatio: 0.7).dampingRatio - 0.7) < 1e-12)
    }

    @Test func springStateIsTheExactSolution() {
        // Each damping regime: the velocity is the position's slope, and it starts as given.
        for zeta in [0.3, 1.0, 2.5] {
            let spring = SpringModel(omega: 12, zeta: zeta)
            let start = spring.state(displacement: 40, velocity: -900, at: 0)
            #expect(start.displacement == 40 && start.velocity == -900)
            for t in [0.01, 0.1, 0.37] {
                let h = 1e-6
                let a = spring.state(displacement: 40, velocity: -900, at: t - h), b = spring.state(displacement: 40, velocity: -900, at: t + h)
                let slope = (b.displacement - a.displacement) / (2 * h)
                #expect(abs(slope - spring.state(displacement: 40, velocity: -900, at: t).velocity) < 1e-3)
            }
            let settle = spring.settlingTime(displacement: 40, velocity: -900, epsilon: 0.01)
            #expect(abs(spring.state(displacement: 40, velocity: -900, at: settle).displacement) <= 0.011)
        }
        // Spring(...).value: a change of `target` from zero.
        #expect(Spring.smooth.value(target: 10.0, time: 0) == 0)
        #expect(abs(Spring.smooth.value(target: 10.0, time: 5) - 10) < 1e-6)
        #expect(abs(Spring.smooth.velocity(target: 0.0, initialVelocity: 3.0, time: 0) - 3) < 1e-9)
    }

    @Test func snappyMatchesTheSimulatorsToggle() {
        // SwiftUI's own parameters, mapped as above, draw iOS's curve within a tenth of a point.
        let spring = SpringModel(duration: 0.5, bounce: 0.15)
        let rms = bestFit(Self.toggleKnob, starts: -0.05...0.05) { spring.state(displacement: 19.7, velocity: 0, at: $0).displacement }
        #expect(rms < 0.2, "rms \(rms)")
    }

    @Test func navigationSpringMatchesTheSimulatorsSheet() {
        // A system sheet rises on UIKit's navigation spring from below the screen.
        let spring = SpringModel.navigation
        var best = Double.infinity
        for start in stride(from: 650.0, through: 800, by: 5) {
            best = min(best, bestFit(Self.sheetOpen, starts: -0.03...0.03) { spring.state(displacement: start, velocity: 0, at: $0).displacement })
        }
        #expect(best < 2.5, "rms \(best)")
    }

    @Test func rubberBandMatchesTheSimulatorsPull() {
        // 200 pt of finger, 10 of them the drag's slop, against the 852 pt tall list: 93.08 pt.
        #expect(abs(RubberBand.offset(forOvershoot: 190, dimension: 852) - 93.08) < 0.1)
        #expect(RubberBand.offset(forOvershoot: -190, dimension: 852) < -93)
        // A finger landing on stretched content picks it up where it is.
        #expect(abs(RubberBand.overshoot(forOffset: 93.08, dimension: 852) - 190) < 0.5)
        // Released, it springs back from rest.
        let rms = bestFit(Self.bandReturn, starts: 0.70...0.80) { SpringModel.rubberBandReturn.state(displacement: 93.08, velocity: 0, at: $0).displacement }
        #expect(rms < 2, "rms \(rms)")
    }

    // MARK: Decay

    @Test func decayMatchesTheSimulatorsCoast() {
        let decay = DecayModel.normal
        #expect(abs(decay.restOffset(velocity: 1000) - 499.5) < 0.1)
        #expect(abs(decay.projectedOffset(velocity: 1000) - 499) < 1e-9)
        // x(t) = rest + a · e^(kt): the best rest and a by least squares, then the distance.
        let k = decay.exponent
        let e = Self.coast.map { _exp(k * $0.0 / 1000) }, x = Self.coast.map(\.1)
        let n = Double(e.count), se = e.reduce(0, +), see = e.reduce(0) { $0 + $1 * $1 }
        let sx = x.reduce(0, +), sex = zip(e, x).reduce(0) { $0 + $1.0 * $1.1 }
        let a = (n * sex - se * sx) / (n * see - se * se), rest = (sx - a * se) / n
        let rms = (zip(e, x).reduce(0) { $0 + pow(rest + a * $1.0 - $1.1, 2) } / n).squareRoot()
        #expect(rms < 0.5, "rms \(rms)")
        // The same fit with a rate either side is clearly worse: the rate is iOS's.
        for other in [DecayModel(rate: 0.997), DecayModel(rate: 0.999)] {
            let e2 = Self.coast.map { _exp(other.exponent * $0.0 / 1000) }
            let se2 = e2.reduce(0, +), see2 = e2.reduce(0) { $0 + $1 * $1 }, sex2 = zip(e2, x).reduce(0) { $0 + $1.0 * $1.1 }
            let a2 = (n * sex2 - se2 * sx) / (n * see2 - se2 * se2), rest2 = (sx - a2 * se2) / n
            let rms2 = (zip(e2, x).reduce(0) { $0 + pow(rest2 + a2 * $1.0 - $1.1, 2) } / n).squareRoot()
            #expect(rms2 > rms * 4)
        }
        // Travel and slowing times agree with the state.
        let hit = decay.timeToTravel(300, velocity: 1000)!
        #expect(abs(decay.state(velocity: 1000, at: hit).offset - 300) < 1e-6)
        #expect(decay.timeToTravel(600, velocity: 1000) == nil)
        #expect(abs(decay.state(velocity: 1000, at: decay.timeToSlow(from: 1000, to: 5)).velocity - 5) < 1e-6)
    }

    // MARK: Stepping by real frame time

    private func run(_ motion: Motion, frames: [Double]) -> Motion {
        var m = motion
        for dt in frames { m.step(dt) }
        return m
    }

    @Test func motionIsTheSameAtAnyFrameRate() {
        // Safari caps a page at 60 frames a second; a phone may give 120, a busy page 30 or a
        // ragged mix. The motion lands in the same place at the same time.
        let total = 0.5
        let rates: [[Double]] = [
            Array(repeating: 1.0 / 60, count: 30), Array(repeating: 1.0 / 120, count: 60), Array(repeating: 1.0 / 30, count: 15),
            [0.004, 0.05, 0.016, 0.1, 0.03, 0.016, 0.084, 0.2],
        ]
        var spring = Motion(position: 0, velocity: 2000)
        spring.animate(to: 300, spring: SpringModel(duration: 0.5, bounce: 0.3))
        var coast = Motion(position: 0)
        coast.coast(within: -1000...200, edge: .rubberBandReturn, velocity: 1500)
        for start in [spring, coast] {
            let ends = rates.map { run(start, frames: $0) }
            #expect(rates.allSatisfy { abs($0.reduce(0, +) - total) < 1e-9 })
            for end in ends.dropFirst() {
                #expect(abs(end.position - ends[0].position) < 1e-6 && abs(end.velocity - ends[0].velocity) < 1e-4)
            }
        }
    }

    @Test func coastBouncesOffItsEndOnASpring() {
        // Coasting into a bound hands over to the edge spring at the speed it arrived with:
        // the content overshoots, then settles on the bound.
        var m = Motion(position: 0)
        m.coast(within: -1000...200, edge: .rubberBandReturn, velocity: 2000)
        var furthest = 0.0
        for _ in 0..<180 { m.step(1.0 / 60); furthest = max(furthest, m.position) }
        #expect(furthest > 220)
        #expect(m.position == 200 && !m.isMoving)
        // A coast that ends short of the bound just stops.
        var short = Motion(position: 0)
        short.coast(within: -1000...2000, edge: .rubberBandReturn, velocity: 1000)
        for _ in 0..<600 { short.step(1.0 / 60) }
        #expect(!short.isMoving && abs(short.position - DecayModel.normal.restOffset(velocity: 1000)) < 3)
        // Released while stretched past the end: straight back on the spring.
        var stretched = Motion(position: 260)
        stretched.coast(within: -1000...200, edge: .rubberBandReturn)
        #expect(stretched.driver == .spring(.rubberBandReturn, target: 200))
    }

    // MARK: Interruption and hand-off

    @Test func retargetingKeepsTheVelocity() {
        var m = Motion(position: 0)
        m.animate(to: 100, spring: .navigation)
        m.step(0.05)
        let (position, velocity) = (m.position, m.velocity)
        #expect(velocity > 100)
        m.animate(to: -50, spring: SpringModel(duration: 0.4, bounce: 0))
        #expect(m.position == position && m.velocity == velocity)
        // The finger's speed hands over into the spring that follows it.
        var held = Motion(position: 0)
        held.hold(at: 40, velocity: -800)
        held.animate(to: 0, spring: .navigation)
        held.step(1.0 / 120)
        #expect(held.position < 40 - 800 / 120 * 0.8)
    }

    @Test func aRetargetedTweenCarriesOn() {
        let spring = Animation.spring(duration: 0.5, bounce: 0)
        let first = Tween(from: [0, 10], to: [100, 10], animation: spring, start: 0)
        let at = 0.08
        let v = first.velocity(at: at)
        #expect(v[0] > 100 && v[1] == 0)
        let second = Tween(from: first.value(at: at), to: [-40, 10], animation: spring, start: at, continuing: first)
        // Same place, same speed at the hand-off: no jump, no kink.
        #expect(zip(second.value(at: at), first.value(at: at)).allSatisfy { abs($0 - $1) < 1e-9 })
        let carried = second.velocity(at: at)
        #expect(abs(carried[0] - v[0]) < 1e-6 && carried[1] == 0)
        let h = 1.0 / 240
        #expect(abs((second.value(at: at + h)[0] - second.value(at: at)[0]) / h - v[0]) < abs(v[0]) * 0.2)
        // ...and still arrives.
        #expect(!second.isFinished(at: at + 0.1) && second.isFinished(at: at + 3))
        #expect(second.value(at: at + 3) == [-40, 10])
        // A curve that isn't a spring starts from the presented value as before.
        let eased = Tween(from: [0], to: [1], animation: .easeInOut(duration: 1), start: at, continuing: first)
        #expect(eased.velocity == nil)
    }

    @Test func theFingersSpeedIsReadOverItsRecentPath() {
        // 1000 pt/s with uneven frames reads 1000, not the last step's speed.
        var tracker = VelocityTracker()
        var t = 0.0, y = 0.0
        for dt in [0.016, 0.008, 0.033, 0.004, 0.016, 0.025, 0.012] {
            t += dt; y += 1000 * dt
            tracker.add(CGPoint(x: 0, y: y), at: t)
        }
        #expect(abs(tracker.velocity(at: t).height - 1000) < 1)
        // A finger that rests before lifting leaves no speed.
        #expect(tracker.velocity(at: t + 0.15) == .zero)
    }

    // MARK: Animations start when their first frame shows

    struct Growing: View {
        @Bindable var model: Model
        var body: some View { Color.red.frame(width: model.wide ? 200 : 100, height: 40) }
    }

    @Observable final class Model: @unchecked Sendable { var wide = false }

    @Test func aSlowFrameDoesNotEatTheAnimation() {
        func painted(lateness: Double) -> String {
            let model = Model()
            let r = Runtime()
            r.mount(Growing(model: model))
            r.layout(in: CGSize(width: 320, height: 200))
            withAnimation(.linear(duration: 1)) { model.wide = true }
            r.layout(in: CGSize(width: 320, height: 200))
            // The frame that began it took `lateness` to reach the screen; the next comes a
            // sixtieth of a second after that.
            r.commitAnimations(lateness: lateness)
            r.advanceAnimations(elapsed: lateness + 0.1)
            return r.render(scale: 1).commands.map(\.description).first { $0.hasPrefix("fillRect") } ?? ""
        }
        // A tenth of a second in, however long the first frame took.
        #expect(painted(lateness: 0.25) == painted(lateness: 0))
        #expect(painted(lateness: 0).contains("fillRect(105, 80, 110, 40)"))
    }
}
#endif
