// Selectors sent with as many arguments as their methods take: key commands, display links and
// notification observers name methods with the sender (`newGame(_:)`) or without (`refresh`).
// On the Objective-C runtime's wasm build a send with the wrong count traps (wasm checks every
// indirect call's signature); here the count each method received is checked.
#if _runtime(_ObjC)
import Testing
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@MainActor final class ArityTarget: UIViewController {
    var calls: [String] = []
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    required init?(coder: NSCoder) { nil }
    init() { super.init(nibName: nil, bundle: nil) }

    @objc func refresh() { calls.append("refresh") }
    @objc func newGame(_ sender: Any?) { calls.append("newGame \(sender is UIKeyCommand ? "command" : sender == nil ? "nil" : "other")") }
    @objc func tick(_ link: CADisplayLink) { calls.append("tick") }
    @objc func act(_ sender: Any?, forEvent event: Any?) { calls.append("act \(event == nil ? "nil" : "event")") }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(refresh)),
         UIKeyCommand(input: "n", modifierFlags: .command, action: #selector(newGame(_:)))]
    }
}

@Suite @MainActor struct SelectorArityTests {
    @Test func sendPassesTheArgumentsTheMethodTakes() {
        let target = ArityTarget()
        target._send(#selector(ArityTarget.refresh), passing: "ignored")
        target._send(#selector(ArityTarget.newGame(_:)), passing: nil)
        target._send(#selector(ArityTarget.act(_:forEvent:)), passing: target)
        #expect(target.calls == ["refresh", "newGame nil", "act nil"])
    }

    @Test func keyCommandsWithAndWithoutTheSender() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let target = ArityTarget()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = target
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(scene.keyDown(KeyEvent(key: KeyEquivalent("r"), characters: "r", modifiers: .command)))
        #expect(scene.keyDown(KeyEvent(key: KeyEquivalent("n"), characters: "n", modifiers: .command)))
        #expect(target.calls == ["refresh", "newGame command"])
        scene.removeAllWindows()
    }

    @Test func displayLinkSendsItselfToAOneArgumentSelector() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        let target = ArityTarget()
        let link = CADisplayLink(target: target, selector: #selector(ArityTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        _ = scene.advanceFrame(elapsed: 1.0 / 60)
        #expect(target.calls == ["tick"])
        link.invalidate()
    }
}
#endif
