// Apple's `HealthKit` module for wasm. A page has no Health store, so
// `HKHealthStore.isHealthDataAvailable()` is false (as on an iPad without Health) and the
// store's requests do nothing; the type objects are values naming their identifiers, so an
// app's sets of types compile. Accepted for source compatibility: an app's "no Health" path runs.
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

/// The Health store: unavailable on the web.
open class HKHealthStore: NSObject, @unchecked Sendable {
    public override init() {}
    open class func isHealthDataAvailable() -> Bool { false }
    open func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .notDetermined }
    open func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        throw HKError(code: .errorHealthDataUnavailable)
    }
    open func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        completion(false, HKError(code: .errorHealthDataUnavailable))
    }
    open func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        .unknown
    }
}
#endif
