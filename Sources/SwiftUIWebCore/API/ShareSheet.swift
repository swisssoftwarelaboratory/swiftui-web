// The drawn iPhone's share sheet (Docs/elements/ShareLink.md, new-website#668): iOS 27's glass
// panel floating 9 pt above the bottom, as the simulator shows a ShareLink (a glass popover, not
// a sheet: it scales up from its own centre and fades in, nothing dimmed behind it), with the
// item's preview and title, four made-up people, two made-up apps from the drawn home screen and
// More, and the round actions; View More grows it into the full sheet with the grouped list and
// Edit Actions. A person or an app closes it as if sent, Copy puts the item on the viewer's real
// clipboard, Save Image puts it in the drawn phone's photos (`_PhotoLibrary`), the rest close it.
import WebFoundation

/// The share sheet's two stages: the compact card, and the full sheet View More grows it into.
package enum ShareSheetStage: Sendable, Equatable { case compact, expanded }

/// The share sheet's measures, in points, read in the iOS 27 simulator (iPhone 16, 393 x 852):
/// the panel's frame, corners and springs from its layers, the rows by pixel from 3x screenshots
/// (swipe-harness/share-probe-668/FINDINGS.md).
package enum ShareSheetMetrics {
    // The panel: 9 from the window's sides and bottom; its bottom corners follow the screen's.
    package static let sideInset: CGFloat = 9
    package static let bottomInset: CGFloat = 9
    package static let cornerRadius: CGFloat = 38
    package static let bottomCornerRadius: CGFloat = 46
    package static let expandedBottomCornerRadius: CGFloat = 55
    package static let glassSigma: CGFloat = 20
    package static let fill = RGBA(red: 0.98, green: 0.98, blue: 0.98, alpha: 0.9)
    package static let fillDark = RGBA(red: 0.14, green: 0.14, blue: 0.15, alpha: 0.9)
    package static let expandedFill = RGBA(red: 0.996, green: 0.996, blue: 0.996, alpha: 1)
    package static let dimAlpha: Double = 0
    // Inside it: 25.67 in from the compact panel's sides and top, 29.33 in the full sheet's.
    package static let inset: CGFloat = 25.67
    package static let expandedInset: CGFloat = 29.33
    package static let thumbnail: CGFloat = 64
    package static let thumbnailCorner: CGFloat = 16
    package static let titleGap: CGFloat = 15.67
    package static let titleSize: CGFloat = 15
    package static let separatorAbove: CGFloat = 16
    package static let tileBelowSeparator: CGFloat = 15
    package static let tileLabelGap: CGFloat = 7.33
    package static let separatorBelowRow: CGFloat = 17.33
    package static let circleBelowSeparator: CGFloat = 16
    package static let circleLabelGap: CGFloat = 5.67
    package static let tile: CGFloat = 66
    package static let tileCorner: CGFloat = 15
    package static let labelSize: CGFloat = 12
    package static let labelLinePitch: CGFloat = 16
    package static let symbolSize: CGFloat = 27
    package static let bottom: CGFloat = 15.67
    package static let separator = Color(red: 226.0 / 255, green: 226.0 / 255, blue: 227.0 / 255)
    package static let circleFill = Color(white: 230.0 / 255)
    // The full sheet.
    package static let closeButton: CGFloat = 44
    package static let closeTop: CGFloat = 10
    package static let closeTrailing: CGFloat = 16
    package static let listTop: CGFloat = 26.33
    package static let listSide: CGFloat = 16
    package static let listRow: CGFloat = 49.33
    package static let listCorner: CGFloat = 24
    package static let listTextLeading: CGFloat = 56.67
    package static let listTextSize: CGFloat = 17
    package static let listFill = Color(white: 236.0 / 255)
    package static let listSeparator = Color(red: 215.0 / 255, green: 215.0 / 255, blue: 216.0 / 255)
    package static let editActionsTop: CGFloat = 19.33
    package static let editActionsSize = CGSize(width: 116, height: 35.67)
    // The motion, read from Core Animation: in, scale 0.01 to 1 about the panel's centre and the
    // fade on one spring (stiffness 331.90, damping 29.149, the popover's); out on 283.97, 28.648;
    // View More and View Less move the frame and corners on 322.27, 35.90 (critically damped).
    package static let open = SpringModel(mass: 1, stiffness: 331.9007, damping: 29.149)
    package static let close = SpringModel(mass: 1, stiffness: 283.9735, damping: 28.6476)
    package static let expand = SpringModel(mass: 1, stiffness: 322.27, damping: 35.90)
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
    @State private var held = _ShareItemHolder()
    @Environment(\.colorScheme) private var colorScheme

    public init(request: _ShareRequest, close: @escaping @MainActor () -> Void) {
        self.request = request
        self.close = close
    }

    private typealias M = ShareSheetMetrics

    private var items: [_ShareItem] { request.items + (held.given ?? []) }

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
    private var hairline: Color { Color(white: colorScheme == .dark ? 1 : 0, opacity: 0.1) }

    private var inset: CGFloat { expanded ? M.expandedInset : M.inset }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator(above: M.separatorAbove, below: M.tileBelowSeparator)
            grid(ShareSheetContent.people.map { name in AnyView(person(name)) }, labels: ShareSheetContent.people,
                 actions: ShareSheetContent.people.map { _ in sent }, gap: M.tileLabelGap)
            separator(above: M.separatorBelowRow, below: M.tileBelowSeparator)
            grid(ShareSheetContent.apps.map { _ in AnyView(appTile) } + [AnyView(moreTile)],
                 labels: ShareSheetContent.apps + ["More"], actions: [sent, sent, sent], gap: M.tileLabelGap)
            separator(above: M.separatorBelowRow, below: M.circleBelowSeparator)
            actionsRow
            if expanded {
                list.padding(.top, M.listTop).padding(.horizontal, M.listSide - inset)
                editActions.frame(maxWidth: .infinity).padding(.top, M.editActionsTop)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, inset)
        .padding(.top, inset)
        .padding(.bottom, expanded ? 0 : M.bottom)
        .frame(maxWidth: .infinity, maxHeight: expanded ? .infinity : nil, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if expanded { closeButton.padding(.top, M.closeTop).padding(.trailing, M.closeTrailing) }
        }
        .modifier(_PresentationOptionsModifier(share: expanded ? .expanded : .compact))
        .task {
            // The app renders what it shares on our main thread (iOS does it in the share
            // service's process): asked once the panel has settled, its work never costs the
            // opening frames (a 3x image took a ~100 ms frame, which ate the opening's start).
            try? await Task.sleep(nanoseconds: 600_000_000)
            _ = await held.resolve(request)
        }
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

    /// The preview's image, else a plain white tile with a grey rim (iOS draws a placeholder of its
    /// own there, which we never copy).
    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: M.thumbnailCorner, style: .continuous)
        if let image = request.previewImage {
            image.resizable().scaledToFill().frame(width: M.thumbnail, height: M.thumbnail).clipShape(shape)
        } else {
            shape.fill(Color.white)
                .overlay { shape.strokeBorder(M.separator, lineWidth: 1) }
                .frame(width: M.thumbnail, height: M.thumbnail)
        }
    }

    private func separator(above: CGFloat, below: CGFloat) -> some View {
        Rectangle().fill(colorScheme == .dark ? Color(white: 1, opacity: 0.12) : M.separator)
            .frame(height: 1).padding(.top, above).padding(.bottom, below)
    }

    // MARK: Rows

    /// Four columns spread across the content, first at its leading edge and last at its trailing
    /// one (85.67 apart in the compact panel), each a 66 pt tile or circle with its label centred
    /// under it; a shorter row leaves the last columns empty.
    private func grid(_ icons: [AnyView], labels: [String], actions: [@MainActor () -> Void], gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 { Spacer(minLength: 0) }
                if index < icons.count {
                    Button(action: actions[index]) {
                        VStack(spacing: gap) {
                            icons[index]
                            Text(labels[index])
                                .font(.system(size: M.labelSize))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.center)
                                .lineSpacing(M.labelLinePitch - 14.32)
                                .fixedSize()
                                .frame(width: M.tile)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels[index].replacingOccurrences(of: "\n", with: " "))
                } else {
                    Color.clear.frame(width: M.tile, height: M.tile)
                }
            }
        }
    }

    private func person(_ name: String) -> some View {
        Circle().fill(Color(white: 0.72))
            .frame(width: M.tile, height: M.tile)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// A made-up app: the drawn home screen's plain grey tile.
    private var appTile: some View {
        RoundedRectangle(cornerRadius: M.tileCorner, style: .continuous)
            .fill(Color(white: 210.0 / 255))
            .frame(width: M.tile, height: M.tile)
    }

    /// More: a white tile with a soft shadow and three grey dots.
    private var moreTile: some View {
        RoundedRectangle(cornerRadius: M.tileCorner, style: .continuous)
            .fill(Color(white: colorScheme == .dark ? 0.25 : 1))
            .shadow(color: Color(white: 0, opacity: 0.06), radius: 6, x: 0, y: 1)
            .frame(width: M.tile, height: M.tile)
            .overlay {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(white: 0.4)).frame(width: 8, height: 8) }
                }
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
            AnyView(Circle().fill(colorScheme == .dark ? Color(white: 1, opacity: 0.14) : M.circleFill).frame(width: M.tile, height: M.tile)
                .overlay { Image(systemName: symbol).font(.system(size: M.symbolSize, weight: .regular)).foregroundStyle(ink) })
        }
        return grid(icons, labels: labels, actions: actions, gap: M.circleLabelGap)
    }

    // MARK: The full sheet

    private var list: some View {
        let rows: [(String, String)] = isImage
            ? [("printer", "Print"), ("rectangle.stack", "Add to Shared Album"), ("clock", "Create Watch Face"), ("folder", "Save to Files")]
            : [("printer", "Print"), ("folder", "Save to Files")]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { index in
                Button(action: plainClose) {
                    ZStack(alignment: .leading) {
                        Image(systemName: rows[index].0).font(.system(size: 22)).foregroundStyle(ink)
                            .frame(width: 32).padding(.leading, 16)
                        Text(rows[index].1).font(.system(size: M.listTextSize)).foregroundStyle(ink)
                            .padding(.leading, M.listTextLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: M.listRow, maxHeight: M.listRow, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rows[index].1)
                if index < rows.count - 1 {
                    Rectangle().fill(M.listSeparator).frame(height: 1).padding(.leading, M.listTextLeading - 0.67).padding(.trailing, 16)
                }
            }
        }
        .background(colorScheme == .dark ? Color(white: 1, opacity: 0.1) : M.listFill, in: RoundedRectangle(cornerRadius: M.listCorner, style: .continuous))
    }

    private var editActions: some View {
        Button(action: plainClose) {
            Text("Edit Actions")
                .font(.system(size: M.listTextSize))
                .foregroundStyle(ink)
                .frame(width: M.editActionsSize.width, height: M.editActionsSize.height)
                .background { Capsule().fill(Color(white: colorScheme == .dark ? 0.2 : 1)).shadow(color: Color(white: 0, opacity: 0.06), radius: 6, x: 0, y: 1) }
                .overlay { Capsule().strokeBorder(hairline, lineWidth: 0.67) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: plainClose) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: M.closeButton, height: M.closeButton)
                .background(Circle().fill(Color(white: colorScheme == .dark ? 0.2 : 1)))
                .overlay { Circle().strokeBorder(hairline, lineWidth: 0.67) }
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
        { expanded.toggle() }
    }

    /// The image's bytes and MIME type, when the item is an image.
    private static func imageData(_ items: [_ShareItem]) -> (Data, String)? {
        for item in items {
            guard case .data(let data, let type) = item.kind, !data.isEmpty else { continue }
            if type == .png { return (data, "image/png") }
            if type == .jpeg || type.conforms(to: .image) || type == .image { return (data, "image/jpeg") }
        }
        return nil
    }

    /// Copy: the image, else the text and links, on the viewer's real clipboard.
    /// The sheet closes at once, as on iOS; an item the app has not rendered yet is copied or
    /// saved once it has.
    private func withItems(_ act: @escaping @MainActor ([_ShareItem]) -> Void) {
        let request = request, holder = held
        if request.pending.isEmpty {
            act(request.items)
        } else if let given = holder.given {
            act(request.items + given)
        } else {
            Task { @MainActor in act(request.items + (await holder.resolve(request))) }
        }
        close()
    }

    private var copy: @MainActor () -> Void {
        { withItems(Self.copy) }
    }

    private static func copy(_ items: [_ShareItem]) {
            if let (data, mime) = imageData(items) {
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
    }

    /// Save Image: the image goes in front of the drawn phone's photos.
    private var saveImage: @MainActor () -> Void {
        { withItems { items in if let (data, _) = Self.imageData(items) { _PhotoLibrary.shared.save(data) } } }
    }
}

/// The items an app's async exporter gave the share sheet, asked for once.
@MainActor
final class _ShareItemHolder {
    private(set) var given: [_ShareItem]?
    private var running: Task<[_ShareItem], Never>?

    func resolve(_ request: _ShareRequest) async -> [_ShareItem] {
        if let given { return given }
        if request.pending.isEmpty { given = []; return [] }
        let work = running ?? Task { @MainActor in
            var items: [_ShareItem] = []
            for item in request.pending {
                if let ready = await item.resolve() { items.append(ready) }
            }
            return items
        }
        running = work
        let items = await work.value
        given = items
        return items
    }
}
