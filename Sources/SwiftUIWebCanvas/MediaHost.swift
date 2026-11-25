// The browser behind AVFoundation's audio (decision 0021, pf-avfoundation-audio): `AVAudioPlayer`
// plays through an `<audio>` element, `AVAudioEngine.inputNode` is `getUserMedia` through an
// `AudioContext` whose script processor hands mono float frames to the taps — the app's own
// buffers, as on a phone. The Speech framework's host is SpeechHost (decision 0022): it takes
// the buffers an app appends to its request, which on Scrumdinger's path are these.
#if os(WASI)
import JavaScriptKit
import AVFoundation

@MainActor
enum MediaHost {
    static func install() {
        _AVAudioHost.makePlayer = { url in AudioElementPlayback(url: _MemoryFiles._pageAddress(url)) }
        _AVAudioHost.requestRecordPermission = { completion in
            requestMicrophone { stream in
                if let stream { stopTracks(stream) }
                MainActor.assumeIsolated { completion(stream != nil) }
            }
        }
        _AVAudioHost.openMicrophone = { bufferSize, deliver, failed in MicrophoneCapture(bufferSize: bufferSize, deliver: deliver, failed: failed) }
        _AVAudioHost.openOutput = { channels, rate, render in SpeakerOutput(channels: channels, sampleRate: rate, render: render) }
    }

    /// `navigator.mediaDevices.getUserMedia({audio: true})`: the stream, or nil when refused or absent.
    nonisolated static func requestMicrophone(_ completion: @escaping (JSObject?) -> Void) {
        guard let devices = JSObject.global.navigator.mediaDevices.object, let getUserMedia = devices.getUserMedia.function else {
            completion(nil)
            return
        }
        let constraints = JSObject.global.Object.function!.new()
        constraints.audio = .boolean(true)
        guard let promise = getUserMedia(this: devices, constraints).object else { completion(nil); return }
        let resolved = JSClosure { (arguments: [JSValue]) -> JSValue in completion(arguments.first?.object); return .undefined }
        let rejected = JSClosure { (_: [JSValue]) -> JSValue in completion(nil); return .undefined }
        _ = promise.then!(resolved, rejected)
        retained.append(resolved)
        retained.append(rejected)
    }

    nonisolated static func stopTracks(_ stream: JSObject) {
        guard let tracks = stream.getTracks?().object, let count = tracks.length.number else { return }
        for index in 0..<Int(count) { _ = tracks[index].object?.stop?() }
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []
}

/// One sound: an `HTMLAudioElement` for the URL (the bundle's assets or a data URL).
final class AudioElementPlayback: _AVAudioPlayback {
    private let element: JSObject
    private var endedClosure: JSClosure?
    var onFinished: (@MainActor @Sendable () -> Void)? {
        didSet {
            guard endedClosure == nil else { return }
            nonisolated(unsafe) weak let playback = self
            let closure = JSClosure { (_: [JSValue]) -> JSValue in
                MainActor.assumeIsolated { playback?.onFinished?() }
                return .undefined
            }
            endedClosure = closure
            _ = element.addEventListener?("ended", closure)
        }
    }

    init?(url: String) {
        guard let audio = JSObject.global.Audio.function else { return nil }
        element = audio.new(url)
        element.preload = .string("auto")
    }

    func play() { _ = element.play?() }
    func pause() { _ = element.pause?() }
    func stop() {
        _ = element.pause?()
        element.currentTime = .number(0)
    }
    var currentTime: Double {
        get { element.currentTime.number ?? 0 }
        set { element.currentTime = .number(newValue) }
    }
    var duration: Double {
        let value = element.duration.number ?? 0
        return value.isFinite ? value : 0
    }
    var volume: Double {
        get { element.volume.number ?? 1 }
        set { element.volume = .number(max(0, min(1, newValue))) }
    }
    var rate: Double {
        get { element.playbackRate.number ?? 1 }
        set { element.playbackRate = .number(newValue) }
    }
    var loops: Int = 0 {
        didSet { element.loop = .boolean(loops != 0) }
    }
    var isPlaying: Bool { !(element.paused.boolean ?? true) }
}

/// The microphone: an `AudioContext`, the stream's source node and a `ScriptProcessorNode`
/// (supported everywhere, its deprecation notwithstanding) delivering each block's first
/// channel as float frames.
final class MicrophoneCapture: _AVAudioCapture {
    private var context: JSObject?
    private var source: JSObject?
    private var processor: JSObject?
    private var stream: JSObject?
    private var processClosure: JSClosure?
    private(set) var sampleRate: Double = 48_000
    private var stopped = false

    init?(bufferSize: Int, deliver: @escaping @MainActor ([Float], Double) -> Void, failed: @escaping @MainActor (String) -> Void) {
        nonisolated(unsafe) let deliver = deliver, failed = failed   // run on the main actor; Swift 5 mode (decision 0027)
        guard let contextConstructor = JSObject.global.AudioContext.function ?? JSObject.global.webkitAudioContext.function else { return nil }
        let context = contextConstructor.new()
        self.context = context
        sampleRate = context.sampleRate.number ?? 48_000
        // Script processors take powers of two from 256 to 16384.
        var size = 256
        while size < bufferSize && size < 16384 { size *= 2 }
        MediaHost.requestMicrophone { [weak self] stream in
            guard let self, !stopped else { if let stream { MediaHost.stopTracks(stream) }; return }
            guard let stream else {
                MainActor.assumeIsolated { failed("AVAudioEngine: the microphone was refused") }
                return
            }
            self.stream = stream
            guard let source = context.createMediaStreamSource?(stream).object, let processor = context.createScriptProcessor?(size, 1, 1).object else {
                MainActor.assumeIsolated { failed("AVAudioEngine: the browser has no audio input node") }
                return
            }
            self.source = source
            self.processor = processor
            let rate = self.sampleRate
            let closure = JSClosure { (arguments: [JSValue]) -> JSValue in
                guard let event = arguments.first?.object, let input = event.inputBuffer.object, let data = input.getChannelData?(0).object else { return .undefined }
                let samples = JSTypedArray<Float32>(unsafelyWrapping: data).withUnsafeBytes { Array($0) }
                MainActor.assumeIsolated { deliver(samples, rate) }
                return .undefined
            }
            processClosure = closure
            processor.onaudioprocess = .object(closure)
            _ = source.connect?(processor)
            _ = processor.connect?(context.destination)
            _ = context.resume?()
        }
    }

    func stop() {
        stopped = true
        _ = processor?.disconnect?()
        _ = source?.disconnect?()
        if let stream { MediaHost.stopTracks(stream) }
        _ = context?.close?()
        processor = nil
        source = nil
        stream = nil
        context = nil
    }
}

/// The speakers behind `AVAudioEngine`'s source nodes (new-website#746): an `AudioContext` at the
/// sound's rate whose script processor asks the engine for each block, about 21 ms of sound at a
/// time on the main thread, where the app's render block reads what its views set (a turning
/// coin's speed). Started from the press that made the sound, as browsers want.
final class SpeakerOutput: _AVAudioCapture {
    private var context: JSObject?
    private var processor: JSObject?
    private var processClosure: JSClosure?
    let sampleRate: Double

    init?(channels: Int, sampleRate: Double, render: @escaping @MainActor @Sendable (Int) -> [[Float]]) {
        let pull = render
        guard let contextConstructor = JSObject.global.AudioContext.function ?? JSObject.global.webkitAudioContext.function else { return nil }
        let options = JSObject.global.Object.function!.new()
        options.sampleRate = .number(sampleRate)
        options.latencyHint = .string("interactive")
        let context = contextConstructor.new(options)
        guard let processor = context.createScriptProcessor?(1024, 0, channels).object else { return nil }
        self.context = context
        self.processor = processor
        self.sampleRate = context.sampleRate.number ?? sampleRate
        let closure = JSClosure { (arguments: [JSValue]) -> JSValue in
            guard let event = arguments.first?.object, let out = event.outputBuffer.object else { return .undefined }
            let length = Int(out.length.number ?? 0)
            let blocks = MainActor.assumeIsolated { pull(length) }
            for (channel, samples) in blocks.enumerated() where channel < Int(out.numberOfChannels.number ?? 0) {
                guard let data = out.getChannelData?(channel).object else { continue }
                samples.withUnsafeBufferPointer { _ = data.set?(JSTypedArray<Float32>(buffer: $0)) }
            }
            return .undefined
        }
        processClosure = closure
        processor.onaudioprocess = .object(closure)
        _ = processor.connect?(context.destination)
        _ = context.resume?()
    }

    func stop() {
        _ = processor?.disconnect?()
        _ = context?.close?()
        processor = nil
        context = nil
    }
}

extension String {
    /// Without leading and trailing spaces (the Regex engine and `CharacterSet` stay out of the bundle).
    fileprivate var _trimmed: String {
        var scalars = Substring(self)
        while scalars.first == " " { scalars = scalars.dropFirst() }
        while scalars.last == " " { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
#endif
