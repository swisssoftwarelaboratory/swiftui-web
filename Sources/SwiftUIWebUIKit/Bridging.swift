// SwiftUI values from UIKit ones, as the iOS SDK offers them: `Color(uiColor:)`, `Image(uiImage:)`,
// `Font(_ uiFont:)`.
import SwiftUIWebCore
import UIKitWebCore

extension Color {
    /// Creates a color from a UIKit color, resolved for the light and dark appearances.
    public init(uiColor: UIColor) {
        self.init(storage: .dynamic(light: uiColor.light, dark: uiColor.dark))
    }

    /// The older spelling, without the argument label.
    public init(_ uiColor: UIColor) { self.init(uiColor: uiColor) }
}

extension Image {
    /// Creates a SwiftUI image from a UIKit image: the catalog image or symbol it names, or the
    /// drawing an image context recorded (ios/representable/renderedimage: drawn at its size,
    /// scaled when resizable, its silhouette in the foreground colour as a template; a
    /// `withTintColor` tint applies only when the image is rendered as a template).
    public init(uiImage: UIImage) {
        let image: Image
        if let drawing = uiImage.drawing {
            let tint = uiImage.tint.map { Color(uiColor: $0) }
            image = Image(source: .drawing(_ImageDrawing(commands: drawing.commands, size: drawing.size, scale: drawing.scale, tint: tint)), label: nil)
        } else if !uiImage.isSystemSymbol, uiImage.name.hasPrefix("data:") {
            // An image made from bytes (`UIImage(data:)`, a photo): its data URL, loaded as
            // `AsyncImage` loads one, at its pixel size (not a catalog name, which found nothing).
            let pixels = CGSize(width: uiImage.size.width * uiImage.scale, height: uiImage.size.height * uiImage.scale)
            image = Image(source: .url(uiImage.name, pixelSize: pixels, scale: uiImage.scale), label: nil)
        } else {
            image = uiImage.isSystemSymbol ? Image(systemName: uiImage.name) : Image(uiImage.name)
        }
        self = uiImage.renderingMode == .alwaysTemplate ? image.renderingMode(.template) : image
    }
}

extension Font {
    /// Creates a SwiftUI font from a UIKit font: the same text style, or the same size and weight.
    public init(_ uiFont: UIFont) {
        // UIFont's weight is the CSS weight UIKitWeb resolved it to.
        let weight = Font.Weight(uiFont.weight.css)
        if let style = uiFont.textStyle, let textStyle = Self.textStyle(for: style) {
            self = Font.system(textStyle, weight: uiFont.weight == .regular ? nil : weight)
        } else {
            self = Font.system(size: uiFont.pointSize, weight: weight)
        }
    }

    private static func textStyle(for style: UIFont.TextStyle) -> Font.TextStyle? {
        switch style {
        case .largeTitle: return .largeTitle
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption1: return .caption
        case .caption2: return .caption2
        default: return nil
        }
    }
}

extension ImageRenderer {
    /// The content drawn as a UIImage (a recording of the drawing, at the renderer's scale);
    /// nil when the content has no size.
    public var uiImage: UIImage? {
        let drawn = _draw()
        guard drawn.size.width > 0, drawn.size.height > 0 else { return nil }
        return UIImage(drawing: UIImageDrawing(commands: drawn.commands, size: drawn.size, scale: scale))
    }
}

extension UIColor {
    /// Creates a UIKit color from a SwiftUI color, resolved for the light and dark appearances.
    public convenience init(_ color: Color) {
        var light = EnvironmentValues(), dark = EnvironmentValues()
        light.colorScheme = .light
        dark.colorScheme = .dark
        self.init(light: color.resolve(in: light), dark: color.resolve(in: dark))
    }
}
