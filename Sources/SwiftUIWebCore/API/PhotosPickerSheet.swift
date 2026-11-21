// The photos picker's sheet (Docs/elements/PhotosPicker.md): iOS 27's full sheet over the app,
// drawn from the drawn phone's photo library (`_PhotoLibrary`). Measured from the iOS 27
// simulator (iPhone 16, 393 pt): a round X and the Photos | Collections switch on one line, the
// Private Access banner naming the app, the photos three across edge to edge, and the bottom bar
// with •••, Location Included and search. PhotosUI presents it as a sheet, so it slides up and is
// pulled down like any sheet. One tap on a photo picks it when one photo is asked for; with more,
// taps mark photos and the check button hands them over.
import WebFoundation

/// The photos picker's content, presented as a sheet by PhotosUI.
public struct _PhotosPickerSheet: View {
    /// At most this many photos (1: a tap picks at once; nil: no limit).
    package let limit: Int?
    /// The photos already chosen (ids in `_PhotoLibrary`), marked when the sheet opens.
    package let preselected: [String]
    package let pick: @MainActor ([String]) -> Void
    package let cancel: @MainActor () -> Void

    @ObservedObject private var library: _PhotoLibrary
    @State private var marked: [String]
    @State private var tab = Tab.photos
    @State private var locationIncluded = true
    @Environment(\.colorScheme) private var colorScheme

    /// Closing the banner lasts for the page, as it lasts on a phone.
    @MainActor private static var bannerClosed = false
    @State private var bannerShown = !_PhotosPickerSheet.bannerClosed

    package enum Tab: Hashable { case photos, collections }

    public init(limit: Int?, preselected: [String] = [], library: _PhotoLibrary? = nil,
                pick: @escaping @MainActor ([String]) -> Void, cancel: @escaping @MainActor () -> Void) {
        self.limit = limit
        self.preselected = preselected
        self.pick = pick
        self.cancel = cancel
        _library = ObservedObject(wrappedValue: library ?? _PhotoLibrary.shared)
        _marked = State(initialValue: limit == 1 ? [] : preselected)
    }

    private var single: Bool { limit == 1 }

    /// The app's name as the banner quotes it: its display name, else its bundle name.
    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? "App"
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color(white: colorScheme == .dark ? 0 : 1).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: M.contentTop)
                    if tab == .photos {
                        if bannerShown { banner.padding(.horizontal, M.bannerInset).padding(.bottom, M.bannerGap) }
                        grid
                    } else {
                        collections
                    }
                    Color.clear.frame(height: M.bottomClearance)
                }
            }
            topBar
            VStack { Spacer(); bottomBar }
        }
        .task { await library.load() }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 0) {
            roundButton(symbol: "xmark", label: "Cancel", action: cancel)
            Spacer()
            switcher
            Spacer()
            if single {
                Color.clear.frame(width: M.roundButton, height: M.roundButton)
            } else {
                roundButton(symbol: "checkmark", label: "Add", tinted: !marked.isEmpty) { if !marked.isEmpty { pick(marked) } }
            }
        }
        .padding(.horizontal, M.edge)
        .padding(.top, M.topBarTop)
    }

    private var switcher: some View {
        HStack(spacing: 0) {
            segment("Photos", .photos)
            segment("Collections", .collections)
        }
        .padding(M.switcherPadding)
        .modifier(_PickerGlass(shape: Capsule()))
    }

    private func segment(_ title: String, _ value: Tab) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, M.segmentPadding)
                .frame(minWidth: M.segmentMinWidth)
                .frame(height: M.segmentHeight)
                .background { if tab == value { Capsule().fill(Color(white: colorScheme == .dark ? 0.25 : 0.9)) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private func roundButton(symbol: String, label: String, tinted: Bool = false, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tinted ? Color.white : Color.primary)
                .frame(width: M.roundButton, height: M.roundButton)
                .background { if tinted { Circle().fill(Color.accentColor) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(_PickerGlass(shape: Circle()))
        .accessibilityLabel(label)
    }

    // MARK: Banner

    private var banner: some View {
        HStack(alignment: .top, spacing: M.bannerIconGap) {
            // Apple's Photos icon is never drawn (map 194's Notes): a plain tile names it.
            RoundedRectangle(cornerRadius: M.bannerIconRadius, style: .continuous)
                .fill(Color.white)
                .overlay { Text("Photos").font(.system(size: 8, weight: .medium)).foregroundStyle(Color(white: 0.45)) }
                .overlay { RoundedRectangle(cornerRadius: M.bannerIconRadius, style: .continuous).stroke(Color(white: 0.85), lineWidth: 0.5) }
                .frame(width: M.bannerIcon, height: M.bannerIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text("Private Access to Photos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.trailing, M.bannerCloseLane)
                Text("Your photo library is shown here, but \u{201C}\(appName)\u{201D} can only access the items you select.")
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.trailing, M.bannerTextTrailing)
                Rectangle().fill(Color(white: 0.85)).frame(height: 0.5).padding(.top, 12)
                Text("Learn More\u{2026}")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 11)
                    .padding(.bottom, 14)
            }
        }
        .padding(.leading, M.bannerPadding)
        .padding(.top, M.bannerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: M.bannerRadius, style: .continuous).fill(Color(white: colorScheme == .dark ? 0.11 : 0.95)))
        .overlay(alignment: .topTrailing) {
            Button {
                _PhotosPickerSheet.bannerClosed = true
                withAnimation(.smooth) { bannerShown = false }
            } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .regular)).foregroundStyle(Color.secondary)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4).padding(.trailing, 6)
            .accessibilityLabel("Close")
        }
    }

    // MARK: Photos

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: M.cellGap), count: 3), spacing: M.cellGap) {
            ForEach(library.photos) { photo in cell(photo) }
        }
    }

    private func cell(_ photo: _PhotoLibrary.Photo) -> some View {
        let order = marked.firstIndex(of: photo.id)
        return Button { tap(photo) } label: {
            Color(white: 0.9)
                .aspectRatio(1, contentMode: .fit)
                .overlay { Self.image(photo).resizable().scaledToFill() }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if !single, let order {
                        Text("\(order + 1)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.accentColor))
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                            .padding(5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(order != nil ? .isSelected : [])
    }

    /// The photo as an image: the painter loads a path under the build's assets, or a `data:` URL.
    private static func image(_ photo: _PhotoLibrary.Photo) -> Image {
        Image(source: .url(photo.url, pixelSize: CGSize(width: photo.pixelWidth, height: photo.pixelHeight), scale: 1), label: nil)
    }

    private func tap(_ photo: _PhotoLibrary.Photo) {
        if single { pick([photo.id]); return }
        if let index = marked.firstIndex(of: photo.id) { marked.remove(at: index); return }
        if let limit, limit > 0, marked.count >= limit { return }
        marked.append(photo.id)
    }

    // MARK: Collections

    private var collections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { tab = .photos } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Color(white: 0.9)
                        .frame(width: M.albumSide, height: M.albumSide)
                        .overlay { if let first = library.photos.first { Self.image(first).resizable().scaledToFill() } }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Recents").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.primary)
                    Text("\(library.photos.count)").font(.system(size: 13)).foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, M.bannerInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bottom

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.primary)
                .frame(width: M.bottomButton, height: M.bottomButton)
                .modifier(_PickerGlass(shape: Circle()))
                .accessibilityLabel("Options")
            Spacer()
            Button { locationIncluded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: locationIncluded ? "location.fill" : "location.slash.fill").font(.system(size: 15, weight: .semibold))
                    Text(locationIncluded ? "Location Included" : "No Location").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 16)
                .frame(height: M.bottomButton)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modifier(_PickerGlass(shape: Capsule()))
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium)).foregroundStyle(Color.primary)
                .frame(width: M.bottomButton, height: M.bottomButton)
                .modifier(_PickerGlass(shape: Circle()))
                .accessibilityLabel("Search")
        }
        .padding(.horizontal, M.bottomEdge)
        .padding(.bottom, M.bottomBarBottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// The sheet's measurements, in points from the iOS 27 simulator.
    private enum M {
        static let edge: CGFloat = 16
        static let topBarTop: CGFloat = 16
        static let roundButton: CGFloat = 44
        static let switcherPadding: CGFloat = 4
        static let segmentPadding: CGFloat = 11
        static let segmentMinWidth: CGFloat = 87
        static let segmentHeight: CGFloat = 39
        static let contentTop: CGFloat = 78
        static let bannerInset: CGFloat = 20
        static let bannerGap: CGFloat = 12
        static let bannerPadding: CGFloat = 12
        static let bannerRadius: CGFloat = 26
        static let bannerIcon: CGFloat = 38
        static let bannerIconRadius: CGFloat = 9
        static let bannerIconGap: CGFloat = 12
        static let bannerCloseLane: CGFloat = 40
        static let bannerTextTrailing: CGFloat = 36
        static let cellGap: CGFloat = 5.0 / 3
        static let albumSide: CGFloat = 168
        static let bottomButton: CGFloat = 48
        static let bottomEdge: CGFloat = 28
        static let bottomBarBottom: CGFloat = 28
        static let bottomClearance: CGFloat = 96
    }
}

/// iOS 27's glass on the picker's buttons: the material, a light rim and a soft shadow, which is
/// what shows of it on the sheet's white (the fork's glass is the material alone).
struct _PickerGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background { shape.fill(.ultraThinMaterial).shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2) }
            .overlay { shape.stroke(Color(white: colorScheme == .dark ? 0.3 : 0.86), lineWidth: 0.5) }
    }
}
