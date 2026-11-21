// The drawn phone's photo library (Docs/elements/PhotosPicker.md): the photos every app on the
// page sees in the photos picker, newest first. The build lays them out beside the app's assets
// (`scripts/photos.py`): the app's own demo photos (its web package's `Photos` folder), then the
// everyday set every app shares (`Fixtures/Photos/Everyday`), listed in `photos/photos.json`.
// Whatever is saved later (the share sheet's Save Image) goes in front of them, newest first, and
// lasts as long as the page does.
import WebCombine
import WebFoundation

/// The drawn phone's photo library: what the photos picker shows and hands back.
@MainActor
public final class _PhotoLibrary: WebCombine.ObservableObject {
    /// One photo: where its bytes are, and its upright pixel size.
    public struct Photo: Identifiable, Hashable, Sendable {
        /// Stable for the page's life: the file's path, or `saved-<n>` for a saved one.
        public let id: String
        /// The image file: its path in the build's assets (`photos/…`), or a `data:` URL for a saved photo.
        public let url: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        /// A saved photo's bytes (a listed photo's are read from the build's assets when picked).
        package let data: Data?

        public init(id: String, url: String, pixelWidth: Int, pixelHeight: Int, data: Data? = nil) {
            self.id = id
            self.url = url
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.data = data
        }
    }

    /// The page's one library, shared by every picker and the share sheet.
    public static let shared = _PhotoLibrary()

    public let objectWillChange = ObservableObjectPublisher()

    /// Newest first: saved photos, then the app's own, then the everyday set.
    public var photos: [Photo] { saved + listed }

    /// Whether the build's list has been read (or found missing).
    public private(set) var isLoaded = false

    private var saved: [Photo] = []
    private var listed: [Photo] = []
    private var loading: Task<Void, Never>?
    private var savedCount = 0

    /// The build's list, as a bundle file (`Data(contentsOf:)` reads it from the build's assets).
    nonisolated package static var listURL: URL? { Bundle.main.url(forResource: "photos/photos", withExtension: "json") }

    /// Starts loading one photo into the page's image cache (the host's image loader, set with
    /// `Runtime.imageLoader`). The first screen of photos is asked for as soon as the list is
    /// read, so the grid is full while the sheet is still sliding up, as on a phone.
    nonisolated(unsafe) package static var prefetch: ((String) -> Void)?
    /// How many photos that is: eight rows of three, a little more than one screen.
    package static let prefetchCount = 24

    package init(listed: [Photo] = []) {
        self.listed = listed
        isLoaded = !listed.isEmpty
    }

    /// Reads the build's list once; later calls wait for the first. A missing or broken list is
    /// an empty library, as on a phone with no photos.
    public func load() async {
        if isLoaded { return }
        if let loading { await loading.value; return }
        let task = Task { @MainActor in
            let listed = await Self.readList()
            objectWillChange.send()
            self.listed = listed
            isLoaded = true
            prefetchFirstScreen()
        }
        loading = task
        await task.value
    }

    /// Asks the page's image cache for the first screen of photos, newest first.
    package func prefetchFirstScreen() {
        for photo in photos.prefix(Self.prefetchCount) { Self.prefetch?(photo.url) }
    }

    /// Puts a photo in front of the others, as Save Image does on a phone. Nil for bytes that are
    /// not an image the page can show.
    @discardableResult
    public func save(_ data: Data) -> Photo? {
        guard let info = _ImageFileInfo(data) else { return nil }
        savedCount += 1
        let photo = Photo(id: "saved-\(savedCount)", url: "data:\(info.kind.mimeType);base64," + data.base64EncodedString(),
                          pixelWidth: Int(info.uprightPixelSize.width), pixelHeight: Int(info.uprightPixelSize.height), data: data)
        objectWillChange.send()
        saved.insert(photo, at: 0)
        return photo
    }

    /// The photo with this id, if the library has it.
    public func photo(id: String) -> Photo? { photos.first { $0.id == id } }

    /// A photo's bytes: kept for a saved one, read from the build's assets for a listed one.
    public func data(for photo: Photo) async -> Data? {
        if let data = photo.data { return data }
        guard let url = Bundle.main.url(forResource: photo.url, withExtension: nil) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// A photo's bytes by id (nil when the library has no such photo).
    public func data(id: String) async -> Data? {
        await load()
        guard let photo = photo(id: id) else { return nil }
        return await data(for: photo)
    }

    /// Image bytes as `T`, as a picked item's `loadTransferable` gives them: the bytes for `Data`,
    /// else whatever `T` imports from an image of the file's type. Nil when `T` takes no image.
    nonisolated public static func imported<T: Transferable>(_ data: Data, as type: T.Type) -> T? {
        if let data = data as? T { return data }
        let mime = _ImageFileInfo(data)?.kind.mimeType ?? "image/jpeg"
        return _TransferItem(external: [ExternalDragItem(type: mime, data: data)]).load(as: T.self)
    }

    /// The content types a photo offers, for `supportedContentTypes`.
    public func contentTypes(id: String) -> [UTType] {
        guard let photo = photo(id: id) else { return [] }
        let lower = photo.url.lowercased()
        if lower.hasSuffix(".png") || lower.hasPrefix("data:image/png") { return [.png] }
        if lower.hasSuffix(".gif") || lower.hasPrefix("data:image/gif") { return [.gif] }
        return [.jpeg]
    }

    private struct List: Decodable {
        struct Entry: Decodable { let file: String; let width: Int; let height: Int }
        let photos: [Entry]
    }

    private static func readList() async -> [Photo] {
        guard let url = listURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        return list.photos.map { Photo(id: $0.file, url: "photos/" + $0.file, pixelWidth: $0.width, pixelHeight: $0.height) }
    }
}
