// Sends by selector on a responder without the Objective-C runtime (UIResponder.swift): none
// is answered, so Kingfisher's lookup of the shared application by selector, which checks
// `responds(to:)` first, finds nothing, as in an app extension. With the runtime the real
// NSObject answers (decision 0023).
#if !_runtime(_ObjC)
import Testing
import UIKit
@testable import UIKitWebCore

/// Kingfisher's wrapper (Cache/ImageCache.swift), reached from a nonisolated context as there.
private struct Wrapper<Base> {}
extension Wrapper where Base: UIApplication {
    static var shared: UIApplication? {
        let selector = Selector("sharedApplication")
        guard Base.responds(to: selector) else { return nil }
        guard let unmanaged = Base.perform(selector) else { return nil }
        return unmanaged.takeUnretainedValue() as? UIApplication
    }
}

@MainActor private final class Answering: UIResponder {
    nonisolated override func responds(to aSelector: Selector!) -> Bool { aSelector == Selector("refresh") }
}

@Suite @MainActor struct SelectorSendTests {
    @Test func theApplicationLookupBySelectorFindsNothing() {
        #expect(Wrapper<UIApplication>.shared == nil)
        #expect(!UIApplication.responds(to: Selector("sharedApplication")))
        #expect(!UIApplication.instancesRespond(to: Selector("sharedApplication")))
    }

    @Test func aResponderAnswersNoSendUnlessItSaysSo() {
        let view = UIView()
        #expect(!view.responds(to: Selector("layoutSubviews")))
        #expect(view.perform(Selector("layoutSubviews")) == nil)
        #expect(view.perform(Selector("setTag:"), with: 3) == nil)
        #expect(Answering().responds(to: Selector("refresh")))
        #expect(!Answering().responds(to: Selector("other")))
    }
}
#endif
