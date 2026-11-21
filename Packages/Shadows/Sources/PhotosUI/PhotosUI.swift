// Apple's `PhotosUI` module for wasm: the SwiftUI photos picker (Docs/elements/PhotosPicker.md).
// `PhotosPicker` and `photosPicker(isPresented:)` present iOS 27's picker sheet
// (`_PhotosPickerSheet`) over the drawn phone's photo library (`_PhotoLibrary`): the app's own
// demo photos, then the everyday set every app shares. A picked photo comes back as a
// `PhotosPickerItem` whose `loadTransferable` gives the image's bytes.
#if os(WASI)
import SwiftUI

/// The kinds of asset a picker shows.
public struct PHPickerFilter: Equatable, Hashable, @unchecked Sendable {
    package let name: String
    public static let images = PHPickerFilter(name: "images")
    public static let videos = PHPickerFilter(name: "videos")
    public static let livePhotos = PHPickerFilter(name: "livePhotos")
    public static let screenshots = PHPickerFilter(name: "screenshots")
    public static func any(of filters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(name: filters.map(\.name).joined(separator: "|")) }
    public static func all(of filters: [PHPickerFilter]) -> PHPickerFilter { PHPickerFilter(name: filters.map(\.name).joined(separator: "&")) }
    public static func not(_ filter: PHPickerFilter) -> PHPickerFilter { PHPickerFilter(name: "!" + filter.name) }
}

/// A picked photo: one of the drawn phone's photos (`_PhotoLibrary`).
public struct PhotosPickerItem: Equatable, Hashable, @unchecked Sendable {
    public enum EncodingDisambiguationPolicy: Equatable, Hashable, Sendable { case automatic, current, compatible }
    /// Nil, as on iOS for a picker not given a photo library.
    public let itemIdentifier: String?
    /// The photo's id in the drawn phone's library.
    package let photo: String

    public init(itemIdentifier: String) { self.itemIdentifier = itemIdentifier; photo = itemIdentifier }
    package init(photo: String) { itemIdentifier = nil; self.photo = photo }

    /// The photo's file type (JPEG for the library's photos).
    @MainActor public var supportedContentTypes: [UTType] { _PhotoLibrary.shared.contentTypes(id: photo) }

    /// Loads the photo as a transferable value: its bytes as `Data`, or what `T` imports from them.
    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        let photo = photo
        guard let data = await _PhotoLibrary.shared.data(id: photo) else { return nil }
        return _PhotoLibrary.imported(data, as: T.self)
    }
}

/// How a multi-selection picker treats the selection.
public struct PhotosPickerSelectionBehavior: Equatable, Hashable, Sendable {
    package let name: String
    public static let `default` = PhotosPickerSelectionBehavior(name: "default")
    public static let ordered = PhotosPickerSelectionBehavior(name: "ordered")
    public static let continuous = PhotosPickerSelectionBehavior(name: "continuous")
}

/// A button that presents the photos picker: iOS 27's sheet of the drawn phone's photos.
@MainActor @preconcurrency
public struct PhotosPicker<Label: View>: View {
    nonisolated(unsafe) private let label: Label
    nonisolated(unsafe) private let single: Binding<PhotosPickerItem?>?
    nonisolated(unsafe) private let multiple: Binding<[PhotosPickerItem]>?
    private let limit: Int?
    @State private var presented = false

    @preconcurrency nonisolated public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                            @ViewBuilder label: @Sendable () -> Label) {
        self.label = label()
        single = selection
        multiple = nil
        limit = 1
    }

    @preconcurrency nonisolated public init(selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                            selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                            @ViewBuilder label: @Sendable () -> Label) {
        self.label = label()
        single = nil
        multiple = selection
        limit = maxSelectionCount.flatMap { $0 > 0 ? $0 : nil }
    }

    public var body: some View {
        Button(action: { presented = true }) { label }
            .modifier(_PhotosPickerPresenter(isPresented: $presented, single: single, multiple: multiple, limit: limit))
    }
}

extension PhotosPicker where Label == Text {
    nonisolated public init(_ titleKey: LocalizedStringKey, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }

    nonisolated public init(_ titleKey: LocalizedStringKey, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                            selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: filter,
                  preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }
}

/// Presents the picker's sheet while `isPresented` is true and writes what was picked into the
/// selection: one tap for a single photo, the check button for several.
struct _PhotosPickerPresenter: ViewModifier {
    nonisolated(unsafe) private let presented: Binding<Bool>
    nonisolated(unsafe) private let single: Binding<PhotosPickerItem?>?
    nonisolated(unsafe) private let multiple: Binding<[PhotosPickerItem]>?
    private let limit: Int?

    nonisolated init(isPresented: Binding<Bool>, single: Binding<PhotosPickerItem?>?, multiple: Binding<[PhotosPickerItem]>?, limit: Int?) {
        presented = isPresented
        self.single = single
        self.multiple = multiple
        self.limit = limit
    }

    func body(content: Content) -> some View {
        let presented = presented
        // The library's list is read as soon as a picker is on screen, so the sheet's first
        // frames already hold the photos.
        return content.task { await _PhotoLibrary.shared.load() }.sheet(isPresented: presented) {
            _PhotosPickerSheet(limit: limit, preselected: multiple?.wrappedValue.map(\.photo) ?? [], pick: { ids in
                if let single { single.wrappedValue = ids.first.map { PhotosPickerItem(photo: $0) } }
                if let multiple { multiple.wrappedValue = ids.map { PhotosPickerItem(photo: $0) } }
                presented.wrappedValue = false
            }, cancel: { presented.wrappedValue = false })
        }
    }
}

extension View {
    /// Presents the photos picker while `isPresented` is true; a tapped photo becomes the selection.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        modifier(_PhotosPickerPresenter(isPresented: isPresented, single: selection, multiple: nil, limit: 1))
    }

    /// Presents the photos picker for several photos; the check button sets the selection.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                         selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        modifier(_PhotosPickerPresenter(isPresented: isPresented, single: nil, multiple: selection, limit: maxSelectionCount.flatMap { $0 > 0 ? $0 : nil }))
    }
}
#endif
