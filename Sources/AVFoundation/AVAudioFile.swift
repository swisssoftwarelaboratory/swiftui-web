// Audio files and render callbacks (AVFAudio, new-website#746). `AVAudioFile(forReading:)` reads
// a WAV file at once, as iOS reads a bundle's files: linear PCM (8, 16, 24 or 32-bit integers, or
// 32 or 64-bit floats), into float buffers at the file's rate and channel count. The build turns
// an app's Apple Lossless `.caf` into WAV under the same name (scripts/web-media.py), so the app's
// own URL opens it; any other file throws, as a file iOS can't read does. A source node's render
// block is pulled by `AVAudioEngine` while it runs, through the host's audio output.
#if os(WASI)
import WebFoundation
@_exported import AudioToolbox   // CoreAudioTypes, which Apple's AVFoundation re-exports

/// An audio file for reading: a WAV file's samples (see the file's note).
open class AVAudioFile {
    public let url: URL
    public let fileFormat: AVAudioFormat
    public let processingFormat: AVAudioFormat
    public private(set) var length: AVAudioFramePosition = 0
    open var framePosition: AVAudioFramePosition = 0
    /// Every channel's samples, as floats.
    private let samples: [[Float]]

    /// Opens a file to read: a WAV file of linear PCM; anything else throws.
    public init(forReading fileURL: URL) throws {
        guard let data = try? Data(contentsOf: fileURL), let wave = Self.wave(data) else {
            throw NSError(domain: "com.apple.coreaudio.avfaudio", code: 1_954_115_647,
                          userInfo: [NSLocalizedDescriptionKey: "The file is not an audio file this page can read."])
        }
        url = fileURL
        samples = wave.channels
        length = AVAudioFramePosition(wave.channels.first?.count ?? 0)
        fileFormat = AVAudioFormat(standardFormatWithSampleRate: wave.rate, channels: UInt32(wave.channels.count))
        processingFormat = fileFormat
    }

    public convenience init(forReading fileURL: URL, commonFormat format: AVAudioCommonFormat, interleaved: Bool) throws {
        try self.init(forReading: fileURL)
    }

    /// Reads from the file's position into the buffer, as many frames as fit.
    open func read(into buffer: AVAudioPCMBuffer) throws {
        try read(into: buffer, frameCount: buffer.frameCapacity)
    }

    open func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws {
        let start = Int(framePosition)
        let available = samples.first.map { $0.count - start } ?? 0
        let count = max(0, min(Int(frames), Int(buffer.frameCapacity), available))
        guard let out = buffer.floatChannelData, !samples.isEmpty else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            samples[min(channel, samples.count - 1)].withUnsafeBufferPointer { from in
                out[channel].update(from: from.baseAddress! + start, count: count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(count)
        framePosition += AVAudioFramePosition(count)
    }

    /// A RIFF WAVE file's rate and channels (linear PCM or IEEE float).
    static func wave(_ data: Data) -> (rate: Double, channels: [[Float]])? {
        let bytes = [UInt8](data)
        guard bytes.count > 44, Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WAVE".utf8) else { return nil }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var format = 0, channels = 0, rate = 0, bits = 0
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self), size = u32(offset + 4), body = offset + 8
            if id == "fmt " {
                format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                // WAVE_FORMAT_EXTENSIBLE names its real format in its sub-format.
                if format == 65534, size >= 26 { format = u16(body + 24) }
            } else if id == "data" {
                guard channels > 0, rate > 0, bits > 0, format == 1 || format == 3 else { return nil }
                let width = bits / 8, end = min(bytes.count, body + size), frames = (end - body) / (width * channels)
                var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channels)
                bytes.withUnsafeBytes { raw in
                    for frame in 0..<frames {
                        for channel in 0..<channels {
                            out[channel][frame] = Self.sample(raw, at: body + (frame * channels + channel) * width, format: format, bits: bits)
                        }
                    }
                }
                return (Double(rate), out)
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    private static func sample(_ raw: UnsafeRawBufferPointer, at i: Int, format: Int, bits: Int) -> Float {
        switch (format, bits) {
        case (1, 8): return (Float(raw[i]) - 128) / 128
        case (1, 16): return Float(raw.loadUnaligned(fromByteOffset: i, as: Int16.self)) / 32768
        case (1, 24):
            let packed = UInt32(raw[i]) << 8 | UInt32(raw[i + 1]) << 16 | UInt32(raw[i + 2]) << 24
            return Float(Int32(bitPattern: packed) >> 8) / 8_388_608
        case (1, 32): return Float(raw.loadUnaligned(fromByteOffset: i, as: Int32.self)) / 2_147_483_648
        case (3, 32): return raw.loadUnaligned(fromByteOffset: i, as: Float.self)
        case (3, 64): return Float(raw.loadUnaligned(fromByteOffset: i, as: Double.self))
        default: return 0
        }
    }
}

/// The block a source node renders through.
public typealias AVAudioSourceNodeRenderBlock = (UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>, AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>) -> OSStatus

/// A node that renders audio through a block, pulled by its engine while it runs.
public final class AVAudioSourceNode: AVAudioNode {
    package let renderBlock: AVAudioSourceNodeRenderBlock
    public init(renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        renderBlock = block
        super.init()
    }
    public init(format: AVAudioFormat, renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        renderBlock = block
        super.init()
        self.format = format
    }
}
#endif
