// The location manager over the browser's geolocation (pf-corelocation), through a host hook
// (`_CoreLocationHost`, installed by SwiftUIWebCanvas: `navigator.geolocation` for positions,
// the Permissions API for the browser's answer). Authorization is the browser's permission:
// asking for it is the browser's prompt, a granted permission is "when in use" (a page has no
// "always"), a refusal is denied. Location updates, the one-shot request, significant changes
// and circular regions all ride on the browser's positions. A page has no compass, beacons,
// visits or deferred updates: those report unavailable, as on a device without the hardware.
// Without a host (tests, a runtime with no geolocation) location services are off: a request
// for authorization answers denied and an update fails with `CLError.denied`. The hook itself
// is in CoreLocationHost, a module of its own, so the canvas can install it without linking
// this module into every app (decision 0006: a module's class metadata keeps all of it).
@_exported import CoreLocationHost

extension _CoreLocationHost.Position {
    var location: CLLocation {
        let course = heading.flatMap { $0.isNaN ? nil : $0 }
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude ?? 0,
                          horizontalAccuracy: accuracy, verticalAccuracy: altitude == nil ? -1 : altitudeAccuracy ?? -1,
                          course: course ?? -1, courseAccuracy: -1, speed: speed.flatMap { $0.isNaN ? nil : $0 } ?? -1, speedAccuracy: -1,
                          timestamp: Date(timeIntervalSince1970: timestamp / 1000))
    }
}

// MARK: - The delegate

/// The manager's callbacks, each with an empty default (they are optional on Apple platforms).
public protocol CLLocationManagerDelegate: NSObjectProtocol {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading)
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint)
    func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: any Error)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion)
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error)
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion)
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager)
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: (any Error)?)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit)
}

extension CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {}
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {}
    public func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: any Error) {}
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {}
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {}
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {}
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {}
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: (any Error)?) {}
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {}
}

// MARK: - The manager

/// A weak reference that crosses into the main actor's callbacks.
final class _WeakManager: @unchecked Sendable {
    weak var value: CLLocationManager?
    init(_ value: CLLocationManager) { self.value = value }
}

/// Starts and stops the delivery of location events to its delegate. Callbacks arrive on the
/// main actor, after the call that caused them returns, as Apple's arrive on the run loop.
open class CLLocationManager: NSObject {
    /// Setting a delegate reports the current authorization to it, as on Apple platforms.
    open weak var delegate: (any CLLocationManagerDelegate)? {
        didSet { if delegate != nil { scheduleAuthorizationReport() } }
    }

    open var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    open var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    open var activityType: CLActivityType = .other
    open var allowsBackgroundLocationUpdates = false
    open var pausesLocationUpdatesAutomatically = true
    open var showsBackgroundLocationIndicator = false
    open var headingFilter: CLLocationDegrees = 1
    open var headingOrientation: CLDeviceOrientation = .portrait

    /// The most recent position the browser reported, to any manager.
    open var location: CLLocation? { Self.lastLocation }
    open var heading: CLHeading? { nil }
    open var authorizationStatus: CLAuthorizationStatus { Self.status }
    /// The browser gives a page its full accuracy once it is allowed.
    open var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
    open var isAuthorizedForWidgetUpdates: Bool { false }
    open var monitoredRegions: Set<CLRegion> { Set(regions.map(\.region)) }
    open var rangedBeaconConstraints: Set<CLBeaconIdentityConstraint> { [] }
    open var maximumRegionMonitoringDistance: CLLocationDistance { _CoreLocationHost.watch == nil ? -1 : 1_000_000 }

    public override init() {
        super.init()
        Self.managers.removeAll { $0.value == nil }
        Self.managers.append(box)
        if _CoreLocationHost._authorizationObserver == nil {
            _CoreLocationHost._authorizationObserver = { CLLocationManager.authorizationMayHaveChanged() }
        }
    }

    deinit {
        if let id = watchID { _CoreLocationHost.clearWatch?(id) }
    }

    // MARK: Availability

    open class func locationServicesEnabled() -> Bool { _CoreLocationHost.locate != nil }
    open class func authorizationStatus() -> CLAuthorizationStatus { status }
    open class func headingAvailable() -> Bool { false }
    open class func significantLocationChangeMonitoringAvailable() -> Bool { _CoreLocationHost.watch != nil }
    open class func isMonitoringAvailable(for regionClass: AnyClass) -> Bool {
        _CoreLocationHost.watch != nil && regionClass is CLCircularRegion.Type
    }
    open class func isRangingAvailable() -> Bool { false }
    open class func deferredLocationUpdatesAvailable() -> Bool { false }

    // MARK: Authorization

    open func requestWhenInUseAuthorization() { requestAuthorization() }
    /// A page has no "always": the browser's one permission answers both requests.
    open func requestAlwaysAuthorization() { requestAuthorization() }

    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String, completion: (((any Error)?) -> Void)? = nil) {
        completion?(nil)
    }
    open func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) async throws {}

    private func requestAuthorization() {
        guard Self.status == .notDetermined else { return }
        guard let locate = _CoreLocationHost.locate else {
            Self.answer = .denied
            Task { @MainActor in CLLocationManager.authorizationMayHaveChanged() }
            return
        }
        locate(false) { result in
            _ = CLLocationManager.settle(result)
            CLLocationManager.authorizationMayHaveChanged()
        }
    }

    // MARK: Locations

    open func requestLocation() {
        guard let locate = _CoreLocationHost.locate else { later { $0.fail(.denied) }; return }
        let box = self.box
        locate(highAccuracy) { result in
            let location = CLLocationManager.settle(result)
            CLLocationManager.authorizationMayHaveChanged()
            guard let manager = box.value else { return }
            switch result {
            case .success: if let location { manager.delegate?.locationManager(manager, didUpdateLocations: [location]) }
            case .failure(let failure): manager.fail(failure)
            }
        }
    }

    open func startUpdatingLocation() {
        updating = true
        lastDelivered = nil
        startWatching()
    }

    open func stopUpdatingLocation() {
        updating = false
        stopWatchingIfIdle()
    }

    /// Positions at least 500 metres apart, from the same browser positions.
    open func startMonitoringSignificantLocationChanges() {
        significant = true
        lastSignificant = nil
        startWatching()
    }

    open func stopMonitoringSignificantLocationChanges() {
        significant = false
        stopWatchingIfIdle()
    }

    // MARK: Regions

    open func startMonitoring(for region: CLRegion) {
        guard region is CLCircularRegion, _CoreLocationHost.watch != nil else {
            later { $0.delegate?.locationManager($0, monitoringDidFailFor: region, withError: CLError(.regionMonitoringFailure)) }
            return
        }
        regions.removeAll { $0.region.identifier == region.identifier }
        regions.append(Monitored(region: region))
        later { $0.delegate?.locationManager($0, didStartMonitoringFor: region) }
        startWatching()
    }

    open func stopMonitoring(for region: CLRegion) {
        regions.removeAll { $0.region.identifier == region.identifier }
        stopWatchingIfIdle()
    }

    /// The region's state now: reported at once when known, or when the next position decides it.
    open func requestState(for region: CLRegion) {
        if let index = regions.firstIndex(where: { $0.region.identifier == region.identifier }) {
            let state = regions[index].state
            if state != .unknown { later { $0.delegate?.locationManager($0, didDetermineState: state, for: region) } }
            return
        }
        var state = CLRegionState.unknown
        if let circle = region as? CLCircularRegion, let location = Self.lastLocation {
            state = circle.contains(location.coordinate) ? .inside : .outside
        }
        let settled = state
        later { $0.delegate?.locationManager($0, didDetermineState: settled, for: region) }
    }

    // MARK: What a page has no hardware for

    open func startUpdatingHeading() {}
    open func stopUpdatingHeading() {}
    open func dismissHeadingCalibrationDisplay() {}
    open func startMonitoringVisits() {}
    open func stopMonitoringVisits() {}

    open func startRangingBeacons(satisfying constraint: CLBeaconIdentityConstraint) {
        later { $0.delegate?.locationManager($0, didFailRangingFor: constraint, error: CLError(.rangingUnavailable)) }
    }
    open func stopRangingBeacons(satisfying constraint: CLBeaconIdentityConstraint) {}
    @available(*, deprecated, renamed: "startRangingBeacons(satisfying:)")
    open func startRangingBeacons(in region: CLBeaconRegion) { startRangingBeacons(satisfying: region.beaconIdentityConstraint) }
    @available(*, deprecated, renamed: "stopRangingBeacons(satisfying:)")
    open func stopRangingBeacons(in region: CLBeaconRegion) {}

    open func allowDeferredLocationUpdates(untilTraveled distance: CLLocationDistance, timeout: TimeInterval) {
        later { $0.delegate?.locationManager($0, didFinishDeferredUpdatesWithError: CLError(.deferredFailed)) }
    }
    open func disallowDeferredLocationUpdates() {}

    // MARK: State shared by every manager

    /// The answer a request got, for a browser whose permission can't be read.
    nonisolated(unsafe) static var answer = CLAuthorizationStatus.notDetermined
    nonisolated(unsafe) static var lastLocation: CLLocation?
    nonisolated(unsafe) static var managers: [_WeakManager] = []

    /// The browser's permission when it has decided, otherwise the last request's answer.
    static var status: CLAuthorizationStatus {
        switch _CoreLocationHost.permission?() {
        case "granted": .authorizedWhenInUse
        case "denied": .denied
        default: answer
        }
    }

    /// Records what a position or failure says about authorization; the location, if one came.
    static func settle(_ result: Result<_CoreLocationHost.Position, _CoreLocationHost.Failure>) -> CLLocation? {
        switch result {
        case .success(let position):
            answer = .authorizedWhenInUse
            let location = position.location
            lastLocation = location
            return location
        case .failure(.denied):
            answer = .denied
            return nil
        case .failure:
            // Not a refusal: the prompt, if any, was answered yes.
            if answer == .notDetermined { answer = .authorizedWhenInUse }
            return nil
        }
    }

    /// Forgets the shared answer, location and managers (tests start each case from here).
    package static func _resetForTesting() {
        answer = .notDetermined
        lastLocation = nil
        managers.removeAll()
    }

    /// Tells each manager whose authorization changed.
    static func authorizationMayHaveChanged() {
        managers.removeAll { $0.value == nil }
        for box in managers { box.value?.reportAuthorization(force: false) }
    }

    // MARK: Per manager

    struct Monitored {
        let region: CLRegion
        var state = CLRegionState.unknown
    }

    private lazy var box = _WeakManager(self)
    private var reportedStatus: CLAuthorizationStatus?
    private var reportPending = false
    private var updating = false
    private var significant = false
    private var watchID: Int?
    private var regions: [Monitored] = []
    private var lastDelivered: CLLocation?
    private var lastSignificant: CLLocation?

    private var highAccuracy: Bool { desiredAccuracy < kCLLocationAccuracyHundredMeters }
    private var needsWatch: Bool { updating || significant || !regions.isEmpty }

    /// Runs `body` on the main actor after the current call returns, if the manager is alive.
    private func later(_ body: @escaping @MainActor @Sendable (CLLocationManager) -> Void) {
        let box = self.box
        Task { @MainActor in if let manager = box.value { body(manager) } }
    }

    private func scheduleAuthorizationReport() {
        guard !reportPending else { return }
        reportPending = true
        later { manager in
            manager.reportPending = false
            manager.reportAuthorization(force: true)
        }
    }

    private func reportAuthorization(force: Bool) {
        let status = Self.status
        guard force || status != reportedStatus else { return }
        reportedStatus = status
        delegate?.locationManagerDidChangeAuthorization(self)
        delegate?.locationManager(self, didChangeAuthorization: status)
    }

    private func fail(_ failure: _CoreLocationHost.Failure) {
        delegate?.locationManager(self, didFailWithError: CLError(failure == .denied ? .denied : .locationUnknown))
    }

    private func startWatching() {
        guard watchID == nil, needsWatch else { return }
        guard let watch = _CoreLocationHost.watch else {
            if updating || significant { later { $0.fail(.denied) } }
            return
        }
        let box = self.box
        watchID = watch(highAccuracy) { result in
            let location = CLLocationManager.settle(result)
            CLLocationManager.authorizationMayHaveChanged()
            box.value?.receive(result, location)
        }
    }

    private func stopWatchingIfIdle() {
        guard !needsWatch, let id = watchID else { return }
        watchID = nil
        _CoreLocationHost.clearWatch?(id)
    }

    private func receive(_ result: Result<_CoreLocationHost.Position, _CoreLocationHost.Failure>, _ location: CLLocation?) {
        guard let location else {
            guard case .failure(let failure) = result else { return }
            if failure == .denied, let id = watchID {
                // The browser sends nothing more once refused.
                watchID = nil
                _CoreLocationHost.clearWatch?(id)
            }
            if updating || significant { fail(failure) }
            if failure == .denied {
                for monitored in regions {
                    delegate?.locationManager(self, monitoringDidFailFor: monitored.region, withError: CLError(.regionMonitoringDenied))
                }
            }
            return
        }
        var deliver = false
        if updating, distanceFilter <= 0 || lastDelivered.map({ location.distance(from: $0) >= distanceFilter }) ?? true {
            lastDelivered = location
            deliver = true
        }
        if significant, lastSignificant.map({ location.distance(from: $0) >= 500 }) ?? true {
            lastSignificant = location
            deliver = true
        }
        if deliver { delegate?.locationManager(self, didUpdateLocations: [location]) }
        // A callback may stop or start monitoring regions, so each region is looked up again by
        // its identifier rather than by an index taken before the first callback, and a region
        // stopped meanwhile hears nothing more.
        for identifier in regions.map(\.region.identifier) {
            guard let index = monitoredIndex(identifier), let circle = regions[index].region as? CLCircularRegion else { continue }
            let state: CLRegionState = circle.contains(location.coordinate) ? .inside : .outside
            let previous = regions[index].state
            guard previous != state else { continue }
            regions[index].state = state
            if previous != .unknown {
                if state == .inside, circle.notifyOnEntry { delegate?.locationManager(self, didEnterRegion: circle) }
                if state == .outside, circle.notifyOnExit { delegate?.locationManager(self, didExitRegion: circle) }
            }
            guard let still = monitoredIndex(identifier), regions[still].region === circle else { continue }
            delegate?.locationManager(self, didDetermineState: state, for: circle)
        }
    }

    private func monitoredIndex(_ identifier: String) -> Int? {
        regions.firstIndex { $0.region.identifier == identifier }
    }
}

// MARK: - Live updates (iOS 17)

/// One event of `CLLocationUpdate.liveUpdates()`: a location, or why there is none.
public struct CLLocationUpdate: Sendable {
    public let location: CLLocation?
    public let isStationary: Bool
    public var stationary: Bool { isStationary }
    public let authorizationDenied: Bool
    public let authorizationDeniedGlobally: Bool
    public var authorizationRestricted: Bool { false }
    public var insufficientlyInUse: Bool { false }
    public let locationUnavailable: Bool
    public var accuracyLimited: Bool { false }
    public var serviceSessionRequired: Bool { false }
    public var authorizationRequestInProgress: Bool { false }

    init(location: CLLocation? = nil, denied: Bool = false, deniedGlobally: Bool = false, unavailable: Bool = false) {
        self.location = location
        isStationary = false
        authorizationDenied = denied
        authorizationDeniedGlobally = deniedGlobally
        locationUnavailable = unavailable
    }

    public struct LiveConfiguration: Sendable {
        let highAccuracy: Bool
        public static let `default` = LiveConfiguration(highAccuracy: true)
        public static let automotiveNavigation = LiveConfiguration(highAccuracy: true)
        public static let otherNavigation = LiveConfiguration(highAccuracy: true)
        public static let fitness = LiveConfiguration(highAccuracy: true)
        public static let airborne = LiveConfiguration(highAccuracy: true)
    }

    /// The browser's positions as they change, for as long as the sequence is iterated.
    public struct Updates: AsyncSequence, Sendable {
        public typealias Element = CLLocationUpdate
        let configuration: LiveConfiguration

        public struct Iterator: AsyncIteratorProtocol {
            var base: AsyncStream<CLLocationUpdate>.Iterator
            public mutating func next() async throws -> CLLocationUpdate? { await base.next() }
        }

        public func makeAsyncIterator() -> Iterator {
            let highAccuracy = configuration.highAccuracy
            let stream = AsyncStream<CLLocationUpdate> { continuation in
                guard let watch = _CoreLocationHost.watch else {
                    continuation.yield(CLLocationUpdate(denied: true, deniedGlobally: true))
                    return
                }
                let id = watch(highAccuracy) { result in
                    let location = CLLocationManager.settle(result)
                    CLLocationManager.authorizationMayHaveChanged()
                    switch result {
                    case .success: continuation.yield(CLLocationUpdate(location: location))
                    case .failure(.denied): continuation.yield(CLLocationUpdate(denied: true))
                    case .failure: continuation.yield(CLLocationUpdate(unavailable: true))
                    }
                }
                continuation.onTermination = { _ in _CoreLocationHost.clearWatch?(id) }
            }
            return Iterator(base: stream.makeAsyncIterator())
        }
    }

    public static func liveUpdates(_ configuration: LiveConfiguration = .default) -> Updates { Updates(configuration: configuration) }
}
