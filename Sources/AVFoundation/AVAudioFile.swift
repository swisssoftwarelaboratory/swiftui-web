// Audio files and render callbacks (AVFAudio). Neither runs on the web yet: reading a file
// needs the browser's asynchronous decoder, which a synchronous `AVAudioFile(forReading:)`
// cannot wait for, so opening one throws; a source node's render block is never called, as
// the engine renders no output graph. Accepted for source compatibility: an app's "no sound"
// path runs.
#if os(WASI)
import WebFoundation
@_exported import AudioToolbox   // CoreAudioTypes, which Apple's AVFoundation re-exports

/// An audio file for reading or writing (not readable on the web; see the file's note).
open class AVAudioFile {
    public let url: URL
    public let fileFormat: AVAudioFormat
    public let processingFormat: AVAudioFormat
    public private(set) var length: AVAudioFramePosition = 0
    open var framePosition: AVAudioFramePosition = 0

    /// Opens a file to read: throws on the web, where no file can be decoded synchronously.
    public init(forReading fileURL: URL) throws {
        throw NSError(domain: "com.apple.coreaudio.avfaudio", code: 2003334207,
                      userInfo: [NSLocalizedDescriptionKey: "Audio files cannot be read on the web."])
    }

    public convenience init(forReading fileURL: URL, commonFormat format: AVAudioCommonFormat, interleaved: Bool) throws {
        try self.init(forReading: fileURL)
    }

    open func read(into buffer: AVAudioPCMBuffer) throws {}
    open func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws {}
}

/// The block a source node renders through.
public typealias AVAudioSourceNodeRenderBlock = (UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>, AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>) -> OSStatus

/// A node that renders audio through a block (never called on the web; see the file's note).
public final class AVAudioSourceNode: AVAudioNode {
    private let renderBlock: AVAudioSourceNodeRenderBlock
    public init(renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        renderBlock = block
        super.init()
    }
    public init(format: AVAudioFormat, renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        renderBlock = block
        super.init()
    }
}
#endif
