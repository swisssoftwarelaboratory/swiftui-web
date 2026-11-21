// Camera capture as AVFoundation names it. A page reaches the camera only through
// `getUserMedia`, which this module does not drive yet, so in a plain page there is no capture
// device: `AVCaptureDevice.default(...)` is nil, authorization is denied, and a session runs
// nothing; an app's "no camera" path (a simulator's) is the one that runs. Inside the drawn
// iPhone (new-website#666) the phone has its cameras, as an iPhone does: asking for access shows
// iOS's alert with the app's `NSCameraUsageDescription` once, and the answer is kept between
// visits. What a running session sees is the demo account's (not drawn yet: nothing flows), and
// the viewer's own camera is never asked for.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The kind of media a device captures.
public struct AVMediaType: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
}

/// Whether the app may use a capture device.
public enum AVAuthorizationStatus: Int, Sendable {
    case notDetermined, restricted, denied, authorized
}

/// A camera or microphone (none on the web).
open class AVCaptureDevice: NSObject, @unchecked Sendable {
    public struct DeviceType: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let builtInWideAngleCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInWideAngleCamera")
        public static let builtInUltraWideCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
        public static let builtInTelephotoCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
        public static let builtInDualCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualCamera")
        public static let builtInTrueDepthCamera = DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTrueDepthCamera")
        public static let microphone = DeviceType(rawValue: "AVCaptureDeviceTypeMicrophone")
    }
    public enum Position: Int, Sendable { case unspecified, back, front }

    public let uniqueID: String
    public let localizedName: String
    public let position: Position
    init(uniqueID: String, localizedName: String, position: Position) {
        self.uniqueID = uniqueID
        self.localizedName = localizedName
        self.position = position
    }

    /// The default device of a type: none in a plain page; the drawn iPhone's cameras.
    open class func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? {
        mediaType == .video ? phoneCamera(.builtInWideAngleCamera, position: .back) : nil
    }
    open class func `default`(_ deviceType: DeviceType, for mediaType: AVMediaType?, position: Position) -> AVCaptureDevice? {
        guard mediaType == nil || mediaType == .video else { return nil }
        return phoneCamera(deviceType, position: position)
    }
    open class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        #if os(WASI)
        if mediaType == .video, _PhonePrompts.isPresent {
            switch _PhonePrompts.answer("camera") {
            case "allow": return .authorized
            case "deny": return .denied
            default: return .notDetermined
            }
        }
        #endif
        return .denied
    }
    open class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping @Sendable (Bool) -> Void) {
        #if os(WASI)
        if mediaType == .video, _PhonePrompts.isPresent {
            switch authorizationStatus(for: .video) {
            case .authorized: handler(true); return
            case .notDetermined: break
            default: handler(false); return
            }
            let german = _PhonePrompts.german
            let title = german ? "\(_PhonePrompts.quotedName) m\u{00F6}chte auf die Kamera zugreifen"
                : "\(_PhonePrompts.quotedName) Would Like to Access the Camera"
            _PhonePrompts.show(.alert(title: title, message: _PhonePrompts.usage("NSCameraUsageDescription"),
                                      buttons: [_PhonePrompts.dontAllow, _PhonePrompts.allow]), fallback: .button(0)) { answer in
                let allowed: Bool
                if case .button(1) = answer { allowed = true } else { allowed = false }
                _PhonePrompts.setAnswer("camera", allowed ? "allow" : "deny")
                handler(allowed)
            }
            return
        }
        #endif
        handler(false)
    }
    open class func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            requestAccess(for: mediaType) { continuation.resume(returning: $0) }
        }
    }

    /// The drawn iPhone's camera of `type` at `position` (the back's wide, ultra wide and
    /// telephoto, the front's wide and TrueDepth); nil in a plain page.
    private class func phoneCamera(_ type: DeviceType, position: Position) -> AVCaptureDevice? {
        #if os(WASI)
        guard _PhonePrompts.isPresent else { return nil }
        let front = position == .front
        switch type {
        case .builtInWideAngleCamera:
            return AVCaptureDevice(uniqueID: front ? "front-wide" : "back-wide", localizedName: front ? "Front Camera" : "Back Camera", position: front ? .front : .back)
        case .builtInTrueDepthCamera where position != .back:
            return AVCaptureDevice(uniqueID: "front-truedepth", localizedName: "Front TrueDepth Camera", position: .front)
        case .builtInUltraWideCamera where !front, .builtInTelephotoCamera where !front, .builtInDualCamera where !front:
            return AVCaptureDevice(uniqueID: "back-\(type.rawValue)", localizedName: "Back Camera", position: .back)
        default:
            return nil
        }
        #else
        return nil
        #endif
    }
}

/// Something a session takes media from or gives it to.
open class AVCaptureInput: NSObject, @unchecked Sendable {}
open class AVCaptureOutput: NSObject, @unchecked Sendable {}

/// A device as a session's input.
open class AVCaptureDeviceInput: AVCaptureInput, @unchecked Sendable {
    public let device: AVCaptureDevice
    public init(device: AVCaptureDevice) throws { self.device = device }
}

/// A capture session: holds inputs and outputs, and runs nothing on the web. Not `Sendable`,
/// as on iOS (an app's `nonisolated(unsafe) let session` must not draw a warning).
open class AVCaptureSession: NSObject {
    public struct Preset: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let photo = Preset(rawValue: "AVCaptureSessionPresetPhoto")
        public static let high = Preset(rawValue: "AVCaptureSessionPresetHigh")
        public static let medium = Preset(rawValue: "AVCaptureSessionPresetMedium")
        public static let low = Preset(rawValue: "AVCaptureSessionPresetLow")
        public static let inputPriority = Preset(rawValue: "AVCaptureSessionPresetInputPriority")
    }
    open var sessionPreset: Preset = .high
    open private(set) var inputs: [AVCaptureInput] = []
    open private(set) var outputs: [AVCaptureOutput] = []
    open private(set) var isRunning = false
    open private(set) var isInterrupted = false

    public override init() {}
    open func canAddInput(_ input: AVCaptureInput) -> Bool { true }
    open func addInput(_ input: AVCaptureInput) { inputs.append(input) }
    open func removeInput(_ input: AVCaptureInput) { inputs.removeAll { $0 === input } }
    open func canAddOutput(_ output: AVCaptureOutput) -> Bool { true }
    open func addOutput(_ output: AVCaptureOutput) { outputs.append(output) }
    open func removeOutput(_ output: AVCaptureOutput) { outputs.removeAll { $0 === output } }
    open func beginConfiguration() {}
    open func commitConfiguration() {}
    /// Starts the session: with no device on the web, nothing flows.
    open func startRunning() {}
    open func stopRunning() { isRunning = false }
}

/// Settings for one photo capture.
open class AVCapturePhotoSettings: NSObject, @unchecked Sendable {
    public override init() {}
    public init(format: [String: Any]?) {}
    open var flashMode: AVCaptureDevice.FlashMode = .off
}

extension AVCaptureDevice {
    public enum FlashMode: Int, Sendable { case off, on, auto }
}

/// A captured photo.
open class AVCapturePhoto: NSObject, @unchecked Sendable {
    open func fileDataRepresentation() -> Data? { nil }
}

/// Receives the results of a photo capture.
public protocol AVCapturePhotoCaptureDelegate: NSObjectProtocol {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?)
}

extension AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {}
}

/// Takes still photos (none without a device).
open class AVCapturePhotoOutput: AVCaptureOutput, @unchecked Sendable {
    public override init() {}
    /// Captures a photo: with no device on the web, the delegate hears an error and no photo.
    open func capturePhoto(with settings: AVCapturePhotoSettings, delegate: any AVCapturePhotoCaptureDelegate) {
        delegate.photoOutput(self, didFinishProcessingPhoto: AVCapturePhoto(), error: _NoCaptureDevice())
    }
}

/// The error a capture reports on the web: there is no capture device.
struct _NoCaptureDevice: Error {}
