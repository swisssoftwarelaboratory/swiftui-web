// The browser's geolocation as CoreLocation's location manager reads it (pf-corelocation): the
// hook SwiftUIWebCanvas installs (GeolocationHost.swift) and CoreLocation uses. A module of its
// own, depending on nothing, so installing the hook links only this into an app that never
// makes a location manager (decision 0006).

// MARK: - The host

public enum _CoreLocationHost {
    /// A position as the browser reports it (`GeolocationPosition`).
    public struct Position: Sendable {
        public var latitude: Double
        public var longitude: Double
        /// Metres, the radius of 95% confidence.
        public var accuracy: Double
        public var altitude: Double?
        public var altitudeAccuracy: Double?
        /// Degrees clockwise from true north, when moving.
        public var heading: Double?
        /// Metres per second.
        public var speed: Double?
        /// Milliseconds since 1970.
        public var timestamp: Double
        public init(latitude: Double, longitude: Double, accuracy: Double, altitude: Double? = nil, altitudeAccuracy: Double? = nil,
                    heading: Double? = nil, speed: Double? = nil, timestamp: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.altitude = altitude
            self.altitudeAccuracy = altitudeAccuracy
            self.heading = heading
            self.speed = speed
            self.timestamp = timestamp
        }
    }

    /// `GeolocationPositionError`'s codes.
    public enum Failure: Int, Error, Sendable {
        case denied = 1
        case unavailable = 2
        case timeout = 3
    }

    public typealias Update = @MainActor @Sendable (Result<Position, Failure>) -> Void

    /// The Permissions API's state for geolocation as last read ("granted", "denied", "prompt"),
    /// when the host is in place; nil where the browser can't say.
    nonisolated(unsafe) public static var permission: (() -> String?)?
    /// One position (`getCurrentPosition`), which prompts for permission the first time.
    nonisolated(unsafe) public static var locate: ((_ highAccuracy: Bool, _ completion: @escaping Update) -> Void)?
    /// Positions as they change (`watchPosition`); the identifier stops them.
    nonisolated(unsafe) public static var watch: ((_ highAccuracy: Bool, _ update: @escaping Update) -> Int)?
    nonisolated(unsafe) public static var clearWatch: ((Int) -> Void)?

    /// The host calls this when the browser's permission is first read or changes.
    @MainActor public static func permissionDidChange() { _authorizationObserver?() }

    /// Set by CoreLocation's first location manager.
    nonisolated(unsafe) public static var _authorizationObserver: (@MainActor @Sendable () -> Void)?
}
