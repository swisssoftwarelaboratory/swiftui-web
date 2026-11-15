// Wheel input once per display frame (new-website#279): a real trackpad's events, in whole
// points and uneven pairs, moved the content by an uneven step every frame.
import Testing
import Foundation
import WebGraphics

@Suite struct WheelResamplerTests {
    /// The recorded swipes' frames at 60 Hz: each frame's step, by applying what arrived
    /// (`resampler` nil) or through a resampler. Frames run from the first event to a tenth of a
    /// second after the last.
    static func steps(_ resampler: WheelResampler?, events: [[Double]] = recordedTrackpadSwipes) -> [Double] {
        var resampler = resampler
        var next = 0
        var steps: [Double] = []
        var frame = events[0][0]
        let end = events[events.count - 1][0] + 0.1
        while frame <= end {
            var moved = CGSize.zero
            while next < events.count, events[next][0] <= frame {
                let delta = CGSize(width: events[next][1], height: events[next][2])
                if resampler != nil { resampler!.add(delta, at: .zero, time: events[next][0]) } else { moved = CGSize(width: moved.width + delta.width, height: moved.height + delta.height) }
                next += 1
            }
            if resampler != nil, let input = resampler!.take(at: frame) { moved = input.delta }
            steps.append(Double((moved.width * moved.width + moved.height * moved.height).squareRoot()))
            frame += 1.0 / 60
        }
        return steps
    }

    /// How much a moving frame's step differs from the mean step of the five frames around it,
    /// relative to that mean (root mean square), and the share of frames standing still while the
    /// frames around them move.
    static func unsteadiness(_ steps: [Double]) -> (unsteady: Double, still: Double) {
        var errors = 0.0, sizes = 0.0, count = 0, still = 0
        for i in 2..<(steps.count - 2) {
            let mean = steps[(i - 2)...(i + 2)].reduce(0, +) / 5
            guard mean >= 2 else { continue }
            errors += (steps[i] - mean) * (steps[i] - mean)
            sizes += mean
            count += 1
            if steps[i] < 0.01 { still += 1 }
        }
        return ((errors / Double(count)).squareRoot() / (sizes / Double(count)), Double(still) / Double(count))
    }

    @Test func nothingIsLost() {
        var resampler = WheelResampler()
        var total = CGSize.zero
        var frame = 0.0
        for event in recordedTrackpadSwipes {
            while frame + 1.0 / 60 < event[0] {
                frame += 1.0 / 60
                if let input = resampler.take(at: frame) { total.width += input.delta.width; total.height += input.delta.height }
            }
            resampler.add(CGSize(width: event[1], height: event[2]), at: .zero, time: event[0])
        }
        for _ in 0..<10 {
            frame += 1.0 / 60
            if let input = resampler.take(at: frame) { total.width += input.delta.width; total.height += input.delta.height }
        }
        #expect(!resampler.isPending)
        let x = recordedTrackpadSwipes.reduce(0) { $0 + $1[1] }, y = recordedTrackpadSwipes.reduce(0) { $0 + $1[2] }
        #expect(abs(Double(total.width) - x) < 1e-6 && abs(Double(total.height) - y) < 1e-6, "\(total) against \(x), \(y)")
    }

    /// The recorded minute: per-frame steps are steadier and no frame stands still mid-swipe.
    /// (On longer recorded Safari sessions: unsteady 52 % to 24 %, 56 % to 21 %, 42 % to 25 %.)
    @Test func framesStepEvenly() {
        let before = Self.unsteadiness(Self.steps(nil))
        let after = Self.unsteadiness(Self.steps(WheelResampler()))
        #expect(after.unsteady < before.unsteady * 0.75, "unsteady \(before.unsteady) -> \(after.unsteady)")
        #expect(after.still <= before.still, "still \(before.still) -> \(after.still)")
    }

    /// A mouse wheel's single notch arrives whole within a few frames, not stretched out.
    @Test func aNotchArrivesWithinTwoFrames() {
        var resampler = WheelResampler()
        resampler.add(CGSize(width: 0, height: 100), at: .zero, time: 1)
        var moved: [CGFloat] = []
        var frame = 1.0
        while resampler.isPending { frame += 1.0 / 60; moved.append(resampler.take(at: frame)?.delta.height ?? 0) }
        #expect(moved.reduce(0, +) == 100)
        #expect(moved.count <= 3, "\(moved)")
    }
}
