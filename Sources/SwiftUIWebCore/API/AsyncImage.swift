// `AsyncImage`: a view that loads an image from a URL through the runtime's image loader (the
// browser host fetches with an `Image` element, the native host with `Data(contentsOf:)`) and
// shows its content for the current phase. Docs/elements/AsyncImage.md.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The phases of loading an image.
public enum AsyncImagePhase: Sendable {
    /// Nothing loaded yet.
    case empty
    /// The image loaded.
    case success(Image)
    /// Loading failed.
    case failure(any Error)

    /// The loaded image, if any.
    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }

    /// The error, if loading failed.
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// The error an `AsyncImage` reports when the host could not load the URL.
public struct AsyncImageLoadingError: Error, Sendable {
    public let url: URL?
    public init(url: URL?) { self.url = url }
}

/// A view that asynchronously loads and displays an image.
public struct AsyncImage<Content: View>: View {
    package let url: URL?
    package let scale: CGFloat
    /// The transaction a phase change applies with (`transaction:`), its animation included.
    package var transaction: Transaction = Transaction()
    package let content: @MainActor (AsyncImagePhase) -> Content

    /// Loads and displays an image from the URL; a placeholder while it loads.
    public init(url: URL?, scale: CGFloat = 1) where Content == _AsyncImageDefaultContent {
        self.url = url
        self.scale = scale
        content = { phase in _AsyncImageDefaultContent(phase: phase) }
    }

    /// Loads the image, showing `content` for a loaded image and `placeholder` until then.
    public init<I: View, P: View>(url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping @MainActor (Image) -> I, @ViewBuilder placeholder: @escaping @MainActor () -> P)
    where Content == _ConditionalContent<I, P> {
        self.url = url
        self.scale = scale
        self.content = { phase in
            if let image = phase.image { return ViewBuilder.buildEither(first: content(image)) }
            return ViewBuilder.buildEither(second: placeholder())
        }
    }

    /// Loads the image, showing `content` for every phase.
    public init(url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(), @ViewBuilder content: @escaping @MainActor (AsyncImagePhase) -> Content) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<AsyncImage<Content>>) -> TypedNode<AsyncImage<Content>> {
        AsyncImageNode(context)
    }
}

/// The default content: the image, else the placeholder ink (measured 2026-10-11: black at
/// 13.7 %, white at 13.7 % in the dark appearance, filling the proposal; the ink of
/// `redacted(reason: .placeholder)`).
public struct _AsyncImageDefaultContent: View {
    let phase: AsyncImagePhase
    public var body: some View {
        if let image = phase.image {
            image
        } else {
            _PlaceholderInk()
        }
    }
}

/// A flexible fill in the environment's placeholder ink.
package struct _PlaceholderInk: View {
    @Environment(\.self) private var environment
    package var body: some View {
        let ink = environment._placeholderColor
        Color(red: ink.red, green: ink.green, blue: ink.blue, opacity: ink.alpha)
    }
}

extension Runtime {
    /// The host's image loader; without one every `AsyncImage` fails.
    public var imageLoader: (any _ImageLoading)? {
        get { _imageLoader }
        set {
            _imageLoader = newValue
            _PhotoLibrary.prefetch = newValue.map { loader in { [weak loader] url in _ = loader?.state(for: url) } }
        }
    }

    /// Tells the runtime a load finished: every `AsyncImage` re-evaluates its phase.
    public func imageLoadDidFinish() {
        for node in asyncImageNodes.compactMap(\.node) { node.reload() }
        asyncImageNodes.removeAll { $0.node == nil }
        setNeedsDisplay()
    }

    package func register(asyncImage node: any _AsyncImageReloading) {
        if !asyncImageNodes.contains(where: { $0.node === node }) { asyncImageNodes.append(WeakAsyncImageNode(node: node)) }
    }

    /// Views sharing a URL share its load (the loader caches by URL); the last one to unmount
    /// while it is still loading cancels it.
    package func retainImageLoad(_ url: String) {
        imageLoadUses[url, default: 0] += 1
    }

    package func releaseImageLoad(_ url: String) {
        guard let count = imageLoadUses[url] else { return }
        if count <= 1 {
            imageLoadUses[url] = nil
            if case .loading = imageLoader?.state(for: url) { imageLoader?.cancel(url) }
        } else {
            imageLoadUses[url] = count - 1
        }
    }
}

/// A node that re-reads its image's load state (`AsyncImageNode`).
@MainActor
package protocol _AsyncImageReloading: AnyObject {
    func reload()
}

package struct WeakAsyncImageNode {
    weak var node: (any _AsyncImageReloading)?
}
