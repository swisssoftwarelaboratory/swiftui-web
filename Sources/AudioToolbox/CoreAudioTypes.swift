// CoreAudioTypes, which Apple's AudioToolbox, CoreAudio and AVFoundation re-export: the buffer
// list a render block fills, its Swift collection view, and the time stamp it is handed. Plain
// memory layouts, as in C (`AudioBufferList` holds its first buffer inline; the others follow).
#if os(WASI)

/// One buffer of audio samples.
public struct AudioBuffer {
    public var mNumberChannels: UInt32
    public var mDataByteSize: UInt32
    public var mData: UnsafeMutableRawPointer?
    public init() { mNumberChannels = 0; mDataByteSize = 0; mData = nil }
    public init(mNumberChannels: UInt32, mDataByteSize: UInt32, mData: UnsafeMutableRawPointer?) {
        self.mNumberChannels = mNumberChannels
        self.mDataByteSize = mDataByteSize
        self.mData = mData
    }
}

extension AudioBuffer: @unchecked Sendable {}

/// A list of buffers: the count, then the buffers (the first inline, as C's flexible array).
public struct AudioBufferList {
    public var mNumberBuffers: UInt32
    public var mBuffers: AudioBuffer
    public init() { mNumberBuffers = 0; mBuffers = AudioBuffer() }
    public init(mNumberBuffers: UInt32, mBuffers: AudioBuffer) {
        self.mNumberBuffers = mNumberBuffers
        self.mBuffers = mBuffers
    }
    /// The bytes a list of `maximumBuffers` buffers takes.
    public static func sizeInBytes(maximumBuffers: Int) -> Int {
        MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride + maximumBuffers * MemoryLayout<AudioBuffer>.stride
    }
    /// A zeroed list with room for `maximumBuffers` buffers (the caller frees it).
    public static func allocate(maximumBuffers: Int) -> UnsafeMutableAudioBufferListPointer {
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeInBytes(maximumBuffers: maximumBuffers), alignment: MemoryLayout<AudioBufferList>.alignment)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: sizeInBytes(maximumBuffers: maximumBuffers))
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.pointee.mNumberBuffers = UInt32(maximumBuffers)
        return UnsafeMutableAudioBufferListPointer(list)
    }
}

/// The buffers of an `AudioBufferList` as a collection.
public struct UnsafeMutableAudioBufferListPointer: MutableCollection, RandomAccessCollection {
    public let unsafeMutablePointer: UnsafeMutablePointer<AudioBufferList>
    public var unsafePointer: UnsafePointer<AudioBufferList> { UnsafePointer(unsafeMutablePointer) }

    public init(_ p: UnsafeMutablePointer<AudioBufferList>) { unsafeMutablePointer = p }
    public init?(_ p: UnsafeMutablePointer<AudioBufferList>?) {
        guard let p else { return nil }
        unsafeMutablePointer = p
    }

    public var count: Int {
        get { Int(unsafeMutablePointer.pointee.mNumberBuffers) }
        nonmutating set { unsafeMutablePointer.pointee.mNumberBuffers = UInt32(newValue) }
    }
    private var buffers: UnsafeMutablePointer<AudioBuffer> {
        let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!
        return (UnsafeMutableRawPointer(unsafeMutablePointer) + offset).assumingMemoryBound(to: AudioBuffer.self)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    public subscript(index: Int) -> AudioBuffer {
        get { buffers[index] }
        nonmutating set { buffers[index] = newValue }
    }
}

/// A moment in an audio stream.
public struct AudioTimeStamp: Sendable {
    public var mSampleTime: Double = 0
    public var mHostTime: UInt64 = 0
    public var mRateScalar: Double = 1
    public var mWordClockTime: UInt64 = 0
    public var mFlags: UInt32 = 0
    public var mReserved: UInt32 = 0
    public init() {}
}
#endif
