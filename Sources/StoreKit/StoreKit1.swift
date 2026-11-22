// The original StoreKit API: product requests, the payment queue, the review prompt and Apple
// Music capabilities. On the web the store has no products and payments are not allowed, so a
// product request lists every identifier as invalid, a payment added to the queue fails, and a
// restore finishes with nothing restored. Callbacks run before the call that starts them
// returns (the App Store answers later on a device).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

// MARK: - Errors

/// An error from the App Store.
public struct SKError: Error, Hashable, @unchecked Sendable {
    public enum Code: Int, Hashable, Sendable {
        case unknown = 0
        case clientInvalid = 1
        case paymentCancelled = 2
        case paymentInvalid = 3
        case paymentNotAllowed = 4
        case storeProductNotAvailable = 5
        case cloudServicePermissionDenied = 6
        case cloudServiceNetworkConnectionFailed = 7
        case cloudServiceRevoked = 8
        case privacyAcknowledgementRequired = 9
        case unauthorizedRequestData = 10
        case invalidOfferIdentifier = 11
        case invalidSignature = 12
        case missingOfferParams = 13
        case invalidOfferPrice = 14
        case overlayCancelled = 15
        case overlayInvalidConfiguration = 16
        case overlayTimeout = 17
        case ineligibleForOffer = 18
        case unsupportedPlatform = 19
        case overlayPresentedInBackgroundScene = 20
    }

    public let code: Code
    /// What the store said about the error, as Foundation's `userInfo`.
    public let userInfo: [String: Any]
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
    }
    /// The error's code, as Foundation's `errorCode`.
    public var errorCode: Int { code.rawValue }
    public static var errorDomain: String { SKErrorDomain }

    public static func == (lhs: SKError, rhs: SKError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    public static var unknown: Code { .unknown }
    public static var clientInvalid: Code { .clientInvalid }
    public static var paymentCancelled: Code { .paymentCancelled }
    public static var paymentInvalid: Code { .paymentInvalid }
    public static var paymentNotAllowed: Code { .paymentNotAllowed }
    public static var storeProductNotAvailable: Code { .storeProductNotAvailable }
    public static var cloudServicePermissionDenied: Code { .cloudServicePermissionDenied }
    public static var cloudServiceNetworkConnectionFailed: Code { .cloudServiceNetworkConnectionFailed }
    public static var unsupportedPlatform: Code { .unsupportedPlatform }
}

/// The domain of App Store errors.
public let SKErrorDomain = "SKErrorDomain"

/// Matches an error against an App Store error code (`catch SKError.paymentCancelled`).
public func ~= (code: SKError.Code, error: any Error) -> Bool {
    (error as? SKError)?.code == code
}

// MARK: - Products

/// A product's subscription period in the original StoreKit API.
open class SKProductSubscriptionPeriod: NSObject {
    public let numberOfUnits: Int
    public let unit: SKProduct.PeriodUnit
    package init(numberOfUnits: Int, unit: SKProduct.PeriodUnit) {
        self.numberOfUnits = numberOfUnits
        self.unit = unit
        super.init()
    }
}

/// A product in the original StoreKit API.
open class SKProduct: NSObject {
    public enum PeriodUnit: UInt, Sendable {
        case day = 0, week, month, year
    }

    open private(set) var productIdentifier: String
    open private(set) var localizedTitle: String
    open private(set) var localizedDescription: String
    open private(set) var price: NSDecimalNumber
    open private(set) var priceLocale: Locale
    open private(set) var isDownloadable = false
    open private(set) var isFamilyShareable = false
    open private(set) var subscriptionPeriod: SKProductSubscriptionPeriod?
    open private(set) var subscriptionGroupIdentifier: String?
    /// The product's introductory offer, if it has one.
    open private(set) var introductoryPrice: SKProductDiscount?
    /// The product's promotional offers.
    open private(set) var discounts: [SKProductDiscount] = []

    /// A product with these details. The App Store makes products; on the web none load.
    package init(productIdentifier: String, localizedTitle: String, localizedDescription: String = "",
                 price: NSDecimalNumber, priceLocale: Locale) {
        self.productIdentifier = productIdentifier
        self.localizedTitle = localizedTitle
        self.localizedDescription = localizedDescription
        self.price = price
        self.priceLocale = priceLocale
        super.init()
    }
}

/// The App Store's answer to a products request.
open class SKProductsResponse: NSObject {
    /// The products the store offers: none on the web.
    open private(set) var products: [SKProduct]
    /// The identifiers the store doesn't recognize: all of them on the web.
    open private(set) var invalidProductIdentifiers: [String]

    package init(products: [SKProduct], invalidProductIdentifiers: [String]) {
        self.products = products
        self.invalidProductIdentifiers = invalidProductIdentifiers
        super.init()
    }
}

/// The callbacks of a request to the App Store.
public protocol SKRequestDelegate: AnyObject {
    func requestDidFinish(_ request: SKRequest)
    func request(_ request: SKRequest, didFailWithError error: any Error)
}

extension SKRequestDelegate {
    public func requestDidFinish(_ request: SKRequest) {}
    public func request(_ request: SKRequest, didFailWithError error: any Error) {}
}

/// The callback with a products request's answer.
public protocol SKProductsRequestDelegate: SKRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse)
}

/// A request to the App Store.
open class SKRequest: NSObject {
    /// Sends the request.
    open func start() {}
    /// Cancels the request.
    open func cancel() {}
}

/// A request for products by identifier. On the web the answer lists no products, and every
/// identifier as invalid.
open class SKProductsRequest: SKRequest {
    public let productIdentifiers: Set<String>
    open weak var delegate: (any SKProductsRequestDelegate)?
    private var cancelled = false

    public init(productIdentifiers: Set<String>) {
        self.productIdentifiers = productIdentifiers
        super.init()
    }

    open override func start() {
        guard !cancelled, let delegate else { return }
        let response = SKProductsResponse(products: [], invalidProductIdentifiers: productIdentifiers.sorted())
        delegate.productsRequest(self, didReceive: response)
        delegate.requestDidFinish(self)
    }

    open override func cancel() { cancelled = true }
}

// MARK: - Payments

/// A request to buy a product.
open class SKPayment: NSObject {
    package var storedProductIdentifier: String
    package var storedQuantity: Int
    package var storedApplicationUsername: String?
    package var storedPaymentDiscount: SKPaymentDiscount?
    package var storedSimulatesAskToBuyInSandbox = false

    open var productIdentifier: String { storedProductIdentifier }
    open var quantity: Int { storedQuantity }
    open var applicationUsername: String? { storedApplicationUsername }
    /// The signed promotional offer to apply to the purchase.
    open var paymentDiscount: SKPaymentDiscount? { storedPaymentDiscount }
    open var simulatesAskToBuyInSandbox: Bool { storedSimulatesAskToBuyInSandbox }

    public convenience init(product: SKProduct) {
        self.init(productIdentifier: product.productIdentifier, quantity: 1)
    }

    package init(productIdentifier: String, quantity: Int, applicationUsername: String? = nil) {
        self.storedProductIdentifier = productIdentifier
        self.storedQuantity = quantity
        self.storedApplicationUsername = applicationUsername
        super.init()
    }
}

/// A payment request the app can change before adding it to the queue.
open class SKMutablePayment: SKPayment {
    open override var productIdentifier: String {
        get { storedProductIdentifier }
        set { storedProductIdentifier = newValue }
    }
    open override var quantity: Int {
        get { storedQuantity }
        set { storedQuantity = newValue }
    }
    open override var applicationUsername: String? {
        get { storedApplicationUsername }
        set { storedApplicationUsername = newValue }
    }
    open override var paymentDiscount: SKPaymentDiscount? {
        get { storedPaymentDiscount }
        set { storedPaymentDiscount = newValue }
    }
    open override var simulatesAskToBuyInSandbox: Bool {
        get { storedSimulatesAskToBuyInSandbox }
        set { storedSimulatesAskToBuyInSandbox = newValue }
    }
}

/// The state of a payment transaction.
public enum SKPaymentTransactionState: Int, Sendable {
    case purchasing = 0
    case purchased = 1
    case failed = 2
    case restored = 3
    case deferred = 4
}

/// A payment in the queue.
open class SKPaymentTransaction: NSObject {
    open private(set) var payment: SKPayment
    open private(set) var transactionState: SKPaymentTransactionState
    open private(set) var transactionIdentifier: String?
    open private(set) var transactionDate: Date?
    open private(set) var error: (any Error)?
    open private(set) var original: SKPaymentTransaction?

    package init(payment: SKPayment, state: SKPaymentTransactionState, error: (any Error)?) {
        self.payment = payment
        self.transactionState = state
        self.error = error
        super.init()
    }
}

/// The callbacks of the payment queue.
public protocol SKPaymentTransactionObserver: AnyObject {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction])
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction])
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: any Error)
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue)
}

extension SKPaymentTransactionObserver {
    public func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {}
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: any Error) {}
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {}
    public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool { true }
    public func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {}
}

/// The queue of payments the App Store processes. On the web payments are not allowed: a
/// payment added fails with `SKError.paymentNotAllowed`.
open class SKPaymentQueue: NSObject {
    private struct WeakObserver { weak var observer: (any SKPaymentTransactionObserver)? }
    private var observerBoxes: [WeakObserver] = []

    nonisolated(unsafe) private static let shared = SKPaymentQueue()

    /// The app's payment queue.
    open class func `default`() -> SKPaymentQueue { shared }

    /// Whether the customer can make payments: never on the web.
    open class func canMakePayments() -> Bool { false }

    /// The transactions waiting in the queue.
    open private(set) var transactions: [SKPaymentTransaction] = []

    /// The object the queue asks before it continues a transaction.
    open weak var delegate: (any SKPaymentQueueDelegate)?

    /// The App Store storefront the queue uses: none on the web, where there is no store.
    open private(set) var storefront: SKStorefront?

    /// The observers registered with the queue.
    open var transactionObservers: [any SKPaymentTransactionObserver] { observerBoxes.compactMap(\.observer) }

    open func add(_ observer: any SKPaymentTransactionObserver) {
        observerBoxes.removeAll { $0.observer == nil || $0.observer === observer }
        observerBoxes.append(WeakObserver(observer: observer))
    }

    open func remove(_ observer: any SKPaymentTransactionObserver) {
        observerBoxes.removeAll { $0.observer == nil || $0.observer === observer }
    }

    /// Adds a payment. It fails at once: there is no store to pay on the web.
    open func add(_ payment: SKPayment) {
        let transaction = SKPaymentTransaction(payment: payment, state: .failed, error: SKError(.paymentNotAllowed))
        transactions.append(transaction)
        for observer in transactionObservers {
            observer.paymentQueue(self, updatedTransactions: [transaction])
        }
    }

    /// Removes a finished transaction from the queue.
    open func finishTransaction(_ transaction: SKPaymentTransaction) {
        guard let index = transactions.firstIndex(where: { $0 === transaction }) else { return }
        transactions.remove(at: index)
        for observer in transactionObservers {
            observer.paymentQueue(self, removedTransactions: [transaction])
        }
    }

    /// Restores the customer's purchases: there are none on the web, so the restore finishes
    /// with nothing restored.
    open func restoreCompletedTransactions() {
        for observer in transactionObservers {
            observer.paymentQueueRestoreCompletedTransactionsFinished(self)
        }
    }

    open func restoreCompletedTransactions(withApplicationUsername username: String?) {
        restoreCompletedTransactions()
    }

    /// Shows the App Store's offer code redemption (none on the web).
    open func presentCodeRedemptionSheet() {}
}

// MARK: - Review prompt

/// The App Store rating prompt. The web has none, so asking shows nothing.
open class SKStoreReviewController: NSObject {
    open class func requestReview() {}
    open class func requestReview(in windowScene: UIWindowScene) {}
}

// MARK: - Apple Music

/// What the customer's Apple Music account can do.
public struct SKCloudServiceCapability: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let musicCatalogPlayback = SKCloudServiceCapability(rawValue: 1 << 0)
    public static let musicCatalogSubscriptionEligible = SKCloudServiceCapability(rawValue: 1 << 1)
    public static let addToCloudMusicLibrary = SKCloudServiceCapability(rawValue: 1 << 8)
}

/// Whether the app may use the customer's Apple Music account.
public enum SKCloudServiceAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case restricted = 2
    case authorized = 3
}

/// The customer's Apple Music account. A web page can't reach one: there are no capabilities
/// and access is restricted.
open class SKCloudServiceController: NSObject {
    public override init() { super.init() }

    /// Inside the drawn iPhone (new-website#710) the app asks as iOS does, once; Allow gives an
    /// account with no subscription and nothing in its library.
    open class func authorizationStatus() -> SKCloudServiceAuthorizationStatus {
        #if os(WASI)
        if _PhonePrompts.isPresent {
            switch _PhonePrompts.allowed("appleMusic") {
            case true?: return .authorized
            case false?: return .denied
            case nil: return .notDetermined
            }
        }
        #endif
        return .restricted
    }

    open class func requestAuthorization(_ handler: @escaping (SKCloudServiceAuthorizationStatus) -> Void) {
        #if os(WASI)
        if _PhonePrompts.isPresent {
            nonisolated(unsafe) let handler = handler
            let title = _PhonePrompts.german
                ? "Darf \(_PhonePrompts.quotedName) auf deine Musik, deine Videoaktivit\u{00E4}ten und auf deine Mediathek in Apple Music zugreifen?"
                : "Allow \(_PhonePrompts.quotedName) to access your music, video activity, and media library in Apple Music?"
            _PhonePrompts.askAllow("appleMusic", title: title, usageKey: "NSAppleMusicUsageDescription") { handler($0 ? .authorized : .denied) }
            return
        }
        #endif
        handler(.restricted)
    }

    open func requestCapabilities(completionHandler: @escaping (SKCloudServiceCapability, (any Error)?) -> Void) {
        completionHandler([], nil)
    }

    open func requestStorefrontCountryCode(completionHandler: @escaping (String?, (any Error)?) -> Void) {
        completionHandler(nil, SKError(.cloudServiceNetworkConnectionFailed))
    }

    open func requestStorefrontIdentifier(completionHandler: @escaping (String?, (any Error)?) -> Void) {
        completionHandler(nil, SKError(.cloudServiceNetworkConnectionFailed))
    }

    open func requestUserToken(forDeveloperToken developerToken: String, completionHandler: @escaping (String?, (any Error)?) -> Void) {
        completionHandler(nil, SKError(.cloudServicePermissionDenied))
    }
}
