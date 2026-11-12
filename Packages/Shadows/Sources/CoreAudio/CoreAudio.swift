// Apple's `CoreAudio` module for wasm: the CoreAudioTypes it re-exports (`AudioBufferList`,
// `UnsafeMutableAudioBufferListPointer`, `AudioTimeStamp`), which SwiftUIWeb's AudioToolbox
// declares, as Apple's AudioToolbox and AVFoundation re-export them too. No audio hardware API.
#if os(WASI)
@_exported import AudioToolbox
#endif
