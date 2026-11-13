// Apple's Speech framework for the web (decisions 0021 and 0022, pf-speech): `SFSpeechRecognizer`
// over the browser's on-device `SpeechRecognition`, fed the buffers the app appends to its
// `SFSpeechAudioBufferRecognitionRequest` — the host (`_SpeechHost`) plays them through an
// AudioWorklet into a MediaStreamTrack the recogniser listens to, so what is transcribed is
// exactly what the app's audio tap delivered, and nothing leaves the device. Partial results
// are cumulative, as Apple's are; the one final result comes when the audio ends.
// Written against Scrumdinger's SpeechService.
@_exported import WebFoundation   // as Apple's Speech re-exports Foundation
import AVFoundation

// MARK: - The host

/// What a host provides: whether on-device recognition exists for a locale (installing its
/// language pack when asked to), and a session recognising the buffers it is given.
public enum _SpeechHost {
    /// Asks whether `locale` (a BCP 47 tag) can be recognised on the device; with `install`,
    /// the host may download the locale's pack first (the one user-visible step, from the
    /// browser's vendor). The answer arrives when known.
    nonisolated(unsafe) public static var availability: ((_ locale: String, _ install: Bool, _ completion: @escaping @MainActor @Sendable (_SpeechAvailability) -> Void) -> Void)?
    /// Starts a session recognising `locale` with interim results when `partial`; `result`
    /// gets the transcript so far and whether it is the final one, `failed` an error; the
    /// returned session takes the audio.
    nonisolated(unsafe) public static var start: ((_ locale: String, _ partial: Bool, _ result: @escaping @MainActor @Sendable (String, Bool) -> Void,
                                                  _ failed: @escaping @MainActor @Sendable (String) -> Void) -> (any _SpeechSession)?)?
    /// The authorisation the host remembers.
    nonisolated(unsafe) public static var authorization: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    /// What the host last answered per locale: `isAvailable` is synchronous, so it reads this.
    nonisolated(unsafe) public static var known: [String: _SpeechAvailability] = [:]

    /// Resets to no host.
    public static func _reset() {
        availability = nil
        start = nil
        authorization = .notDetermined
        known = [:]
    }

    static func ask(_ locale: String, install: Bool, _ completion: @escaping @MainActor (_SpeechAvailability) -> Void) {
        nonisolated(unsafe) let completion = completion   // runs on the main actor; Swift 5 mode (decision 0027)
        guard let availability else { MainActor.assumeIsolated { completion(.unavailable) }; return }
        availability(locale, install) { answer in
            known[locale] = answer
            completion(answer)
        }
    }
}

public enum _SpeechAvailability: Sendable, Equatable {
    /// The locale is recognised on the device now.
    case available
    /// A language pack would have to be downloaded first.
    case downloadable
    /// The browser has no on-device recognition for the locale (or none at all).
    case unavailable
}

/// One recognition: the audio goes in as float frames at their sample rate; `endAudio` lets
/// what was appended finish and then ends with the final result; `stop` finishes with what
/// has been recognised so far; `cancel` ends with no further results.
public protocol _SpeechSession: AnyObject {
    func append(_ samples: [Float], sampleRate: Double)
    func endAudio()
    func stop()
    func cancel()
}

// MARK: - Authorization and hints

public enum SFSpeechRecognizerAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case restricted = 2
    case authorized = 3
}

public enum SFSpeechRecognitionTaskHint: Int, Sendable {
    case unspecified = 0
    case dictation = 1
    case search = 2
    case confirmation = 3
}

public enum SFSpeechRecognitionTaskState: Int, Sendable {
    case starting = 0
    case running = 1
    case finishing = 2
    case canceling = 3
    case completed = 4
}

public struct SFSpeechError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public var errorDescription: String? { description }
    public init(_ description: String) { self.description = description }
}

// MARK: - Recognizer

/// An object you use to check for the availability of the speech recognition service, and to
/// initiate the speech recognition process.
public class SFSpeechRecognizer {
    public let locale: Locale
    public weak var delegate: (any SFSpeechRecognizerDelegate)?
    public var defaultTaskHint: SFSpeechRecognitionTaskHint = .unspecified
    /// Recognition here is on the device or not at all.
    public var supportsOnDeviceRecognition: Bool { _SpeechHost.availability != nil }
    public var queue: DispatchQueue = .main

    /// The recognizer for the current locale.
    public convenience init?() { self.init(locale: Locale.current) }

    /// A recognizer for the locale (Apple's is nil only for an unsupported locale; whether the
    /// device recognises it is `isAvailable`, asked of the host when it is in place — an app's
    /// scene can make its recognizer before the host installs).
    public init?(locale: Locale) {
        self.locale = locale
    }

    /// The locale as the browser names it (a BCP 47 tag).
    var tag: String { Self.tag(for: locale) }

    static func tag(for locale: Locale) -> String {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        // "en" alone is no on-device pack; the browser's packs are regioned.
        if identifier == "en" { return "en-US" }
        return identifier
    }

    /// Whether the recognizer is available to process speech right now: the host's last
    /// answer for the locale. Unknown yet, the host is asked (without installing anything) and
    /// the answer is false until it arrives — `requestAuthorization` waits for one.
    public var isAvailable: Bool {
        if let known = _SpeechHost.known[tag] { return known == .available }
        guard _SpeechHost.availability != nil else { return false }
        nonisolated(unsafe) weak let recognizer = self
        _SpeechHost.ask(tag, install: false) { answer in
            guard let recognizer else { return }
            recognizer.delegate?.speechRecognizer(recognizer, availabilityDidChange: answer == .available)
        }
        return false
    }

    /// The locales the host can recognise: the device's packs are asked for one at a time, so
    /// the current locale stands for them.
    public static func supportedLocales() -> Set<Locale> { [Locale.current] }

    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { _SpeechHost.authorization }

    /// Asks the user to allow speech recognition. The browser's one prompt is the language
    /// pack's download (when the locale's pack is not on the device yet), so this is where it
    /// is installed; the answer is `.authorized` once the current locale can be recognised on
    /// the device and `.restricted` where it cannot.
    public static func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        nonisolated(unsafe) let handler = handler
        guard _SpeechHost.availability != nil else {
            _SpeechHost.authorization = .restricted
            handler(.restricted)
            return
        }
        _SpeechHost.ask(tag(for: Locale.current), install: true) { answer in
            let status: SFSpeechRecognizerAuthorizationStatus = answer == .available ? .authorized : .restricted
            _SpeechHost.authorization = status
            handler(status)
        }
    }

    /// Executes the speech recognition request and delivers the results to the handler.
    @discardableResult
    public func recognitionTask(with request: SFSpeechRecognitionRequest, resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void) -> SFSpeechRecognitionTask {
        let task = SFSpeechRecognitionTask(request: request)
        nonisolated(unsafe) let resultHandler = resultHandler
        task.start(locale: tag, partial: request.shouldReportPartialResults,
                   onResult: { resultHandler($0, nil) }, onError: { resultHandler(nil, $0) })
        return task
    }

    @discardableResult
    public func recognitionTask(with request: SFSpeechRecognitionRequest, delegate: any SFSpeechRecognitionTaskDelegate) -> SFSpeechRecognitionTask {
        let task = SFSpeechRecognitionTask(request: request)
        task.delegate = delegate
        nonisolated(unsafe) let delegate = delegate
        nonisolated(unsafe) let held = task
        task.start(locale: tag, partial: request.shouldReportPartialResults, onResult: { result in
            if result.isFinal {
                delegate.speechRecognitionTask(held, didFinishRecognition: result)
                delegate.speechRecognitionTask(held, didFinishSuccessfully: true)
            } else {
                delegate.speechRecognitionTask(held, didHypothesizeTranscription: result.bestTranscription)
            }
        }, onError: { _ in delegate.speechRecognitionTask(held, didFinishSuccessfully: false) })
        return task
    }
}

public protocol SFSpeechRecognizerDelegate: AnyObject {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool)
}

public protocol SFSpeechRecognitionTaskDelegate: AnyObject {
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult)
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool)
}

extension SFSpeechRecognitionTaskDelegate {
    public func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {}
    public func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {}
}

// MARK: - Requests

/// An abstract class that represents a request to recognize speech from an audio source.
public class SFSpeechRecognitionRequest {
    public var taskHint: SFSpeechRecognitionTaskHint = .unspecified
    public var shouldReportPartialResults = true
    public var contextualStrings: [String] = []
    public var interactionIdentifier: String?
    public var requiresOnDeviceRecognition = false
    public var addsPunctuation = false
    public var customizedLanguageModel: Any?
    package init() {}
}

/// A request to recognize speech from captured audio content, such as audio from the device's
/// microphone. The appended buffers are what the recogniser hears: they go to the task's
/// session as they come, and the ones appended before a task takes the request wait for it.
public final class SFSpeechAudioBufferRecognitionRequest: SFSpeechRecognitionRequest {
    public private(set) var appendedFrames: Int = 0
    public private(set) var audioEnded = false
    public var nativeAudioFormat: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) }
    public override init() { super.init() }

    /// Appends audio from a PCM buffer: its first channel, at the buffer's sample rate.
    public func append(_ audioPCMBuffer: AVAudioPCMBuffer) {
        appendedFrames += Int(audioPCMBuffer.frameLength)
        guard !audioEnded else { return }
        let samples = audioPCMBuffer._samples(channel: 0)
        let rate = audioPCMBuffer.format.sampleRate
        if let session { session.append(samples, sampleRate: rate) } else { pending.append((samples, rate)) }
    }

    /// Marks the end of audio input: the recogniser finishes with what was appended.
    public func endAudio() {
        guard !audioEnded else { return }
        audioEnded = true
        if let session { session.endAudio() } else { pending.removeAll() }
    }

    /// The session taking the audio, set when a task starts: what was appended before goes first.
    var session: (any _SpeechSession)? {
        didSet {
            guard let session else { return }
            for (samples, rate) in pending { session.append(samples, sampleRate: rate) }
            pending.removeAll()
            if audioEnded { session.endAudio() }
        }
    }
    private var pending: [([Float], Double)] = []
}

/// A request to recognize speech in a recorded audio file. The host recognises buffers only;
/// a file would first be decoded into them (not done): the task fails.
public final class SFSpeechURLRecognitionRequest: SFSpeechRecognitionRequest {
    public let url: URL
    public init(url: URL) {
        self.url = url
        super.init()
    }
}

// MARK: - Results

/// A textual representation of the specified speech in its entirety, as recognized by the
/// speech recognizer.
public final class SFTranscription {
    public let formattedString: String
    public let segments: [SFTranscriptionSegment]
    package init(_ string: String) {
        formattedString = string
        var offset = 0
        segments = string.split(separator: " ", omittingEmptySubsequences: true).map { word in
            let segment = SFTranscriptionSegment(substring: String(word), substringRange: NSRange(location: offset, length: word.count))
            offset += word.count + 1
            return segment
        }
    }
    public var speakingRate: Double { 0 }
    public var averagePauseDuration: TimeInterval { 0 }
}

/// A discrete part of an entire transcription.
public final class SFTranscriptionSegment {
    public let substring: String
    public let substringRange: NSRange
    public let timestamp: TimeInterval = 0
    public let duration: TimeInterval = 0
    public let confidence: Float = 1
    public let alternativeSubstrings: [String] = []
    init(substring: String, substringRange: NSRange) {
        self.substring = substring
        self.substringRange = substringRange
    }
}

/// An object that contains the partial or final results of a speech recognition request.
public final class SFSpeechRecognitionResult {
    public let bestTranscription: SFTranscription
    public let transcriptions: [SFTranscription]
    public let isFinal: Bool
    public var speechRecognitionMetadata: Any? { nil }
    package init(_ string: String, isFinal: Bool) {
        bestTranscription = SFTranscription(string)
        transcriptions = [bestTranscription]
        self.isFinal = isFinal
    }
}

// MARK: - Task

/// A task object for monitoring the speech recognition progress.
public final class SFSpeechRecognitionTask {
    public private(set) var state: SFSpeechRecognitionTaskState = .starting
    public private(set) var isCancelled = false
    public private(set) var isFinishing = false
    public private(set) var error: Error?
    public weak var delegate: (any SFSpeechRecognitionTaskDelegate)?
    private let request: SFSpeechRecognitionRequest
    private var session: (any _SpeechSession)?

    package init(request: SFSpeechRecognitionRequest) { self.request = request }

    func start(locale: String, partial: Bool, onResult: @escaping (SFSpeechRecognitionResult) -> Void, onError: @escaping (Error) -> Void) {
        nonisolated(unsafe) let onResult = onResult
        nonisolated(unsafe) let onError = onError
        nonisolated(unsafe) let task = self
        if request is SFSpeechURLRecognitionRequest {
            fail(SFSpeechError("Speech: the host recognises appended buffers, not a file"), onError)
            return
        }
        guard let start = _SpeechHost.start else {
            fail(SFSpeechError("Speech: no speech host"), onError)
            return
        }
        session = start(locale, partial, { transcript, isFinal in
            guard !task.isCancelled, task.state != .completed else { return }
            if isFinal {
                task.state = .completed
                task.delegate?.speechRecognitionTaskFinishedReadingAudio(task)
            } else {
                task.state = .running
                if !partial { return }
            }
            onResult(SFSpeechRecognitionResult(transcript, isFinal: isFinal))
        }, { message in
            task.fail(SFSpeechError(message), onError)
        })
        guard let session else {
            fail(SFSpeechError("Speech: recognition could not start"), onError)
            return
        }
        if state == .starting { state = .running }
        (request as? SFSpeechAudioBufferRecognitionRequest)?.session = session
    }

    private func fail(_ error: Error, _ onError: (Error) -> Void) {
        guard !isCancelled, state != .completed else { return }
        self.error = error
        state = .completed
        onError(error)
    }

    /// Cancels the current speech recognition task: no more results.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        state = .canceling
        session?.cancel()
        session = nil
        delegate?.speechRecognitionTaskWasCancelled(self)
        state = .completed
    }

    /// Stops accepting new audio and finishes processing on the audio input that has already
    /// been accepted.
    public func finish() {
        guard !isCancelled, !isFinishing else { return }
        isFinishing = true
        state = .finishing
        session?.stop()
    }
}
