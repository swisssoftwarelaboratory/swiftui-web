// Apple's `PhotosUI` module for wasm: the SwiftUI photos picker. A page has no photo library
// (a file input would be the browser's stand-in, not driven from here yet), so the picker's
// label shows as a button that opens nothing, `photosPicker(isPresented:)` presents nothing and
// hands the presentation back, and no item is ever selected. Accepted for source compatibility.
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

/// A picked item (none are picked on the web).
public struct PhotosPickerItem: Equatable, Hashable, @unchecked Sendable {
    public enum EncodingDisambiguationPolicy: Equatable, Hashable, Sendable { case automatic, current, compatible }
    public let itemIdentifier: String?
    public var supportedContentTypes: [UTType] { [] }
    public init(itemIdentifier: String) { self.itemIdentifier = itemIdentifier }

    /// Loads the item as a transferable value: nothing to load on the web.
    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? { nil }
}

/// How a multi-selection picker treats the selection.
public struct PhotosPickerSelectionBehavior: Equatable, Hashable, Sendable {
    package let name: String
    public static let `default` = PhotosPickerSelectionBehavior(name: "default")
    public static let ordered = PhotosPickerSelectionBehavior(name: "ordered")
    public static let continuous = PhotosPickerSelectionBehavior(name: "continuous")
}

/// A button that would present the photos picker (its label, inert on the web).
@MainActor @preconcurrency
public struct PhotosPicker<Label: View>: View {
    nonisolated(unsafe) private let label: Label

    @preconcurrency nonisolated public init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                            @ViewBuilder label: @Sendable () -> Label) {
        self.label = label()
    }

    @preconcurrency nonisolated public init(selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                            selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
                                            @ViewBuilder label: @Sendable () -> Label) {
        self.label = label()
    }

    public var body: some View {
        Button(action: {}) { label }
    }
}

extension PhotosPicker where Label == Text {
    nonisolated public init(_ titleKey: LocalizedStringKey, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                            preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) {
        self.init(selection: selection, matching: filter, preferredItemEncoding: preferredItemEncoding) { Text(titleKey) }
    }
}

extension View {
    /// Presents the photos picker: nothing to present on the web, so the presentation ends at once.
    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        onChange(of: isPresented.wrappedValue) { _, presented in if presented { isPresented.wrappedValue = false } }
    }

    nonisolated public func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>, maxSelectionCount: Int? = nil,
                                         selectionBehavior: PhotosPickerSelectionBehavior = .default, matching filter: PHPickerFilter? = nil,
                                         preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic) -> some View {
        onChange(of: isPresented.wrappedValue) { _, presented in if presented { isPresented.wrappedValue = false } }
    }
}
#endif
