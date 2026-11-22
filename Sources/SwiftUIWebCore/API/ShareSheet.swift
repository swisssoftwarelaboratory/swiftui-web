// The drawn iPhone's share sheet (Docs/elements/ShareLink.md, new-website#668): iOS 27's
// frosted card growing out of the pressed share button, with the item's preview and title, four
// made-up people, two made-up apps from the drawn home screen and More, and the round actions;
// View More grows it into the full sheet with the grouped list and Edit Actions. A person or an
// app closes it as if sent, Copy puts the item on the viewer's real clipboard, Save Image puts it
// in the drawn phone's photos (`_PhotoLibrary`), the rest close it.
import WebFoundation

/// The share sheet's two stages: the compact card, and the full sheet View More grows it into.
package enum ShareSheetStage: Sendable, Equatable { case compact, expanded }

/// The share sheet's measures, in points, from the iOS 27 simulator (iPhone 16, 393 pt).
package enum ShareSheetMetrics {
    // The card.
    package static let sideInset: CGFloat = 9
    package static let bottomInset: CGFloat = 9
    package static let cornerRadius: CGFloat = 38
    package static let expandedCornerRadius: CGFloat = 38
    package static let glassSigma: CGFloat = 20
    package static let fill = RGBA(red: 0.975, green: 0.975, blue: 0.98, alpha: 0.86)
    package static let fillDark = RGBA(red: 0.14, green: 0.14, blue: 0.15, alpha: 0.86)
    package static let dimAlpha: Double = 0
    // Inside it.
    package static let inset: CGFloat = 26
    package static let top: CGFloat = 26
    package static let thumbnail: CGFloat = 62
    package static let thumbnailCorner: CGFloat = 14
    package static let titleGap: CGFloat = 17
    package static let titleSize: CGFloat = 17
    package static let separatorGap: CGFloat = 17
    package static let icon: CGFloat = 64
    package static let iconCorner: CGFloat = 0.225
    package static let column: CGFloat = 85
    package static let labelSize: CGFloat = 13
    package static let labelGap: CGFloat = 8
    package static let round: CGFloat = 64
    package static let symbolSize: CGFloat = 25
    package static let bottom: CGFloat = 22
    package static let closeButton: CGFloat = 44
    package static let listRow: CGFloat = 50
    package static let listCorner: CGFloat = 26
    package static let listTextSize: CGFloat = 17
    package static let editActionsHeight: CGFloat = 36
    // The motion: growing out of the button and back, and View More.
    package static let openAcross = SpringModel(omega: 18, zeta: 0.80)
    package static let openHeight = SpringModel(omega: 17, zeta: 0.82)
    package static let openDown = SpringModel(omega: 18, zeta: 0.72)
    package static let close = SpringModel(duration: 0.4, bounce: 0)
    package static let expand = SpringModel(duration: 0.5, bounce: 0)
}

/// The made-up people and apps the sheet offers (the apps are the drawn home screen's first two).
package enum ShareSheetContent {
    package static let people = ["Anna", "Marco", "Lea", "Nils"]
    package static let apps = ["Tide", "Ledger"]
}

/// The share sheet's content, presented as a sheet by `ShareLink` on iOS.
public struct _ShareSheet: View {
    package let request: _ShareRequest
    package let close: @MainActor () -> Void

    @State private var expanded = false
    /// The items an async exporter gave, once it has.
    @State private var loaded: [_ShareItem] = []
    @Environment(\.colorScheme) private var colorScheme

    public init(request: _ShareRequest, close: @escaping @MainActor () -> Void) {
        self.request = request
        self.close = close
    }

    private typealias M = ShareSheetMetrics

    private var items: [_ShareItem] { request.items + loaded }

    /// Whether the item is an image (Save Image and Assign to Contact are offered for one).
    private var isImage: Bool {
        let types = items.compactMap { item -> UTType? in if case .data(_, let type) = item.kind { return type } else { return nil } }
            + request.pending.map(\.contentType)
        return types.contains { $0 == .png || $0 == .jpeg || $0 == .image || $0.conforms(to: .image) }
    }

    private var title: String {
        if let title = request.previewTitle, !title.isEmpty { return title }
        for item in request.items {
            switch item.kind {
            case .url(let url): return url
            case .text(let text): return text
            case .data: continue
            }
        }
        return isImage ? "Image" : "Item"
    }

    private var ink: Color { colorScheme == .dark ? .white : .black }
    private var soft: Color { Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.12 : 0.06) }
    private var hairline: Color { Color(white: colorScheme == .dark ? 1 : 0, opacity: 0.1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator
            row(ShareSheetContent.people.map { name in AnyView(person(name)) }, labels: ShareSheetContent.people, actions: ShareSheetContent.people.map { _ in sent })
            separator
            row(ShareSheetContent.apps.map { _ in AnyView(appIcon) } + [AnyView(moreIcon)],
                labels: ShareSheetContent.apps + ["More"], actions: [sent, sent, sent])
            separator
            actionsRow
            if expanded {
                list.padding(.top, M.separatorGap + 8)
                editActions.frame(maxWidth: .infinity).padding(.top, M.separatorGap + 6)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, M.inset)
        .padding(.top, M.top)
        .padding(.bottom, M.bottom)
        .frame(maxWidth: .infinity, maxHeight: expanded ? .infinity : nil, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if expanded { closeButton.padding(.top, 12).padding(.trailing, 12) }
        }
        .modifier(_PresentationOptionsModifier(share: expanded ? .expanded : .compact))
        .task { await load() }
    }

    /// Asks the app for the bytes it renders when shared, as iOS does when the sheet opens.
    private func load() async {
        var given: [_ShareItem] = []
        for item in request.pending {
            if let ready = await item.resolve() { given.append(ready) }
        }
        loaded = given
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: M.titleGap) {
            thumbnail
            Text(title)
                .font(.system(size: M.titleSize, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(2)
            Spacer(minLength: expanded ? M.closeButton : 0)
        }
    }

    /// The preview's image, else a plain card (iOS draws its own placeholder, which we never copy).
    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: M.thumbnailCorner, style: .continuous)
        if let image = request.previewImage {
            image.resizable().scaledToFill().frame(width: M.thumbnail, height: M.thumbnail).clipShape(shape)
        } else {
            shape.fill(Color.white)
                .overlay { shape.strokeBorder(Color(white: 0.85), lineWidth: 1) }
                .frame(width: M.thumbnail, height: M.thumbnail)
        }
    }

    private var separator: some View {
        Rectangle().fill(hairline).frame(height: 1).padding(.vertical, M.separatorGap)
    }

    // MARK: Rows

    /// A row of round or square targets, each with its label under it, on the sheet's columns.
    private func row(_ icons: [AnyView], labels: [String], actions: [@MainActor () -> Void]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<icons.count, id: \.self) { index in
                Button(action: actions[index]) {
                    VStack(spacing: M.labelGap) {
                        icons[index]
                        Text(labels[index])
                            .font(.system(size: M.labelSize))
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: M.column - 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(labels[index].replacingOccurrences(of: "\n", with: " "))
                .frame(width: M.column, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, -(M.column - M.icon) / 2 + 2)
    }

    private func person(_ name: String) -> some View {
        Circle().fill(Color(white: 0.72))
            .frame(width: M.icon, height: M.icon)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: M.icon * M.iconCorner, style: .continuous)
            .fill(Color(white: 210.0 / 255))
            .frame(width: M.icon, height: M.icon)
    }

    private var moreIcon: some View {
        RoundedRectangle(cornerRadius: M.icon * M.iconCorner, style: .continuous)
            .fill(Color(white: colorScheme == .dark ? 0.25 : 1))
            .frame(width: M.icon, height: M.icon)
            .overlay {
                Image(systemName: "ellipsis").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color(white: 0.4))
            }
    }

    private var actionsRow: some View {
        var labels = ["Copy"]
        var symbols = ["doc.on.doc"]
        var actions: [@MainActor () -> Void] = [copy]
        if isImage {
            labels += ["Save Image", "Assign to\nContact"]
            symbols += ["square.and.arrow.down", "person.crop.circle"]
            actions += [saveImage, plainClose]
        }
        labels.append(expanded ? "View Less" : "View More")
        symbols.append(expanded ? "chevron.up" : "chevron.down")
        actions.append(toggleMore)
        let icons = symbols.map { symbol in
            AnyView(Circle().fill(soft).frame(width: M.round, height: M.round)
                .overlay { Image(systemName: symbol).font(.system(size: M.symbolSize, weight: .regular)).foregroundStyle(ink) })
        }
        return row(icons, labels: labels, actions: actions)
    }

    // MARK: The full sheet

    private var list: some View {
        let rows: [(String, String)] = isImage
            ? [("printer", "Print"), ("rectangle.stack", "Add to Shared Album"), ("clock", "Create Watch Face"), ("folder", "Save to Files")]
            : [("printer", "Print"), ("folder", "Save to Files")]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { index in
                Button(action: plainClose) {
                    HStack(spacing: 18) {
                        Image(systemName: rows[index].0).font(.system(size: 22)).foregroundStyle(ink).frame(width: 30)
                        Text(rows[index].1).font(.system(size: M.listTextSize)).foregroundStyle(ink)
                        Spacer(minLength: 0)
                    }
                    .frame(height: M.listRow)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rows[index].1)
                if index < rows.count - 1 {
                    Rectangle().fill(hairline).frame(height: 1).padding(.leading, 66).padding(.trailing, 16)
                }
            }
        }
        .background(soft, in: RoundedRectangle(cornerRadius: M.listCorner, style: .continuous))
        .padding(.horizontal, -10)
    }

    private var editActions: some View {
        Button(action: plainClose) {
            Text("Edit Actions")
                .font(.system(size: M.listTextSize))
                .foregroundStyle(ink)
                .padding(.horizontal, 18)
                .frame(height: M.editActionsHeight)
                .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: plainClose) {
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: M.closeButton, height: M.closeButton)
                .background(Circle().fill(Color(white: colorScheme == .dark ? 0.2 : 1)))
                .overlay { Circle().strokeBorder(hairline, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    // MARK: What the parts do

    /// A person or an app: the sheet closes as if the item was sent.
    private var sent: @MainActor () -> Void { close }
    private var plainClose: @MainActor () -> Void { close }

    private var toggleMore: @MainActor () -> Void {
        { withAnimation(.smooth(duration: 0.5)) { expanded.toggle() } }
    }

    /// The image's bytes and MIME type, when the item is an image.
    private var imageData: (Data, String)? {
        for item in items {
            guard case .data(let data, let type) = item.kind, !data.isEmpty else { continue }
            if type == .png { return (data, "image/png") }
            if type == .jpeg || type.conforms(to: .image) || type == .image { return (data, "image/jpeg") }
        }
        return nil
    }

    /// Copy: the image, else the text and links, on the viewer's real clipboard.
    private var copy: @MainActor () -> Void {
        {
            if let (data, mime) = imageData {
                ShareAction._copyImage?(Array(data), mime)
            } else {
                let text = items.compactMap { item -> String? in
                    switch item.kind {
                    case .url(let url): return url
                    case .text(let text): return text
                    case .data(let data, let type): return type.isText ? String(data: data, encoding: .utf8) : nil
                    }
                }.joined(separator: "\n")
                if !text.isEmpty { ShareAction._copyText?(text) }
            }
            close()
        }
    }

    /// Save Image: the image goes in front of the drawn phone's photos.
    private var saveImage: @MainActor () -> Void {
        {
            if let (data, _) = imageData { _PhotoLibrary.shared.save(data) }
            close()
        }
    }
}
