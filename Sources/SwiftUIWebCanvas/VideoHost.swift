// The browser behind AVFoundation's video (new-website#746): an item's media plays in a
// `<video>` kept out of sight, and an `AVPlayerLayer` paints its current frame into the frame
// as a surface (`DisplayCommand.drawSurface`), so whatever the app shows above the layer stays
// above it. A bundled clip offers its own file first and the build's WebM beside it second:
// Safari shows HEVC with its alpha, Chrome and Firefox show VP9 with its alpha (and not HEVC's).
#if os(WASI)
import JavaScriptKit
import AVFoundation

@MainActor
enum VideoHost {
    static func install() {
        _AVVideoHost.make = { (url: URL, ready: @escaping (Double) -> Void, ended: @escaping () -> Void, failed: @escaping () -> Void,
                               frame: @escaping () -> Void) -> (any _AVVideoElement)? in
            VideoSurface(sources: _MemoryFiles._clipSources(url), ready: ready, ended: ended, failed: failed, frame: frame)
        }
        _AVVideoHost.clipFacts = { url in _MemoryFiles._clipFacts(url) }
    }
}

@MainActor
final class VideoSurface: _AVVideoElement {
    let surface: Int
    private let video: JSObject
    private var closures: [JSClosure] = []
    nonisolated(unsafe) private static var next = 0

    /// The script that makes the video: the page-wide surface table, the hidden box the videos
    /// sit in (Safari decodes a video's frames only while it is in the document), the source
    /// the browser shows with its alpha, and a callback on every new picture.
    private static let maker: JSObject? = JSObject.global.Function.function?.new("id", "sources", "ready", "ended", "failed", "frame", """
        const surfaces = (globalThis.__swiftuiwebSurfaces ||= new Map());
        let box = document.getElementById('swiftuiweb-videos');
        if (!box) {
          box = document.createElement('div'); box.id = 'swiftuiweb-videos';
          box.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;z-index:-1';
          document.body.appendChild(box);
        }
        const v = document.createElement('video');
        v.muted = true; v.playsInline = true; v.preload = 'auto'; v.setAttribute('playsinline', '');
        v.style.cssText = 'width:1px;height:1px';
        // Safari shows HEVC's alpha; elsewhere the VP9 WebM keeps it.
        const apple = /Apple/.test(navigator.vendor || '') && v.canPlayType('video/mp4; codecs="hvc1"') !== '';
        const ordered = apple || sources.length < 2 ? sources : [sources[1], sources[0]];
        v.src = ordered[0];
        let tried = 0;
        v.addEventListener('error', () => {
          if (++tried < ordered.length) { v.src = ordered[tried]; v.load(); } else failed();
        });
        let told = false;
        const tell = () => { if (!told && v.readyState >= 2) { told = true; ready(isFinite(v.duration) ? v.duration : 0); } };
        v.addEventListener('loadeddata', tell); v.addEventListener('canplay', tell);
        v.addEventListener('ended', () => ended());
        const onPicture = () => { frame(); if (v.requestVideoFrameCallback) v.requestVideoFrameCallback(onPicture); };
        if (v.requestVideoFrameCallback) v.requestVideoFrameCallback(onPicture);
        else v.addEventListener('timeupdate', () => frame());
        v.addEventListener('seeked', () => frame());
        box.appendChild(v);
        surfaces.set(id, v);
        return v;
        """)

    init?(sources: [String], ready: @escaping (Double) -> Void, ended: @escaping () -> Void, failed: @escaping () -> Void, frame: @escaping () -> Void) {
        guard !sources.isEmpty, let maker = Self.maker else { return nil }
        Self.next += 1
        surface = 1_000_000 + Self.next
        func closure(_ body: @escaping ([JSValue]) -> Void) -> JSClosure {
            JSClosure { arguments in MainActor.assumeIsolated { body(arguments) }; return .undefined }
        }
        let made = [closure { ready($0.first?.number ?? 0) }, closure { _ in ended() }, closure { _ in failed() }, closure { _ in frame() }]
        let id: JSValue = .number(Double(surface)), list: JSValue = sources.jsValue
        let callbacks: [JSValue] = made.map { .object($0) }
        guard let video = maker(id, list, callbacks[0], callbacks[1], callbacks[2], callbacks[3]).object else { return nil }
        self.video = video
        closures = made
    }

    var currentTime: Double { video.currentTime.number ?? 0 }
    func play(rate: Float) {
        video.playbackRate = .number(Double(rate))
        _ = video.play?()
    }
    func pause() { _ = video.pause?() }
    func seek(to seconds: Double) { video.currentTime = .number(seconds) }
    func setMuted(_ muted: Bool, volume: Float) {
        video.muted = .boolean(muted)
        video.volume = .number(Double(max(0, min(1, volume))))
    }
    func setLoops(_ loops: Bool) { video.loop = .boolean(loops) }
}
#endif
