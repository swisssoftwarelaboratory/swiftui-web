// Camera capture as AVFoundation names it. A page reaches the camera only through
// `getUserMedia`, which this module does not drive yet, so there is no capture device:
// `AVCaptureDevice.default(...)` is nil, authorization is denied, and a session runs nothing.
// An app's "no camera" path (a simulator's) is the one that runs. Accepted for source
// compatibility.
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

    /// The default device of a type: none on the web.
    open class func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? { nil }
    open class func `default`(_ deviceType: DeviceType, for mediaType: AVMediaType?, position: Position) -> AVCaptureDevice? { nil }
    open class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { .denied }
    open class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping @Sendable (Bool) -> Void) { handler(false) }
    open class func requestAccess(for mediaType: AVMediaType) async -> Bool { false }
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
