// Apple's `HealthKit` module for wasm. A plain page has no Health store, so
// `HKHealthStore.isHealthDataAvailable()` is false (as on an iPad without Health) and the
// store's requests do nothing; the type objects are values naming their identifiers, so an
// app's sets of types compile. Accepted for source compatibility: an app's "no Health" path runs.
//
// Inside the drawn iPhone (new-website#666) Health is there, as on an iPhone: a request shows
// Apple Health's access sheet for the types not answered before (one switch each, the app's
// `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`), the answers are kept
// between visits, `statusForAuthorizationRequest` says whether a request would ask, and
// `authorizationStatus(for:)` reports sharing as iOS does (reading stays private to the app).
// What Health holds is the demo account's (no readings yet).
#if os(WASI)
import WebFoundation

public struct HKQuantityTypeIdentifier: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let stepCount = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierStepCount")
    public static let heartRate = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierHeartRate")
    public static let restingHeartRate = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierRestingHeartRate")
    public static let heartRateVariabilitySDNN = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
    public static let bodyMass = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierBodyMass")
    public static let bodyFatPercentage = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierBodyFatPercentage")
    public static let leanBodyMass = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierLeanBodyMass")
    public static let height = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierHeight")
    public static let activeEnergyBurned = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierActiveEnergyBurned")
    public static let basalEnergyBurned = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierBasalEnergyBurned")
    public static let distanceWalkingRunning = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierDistanceWalkingRunning")
    public static let dietaryEnergyConsumed = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierDietaryEnergyConsumed")
    public static let dietaryProtein = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierDietaryProtein")
    public static let vo2Max = HKQuantityTypeIdentifier("HKQuantityTypeIdentifierVO2Max")
}

public struct HKCategoryTypeIdentifier: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let sleepAnalysis = HKCategoryTypeIdentifier("HKCategoryTypeIdentifierSleepAnalysis")
    public static let mindfulSession = HKCategoryTypeIdentifier("HKCategoryTypeIdentifierMindfulSession")
}

/// A kind of Health data, named by its identifier.
open class HKObjectType: NSObject, @unchecked Sendable {
    public let identifier: String
    init(identifier: String) { self.identifier = identifier }
    open override func isEqual(_ object: Any?) -> Bool { (object as? HKObjectType)?.identifier == identifier }
    open override var hash: Int { identifier.hashValue }
    open override var description: String { identifier }

    open class func quantityType(forIdentifier identifier: HKQuantityTypeIdentifier) -> HKQuantityType? { HKQuantityType(identifier) }
    open class func categoryType(forIdentifier identifier: HKCategoryTypeIdentifier) -> HKCategoryType? { HKCategoryType(identifier) }
    open class func workoutType() -> HKWorkoutType { HKWorkoutType(identifier: "HKWorkoutTypeIdentifier") }
}

open class HKSampleType: HKObjectType, @unchecked Sendable {}
open class HKWorkoutType: HKSampleType, @unchecked Sendable {}
open class HKQuantityType: HKSampleType, @unchecked Sendable {
    public convenience init(_ identifier: HKQuantityTypeIdentifier) { self.init(identifier: identifier.rawValue) }
}
open class HKCategoryType: HKSampleType, @unchecked Sendable {
    public convenience init(_ identifier: HKCategoryTypeIdentifier) { self.init(identifier: identifier.rawValue) }
}

public enum HKAuthorizationStatus: Int, Sendable { case notDetermined = 0, sharingDenied, sharingAuthorized }
public enum HKAuthorizationRequestStatus: Int, Sendable { case unknown = 0, shouldRequest, unnecessary }

public struct HKError: Error, Sendable {
    public enum Code: Int, Sendable { case errorHealthDataUnavailable = 1, errorAuthorizationDenied = 5 }
    public let code: Code
}

/// The Health store: unavailable in a plain page; the drawn iPhone's Health.
open class HKHealthStore: NSObject, @unchecked Sendable {
    public override init() {}
    open class func isHealthDataAvailable() -> Bool { _PhonePrompts.isPresent }

    /// Sharing as the person answered it for `type`.
    open func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        guard _PhonePrompts.isPresent else { return .notDetermined }
        switch _PhonePrompts.answer(Self.key("share", type)) {
        case "on": return .sharingAuthorized
        case "off": return .sharingDenied
        default: return _PhonePrompts.answer(Self.key("read", type)) == nil ? .notDetermined : .sharingDenied
        }
    }

    open func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        guard _PhonePrompts.isPresent else { throw HKError(code: .errorHealthDataUnavailable) }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            ask(share: Array(typesToShare), read: Array(typesToRead)) { done.resume() }
        }
    }

    open func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        guard _PhonePrompts.isPresent else { completion(false, HKError(code: .errorHealthDataUnavailable)); return }
        ask(share: Array(typesToShare ?? []), read: Array(typesToRead ?? [])) { completion(true, nil) }
    }

    /// Whether a request for these types would show the sheet: `.shouldRequest` while one of
    /// them was never answered.
    open func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        guard _PhonePrompts.isPresent else { return .unknown }
        let unanswered = typesToShare.contains { _PhonePrompts.answer(Self.key("share", $0)) == nil }
            || typesToRead.contains { _PhonePrompts.answer(Self.key("read", $0)) == nil }
        return unanswered ? .shouldRequest : .unnecessary
    }

    // MARK: The drawn iPhone's Health (new-website#666)

    private static func key(_ kind: String, _ type: HKObjectType) -> String { "health.\(kind).\(type.identifier)" }

    /// Shows the sheet for the types not answered yet (none: done at once), keeps each answer.
    private func ask(share: [HKObjectType], read: [HKObjectType], done: @escaping @Sendable () -> Void) {
        let newShare = share.filter { _PhonePrompts.answer(Self.key("share", $0)) == nil }
        let newRead = read.filter { _PhonePrompts.answer(Self.key("read", $0)) == nil }
        guard !newShare.isEmpty || !newRead.isEmpty else { done(); return }
        let shareNames = Dictionary(newShare.map { (Self.name($0), $0) }, uniquingKeysWith: { first, _ in first })
        let readNames = Dictionary(newRead.map { (Self.name($0), $0) }, uniquingKeysWith: { first, _ in first })
        let types = (shareNames, readNames)
        _PhonePrompts.show(.health(share: Array(shareNames.keys), read: Array(readNames.keys),
                                   shareExplanation: _PhonePrompts.usage("NSHealthUpdateUsageDescription"),
                                   readExplanation: _PhonePrompts.usage("NSHealthShareUsageDescription")),
                           fallback: .health(allowed: nil)) { answer in
            var allowed: Set<String> = []
            if case let .health(on?) = answer { allowed = on }
            for (name, type) in types.0 { _PhonePrompts.setAnswer(Self.key("share", type), allowed.contains("share:" + name) ? "on" : "off") }
            for (name, type) in types.1 { _PhonePrompts.setAnswer(Self.key("read", type), allowed.contains("read:" + name) ? "on" : "off") }
            done()
        }
    }

    /// A type's name as the Health app shows it.
    private static func name(_ type: HKObjectType) -> String {
        let german = _PhonePrompts.german
        let names: [String: (String, String)] = [
            "HKQuantityTypeIdentifierStepCount": ("Steps", "Schritte"),
            "HKQuantityTypeIdentifierHeartRate": ("Heart Rate", "Herzfrequenz"),
            "HKQuantityTypeIdentifierRestingHeartRate": ("Resting Heart Rate", "Ruhepuls"),
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": ("Heart Rate Variability", "Herzfrequenzvariabilit\u{00E4}t"),
            "HKQuantityTypeIdentifierBodyMass": ("Weight", "Gewicht"),
            "HKQuantityTypeIdentifierBodyFatPercentage": ("Body Fat Percentage", "K\u{00F6}rperfettanteil"),
            "HKQuantityTypeIdentifierLeanBodyMass": ("Lean Body Mass", "Fettfreie K\u{00F6}rpermasse"),
            "HKQuantityTypeIdentifierHeight": ("Height", "Gr\u{00F6}\u{00DF}e"),
            "HKQuantityTypeIdentifierActiveEnergyBurned": ("Active Energy", "Aktive Energie"),
            "HKQuantityTypeIdentifierBasalEnergyBurned": ("Resting Energy", "Ruheenergie"),
            "HKQuantityTypeIdentifierDistanceWalkingRunning": ("Walking + Running Distance", "Gehen + Laufen (Distanz)"),
            "HKQuantityTypeIdentifierDietaryEnergyConsumed": ("Dietary Energy", "Nahrungsenergie"),
            "HKQuantityTypeIdentifierDietaryProtein": ("Protein", "Eiwei\u{00DF}"),
            "HKQuantityTypeIdentifierVO2Max": ("Cardio Fitness", "Cardiofitness"),
            "HKCategoryTypeIdentifierSleepAnalysis": ("Sleep", "Schlaf"),
            "HKCategoryTypeIdentifierMindfulSession": ("Mindful Minutes", "Achtsamkeitsminuten"),
            "HKWorkoutTypeIdentifier": ("Workouts", "Trainings"),
        ]
        // Swiss German writes ss for \u{00DF}, as iOS does in de_CH.
        let swiss = Locale.current.regionCode == "CH"
        if let name = names[type.identifier] { return german ? (swiss ? name.1.replacingOccurrences(of: "\u{00DF}", with: "ss") : name.1) : name.0 }
        var raw = type.identifier
        for prefix in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier"] where raw.hasPrefix(prefix) { raw.removeFirst(prefix.count) }
        return raw
    }
}
#endif
