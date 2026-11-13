// Drag and drop interactions (uk-dragdrop, Docs/elements/DragDrop.md): a card with a
// `UIDragInteraction` carrying "Drag me", a well with a `UIDropInteraction` that turns green
// while a text drag is over it and shows what was dropped. Pixels at rest are compared; the
// drag itself is driven by `Playwright/uikit-dragdrop-probe.mjs` on the gallery.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// The object class a text drop loads: UIKit's providers read `NSString`, UIKitWeb's `String`.
#if canImport(UIKitWebCore)
typealias DragText = String
#else
typealias DragText = NSString
#endif

/// A provider carrying `text` (Foundation's takes an `NSString`, WebFoundation's stand-in a `String`).
func dragTextProvider(_ text: String) -> NSItemProvider {
    #if _runtime(_ObjC)
    return NSItemProvider(object: text as NSString)
    #else
    return NSItemProvider(object: text)
    #endif
}

@MainActor final class DragDropModel: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
    let well = UIView()
    let status = UILabel()

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
        [UIDragItem(itemProvider: dragTextProvider("Drag me"))]
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: DragText.self)
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) { well.backgroundColor = .systemGreen }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) { well.backgroundColor = .systemBlue }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) { well.backgroundColor = .systemBlue }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        _ = session.loadObjects(ofClass: DragText.self) { [weak self] objects in
            guard let self else { return }
            self.status.text = "Dropped: " + objects.map { "\($0)" }.joined(separator: ", ")
            self.status.sizeToFit()
        }
    }
}

public enum DragDropFixtures {
    public static let all = [basic]
    @MainActor static var models: [DragDropModel] = []

    /// A draggable card over a drop well, the status line under them.
    public static let basic = UIKitFixture("uikit/events/dragdrop", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        root.backgroundColor = .white
        let model = DragDropModel()
        models.append(model)
        let card = UILabel(frame: CGRect(x: 20, y: 20, width: 120, height: 60))
        card.text = "Drag me"
        card.textAlignment = .center
        card.textColor = .white
        card.backgroundColor = .systemIndigo
        card.layer.cornerRadius = 10
        card.layer.masksToBounds = true
        card.isUserInteractionEnabled = true
        card.addInteraction(UIDragInteraction(delegate: model))
        root.addSubview(card.probe("source"))
        model.well.frame = CGRect(x: 20, y: 120, width: 280, height: 120)
        model.well.backgroundColor = .systemBlue
        model.well.layer.cornerRadius = 12
        model.well.addInteraction(UIDropInteraction(delegate: model))
        root.addSubview(model.well.probe("target"))
        model.status.frame = CGRect(x: 20, y: 256, width: 280, height: 24)
        model.status.font = .systemFont(ofSize: 15)
        model.status.text = "Nothing dropped"
        model.status.sizeToFit()
        root.addSubview(model.status.probe("status"))
        return root
    }
}
#endif
