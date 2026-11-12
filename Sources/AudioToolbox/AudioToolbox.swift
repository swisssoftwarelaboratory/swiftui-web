// AudioToolbox on the web: system sounds. A page has no system sound set and no vibration motor,
// so playing a system sound (an alert, a tick, the vibrate ID) is silent; a completion runs as
// soon as the sound would have finished. Apps call these for feedback beside what they show, so
// nothing an app draws depends on them.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc   // libm, which Apple's Foundation re-exports through Darwin
#endif

/// The identifier of a system sound.
public typealias SystemSoundID = UInt32

/// The system sound that vibrates the device.
public let kSystemSoundID_Vibrate: SystemSoundID = 4095

/// Plays a system sound (silent here).
public func AudioServicesPlaySystemSound(_ inSystemSoundID: SystemSoundID) {}

/// Plays a system sound as an alert (silent here).
public func AudioServicesPlayAlertSound(_ inSystemSoundID: SystemSoundID) {}

/// Plays a system sound and calls `inCompletionBlock` when it has played.
public func AudioServicesPlaySystemSoundWithCompletion(_ inSystemSoundID: SystemSoundID, _ inCompletionBlock: (@Sendable () -> Void)?) {
    inCompletionBlock?()
}

/// Plays a system sound as an alert and calls `inCompletionBlock` when it has played.
public func AudioServicesPlayAlertSoundWithCompletion(_ inSystemSoundID: SystemSoundID, _ inCompletionBlock: (@Sendable () -> Void)?) {
    inCompletionBlock?()
}
