// UILabel attributed text and fitting (uk-label): per-range fonts and colours, the label's
// size from its tallest run, the continuous scale to fit, the scale floor truncating, and
// tightening before truncation. Sizes against the simulator: UIKitGoldenFrameTests
// (uikit/label/fitting).
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct LabelFittingTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        return scene
    }

    /// The display list of a label alone on a screen.
    private func render(_ label: UIView, in scene: UIKitScene) -> DisplayList {
        scene.removeAllWindows()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let root = UIViewController()
        root.view.backgroundColor = .white
        root.view.addSubview(label)
        window.rootViewController = root
        window.overrideUserInterfaceStyle = .light   // a dark fixture test may run in between
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        return scene.render(scale: 2)
    }

    @Test func attributedRunsKeepTheirFontsAndColours() {
        let scene = scene()
        let label = UILabel()
        let text = NSMutableAttributedString(string: "Plain ", attributes: [.font: UIFont.systemFont(ofSize: 17)])
        text.append(NSAttributedString(string: "bold ", attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        text.append(NSAttributedString(string: "red ", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.systemRed]))
        text.append(NSAttributedString(string: "big", attributes: [.font: UIFont.systemFont(ofSize: 24)]))
        label.attributedText = text
        #expect(label.text == "Plain bold red big" && label.font.pointSize == 17)
        let runs = label.runs
        #expect(runs.map(\.text) == ["Plain ", "bold ", "red ", "big"])
        #expect(runs[1].font.weight == .semibold && runs[2].color == .systemRed && runs[3].font.pointSize == 24)
        // The size: the runs' widths and the tallest run's line (uikit/label/fitting).
        label.sizeToFit()
        #expect(label.frame.size == CGSize(width: 142, height: 29))
        // Painting draws each run in its font and colour.
        label.frame.origin = .zero
        let list = render(label, in: scene)
        let texts = list.commands.compactMap { command -> String? in
            if case .drawText(let text, let font, _, let color) = command { return "\(text)|\(Int(font.size))|\(color == UIColor.systemRed.rgba(for: .light) ? "red" : "label")" }
            return nil
        }
        #expect(texts == ["Plain |17|label", "bold |17|label", "red |17|red", "big|24|label"])
        // Plain text again drops the runs.
        label.text = "Plain"
        #expect(label.attributedText == nil && label.runs.count == 1)
    }

    /// A paragraph's fixed line height sets each line's height, with the extra space above the
    /// text as TextKit puts it; `.baselineOffset` lifts the text and `.kern` spaces its letters.
    @Test func paragraphLineHeightsKernAndBaselineOffset() {
        let scene = scene()
        let font = UIFont.systemFont(ofSize: 17)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 30
        paragraph.maximumLineHeight = 30
        let label = UILabel()
        label.attributedText = NSAttributedString(string: "Plain", attributes: [.font: font, .paragraphStyle: paragraph, .kern: 1.5, .baselineOffset: 2])
        label.sizeToFit()
        // One 30 pt line (17 pt text alone is 20.5 tall).
        #expect(label.frame.height == 30)
        label.frame.origin = .zero
        let list = render(label, in: scene)
        let drawn = list.commands.compactMap { command -> (DisplayFont, CGPoint)? in
            if case .drawText(_, let font, let origin, _) = command { return (font, origin) }
            return nil
        }
        #expect(drawn.count == 1)
        // The baseline: the line's bottom less the descender, lifted by the offset.
        #expect(abs(drawn[0].1.y - (30 + font.descender - 2)) < 0.01)
        #expect(drawn[0].0.letterSpacing == 1.5)
        // Plain text keeps the font's own line.
        let plain = UILabel()
        plain.text = "Plain"
        plain.font = font
        plain.sizeToFit()
        #expect(plain.frame.height < 30)
    }

    @Test func scalesToFitAndTruncatesAtTheFloor() {
        let scene = scene()
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 120, height: 24))
        label.text = "Adjusts the font to fit"
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        let list = render(label, in: scene)
        // 159 pt of 17 pt text in 120: drawn at 120/159 of the size (12.83 pt), as the simulator shows.
        #expect(abs(label.fittedScale - 120.0 / 159.0) < 0.001)
        let drawn = list.commands.compactMap { command -> (String, CGFloat)? in
            if case .drawText(let text, let font, _, _) = command { return (text, font.size) }
            return nil
        }
        let probe = label.layout(width: 120, fitting: true)
        #expect(drawn.map { "\($0.0)|\($0.1)" } == ["Adjusts the font to fit|\(17.0 * 120 / 159)"], "lines \(probe?.lines.count ?? -1) size \(probe?.size ?? .zero) scale \(label.fittedScale)")
        // A floor of 0.9 leaves the text too wide: it draws at 15.3 pt (and truncates).
        label.minimumScaleFactor = 0.9
        label.setNeedsDisplay()
        let floored = scene.render(scale: 2).commands.compactMap { command -> CGFloat? in
            if case .drawText(_, let font, _, _) = command { return font.size }
            return nil
        }
        #expect(label.fittedScale == 0.9 && floored.map { "\($0)" } == ["15.3"])
        // Without the option the text keeps its size; sizing to fit never scales.
        label.adjustsFontSizeToFitWidth = false
        label.setNeedsDisplay()
        _ = scene.render(scale: 2)
        #expect(label.fittedScale == 1 && label.sizeThatFits(CGSize(width: 120, height: 24)).width == 159)
        // A text that fits is not scaled; tightening is passed to the engine.
        let fits = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        fits.text = "Adjusts the font to fit"
        fits.adjustsFontSizeToFitWidth = true
        fits.minimumScaleFactor = 0.5
        fits.allowsDefaultTighteningForTruncation = true
        _ = render(fits, in: scene)
        #expect(fits.fittedScale == 1)
    }
}
