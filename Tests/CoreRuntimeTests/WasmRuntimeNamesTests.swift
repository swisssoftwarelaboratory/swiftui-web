// The Objective-C runtime's names on the stock wasm SDK (WebFoundation, RuntimeNames.swift and
// Responder.swift), as Nuke, Kingfisher and RevenueCat call them.
#if os(WASI) && !_runtime(_ObjC)
import Testing
import WebFoundation

/// A top-level class, which `NSStringFromClass` names "Module.Class".
final class RuntimeNamesLookedUp {}

@Suite struct WasmRuntimeNamesTests {
    struct Failure: Error {}

    @Test func autoreleasepoolRunsItsBody() throws {
        #expect(autoreleasepool { 3 } == 3)
        let data: [UInt8]? = autoreleasepool(invoking: { [1, 2] })
        #expect(data == [1, 2])
        #expect(throws: Failure.self) { try autoreleasepool { () throws -> Int in throw Failure() } }
    }

    @Test func aClassIsFoundByTheNameItsStringGives() {
        let name = NSStringFromClass(RuntimeNamesLookedUp.self)
        #expect(name.hasSuffix(".RuntimeNamesLookedUp"))
        #expect(NSClassFromString(name) == RuntimeNamesLookedUp.self)
        // RevenueCat's lookup of a framework class that is not linked: nothing, so it goes without.
        #expect(NSClassFromString("ASIdentifierManager") == nil)
        #expect(NSClassFromString("") == nil)
    }

    @Test func theIntegerTypesAreSwiftsOwn() {
        let count: NSInteger = -2
        let size: NSUInteger = 4
        #expect(count + Int(size) == 2)
        #expect(NSIntegerMax == Int.max && NSUIntegerMax == UInt.max && NSIntegerMin == Int.min)
    }

    final class Delegate: NSObject {
        override func responds(to aSelector: Selector!) -> Bool { aSelector == Selector("refresh") }
    }

    @Test func anObjectAnswersNoSendUnlessItSaysSo() {
        let object = NSObject()
        #expect(!object.responds(to: Selector("description")))
        #expect(object.perform(Selector("description")) == nil)
        #expect(object.perform(Selector("setValue:"), with: 1) == nil)
        #expect(!NSObject.responds(to: Selector("new")))
        #expect(NSObject.perform(Selector("new")) == nil)
        #expect(Delegate().responds(to: Selector("refresh")))
        #expect(!Delegate().responds(to: Selector("reload")))
    }
}
#endif
