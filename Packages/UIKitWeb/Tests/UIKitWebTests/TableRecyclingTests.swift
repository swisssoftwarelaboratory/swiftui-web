// UITableView recycling (Containers/UITableView.swift): with a known row height only the rows in
// view (and a page around them) have cells; scrolling brings others in and returns the rest to
// the reuse pool, which dequeueReusableCell hands back.
import Testing
import UIKit

@Suite @MainActor struct TableRecyclingTests {
    final class Source: NSObject, UITableViewDataSource {
        var made = 0
        var dequeued = 0
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1000 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell: UITableViewCell
            if let reused = tableView.dequeueReusableCell(withIdentifier: "row") {
                cell = reused
                dequeued += 1
            } else {
                cell = UITableViewCell(style: .default, reuseIdentifier: "row")
                made += 1
            }
            cell.textLabel?.text = "Row \(indexPath.row)"
            return cell
        }
    }

    @Test func onlyTheRowsInViewHaveCells() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        let source = Source()
        table.dataSource = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(table.contentSize.height == 44_000)
        #expect(table.visibleCells.count < 30, "\(table.visibleCells.count)")
        #expect(source.made < 30)
        #expect(abs(table.rectForRow(at: IndexPath(row: 999, section: 0)).minY - 43956) < 0.001)
        // Scrolling far down shows those rows, made from recycled cells.
        table.contentOffset = CGPoint(x: 0, y: 500 * 44)
        scene.layout(in: CGSize(width: 320, height: 400))
        let paths = table.indexPathsForVisibleRows ?? []
        #expect(paths.contains(IndexPath(row: 502, section: 0)))
        #expect(!paths.contains(IndexPath(row: 0, section: 0)))
        #expect(source.dequeued > 0)
        #expect(source.made < 40, "\(source.made)")
        #expect(table.cellForRow(at: IndexPath(row: 502, section: 0))?.textLabel?.text == "Row 502")
    }
}

/// Registered cell classes are made through their own `init(style:reuseIdentifier:)`.
@Suite @MainActor struct RegisteredCellTests {
    /// Overrides the style initializer and has a stored property of its own.
    final class Badged: UITableViewCell {
        var badge = "new"
        var madeWith: String?
        #if _runtime(_ObjC)
        override init(style: CellStyle, reuseIdentifier: String?) {
            madeWith = reuseIdentifier
            super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        }
        #else
        required init(style: CellStyle, reuseIdentifier: String?) {
            madeWith = reuseIdentifier
            super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        }
        #endif
        required init?(coder: NSCoder) { nil }
    }

    #if _runtime(_ObjC)
    /// Only an initializer of its own, as SwiftyFORM's cells have: it compiles because the
    /// style initializer is not required, as in UIKit.
    final class OwnInitializer: UITableViewCell {
        let value: Int
        init(value: Int) {
            self.value = value
            super.init(style: .value1, reuseIdentifier: nil)
        }
        required init?(coder: NSCoder) { nil }
    }
    #endif

    @Test func registeredSubclassRunsItsOwnInitializer() throws {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), style: .plain)
        table.register(Badged.self, forCellReuseIdentifier: "badged")
        let cell = try #require(table.dequeueReusableCell(withIdentifier: "badged") as? Badged)
        #expect(cell.madeWith == "badged")
        #expect(cell.badge == "new")
        #expect(cell.style == .subtitle)
        #expect(cell.reuseIdentifier == "badged")
        #expect(cell.detailTextLabel != nil)
        // The plain class still registers and dequeues.
        table.register(UITableViewCell.self, forCellReuseIdentifier: "plain")
        let plain = try #require(table.dequeueReusableCell(withIdentifier: "plain"))
        #expect(type(of: plain) == UITableViewCell.self && plain.style == .default && plain.reuseIdentifier == "plain")
        #if _runtime(_ObjC)
        let own = OwnInitializer(value: 3)
        #expect(own.value == 3 && own.style == .value1)
        #endif
    }
}

/// Collection view headers and footers: laid out from the reference sizes, dequeued and pooled.
@Suite @MainActor struct CollectionSupplementaryTests {
    final class Source: NSObject, UICollectionViewDataSource {
        var made = 0
        func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 2 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            made += 1
            return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
        }
    }

    @Test func headersAndFootersFrameTheSections() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 200), scale: 2)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 90, height: 60)
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        layout.headerReferenceSize = CGSize(width: 0, height: 44)
        layout.footerReferenceSize = CGSize(width: 0, height: 30)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "header")
        let source = Source()
        collection.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 200))
        // A section is 44 + 12 + 60 + 12 + 30 = 158 tall; the content holds three.
        #expect(collection.contentSize.height == 474)
        let header0 = collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0))
        #expect(header0?.frame == CGRect(x: 0, y: 0, width: 320, height: 44))
        #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0))?.frame == CGRect(x: 16, y: 56, width: 90, height: 60))
        let footer0 = collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: 0))
        #expect(footer0?.frame == CGRect(x: 0, y: 128, width: 320, height: 30))
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 1))?.frame.minY == 158)
        // Only the views in the 200 pt window exist: two headers, one footer.
        #expect(source.made == 3)
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 2)) == nil)
        // Scrolling to the end pools the first section's views and makes the last section's.
        collection.contentOffset = CGPoint(x: 0, y: 274)
        scene.layout(in: CGSize(width: 320, height: 200))
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)) == nil)
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: 2))?.frame.maxY == 474)
    }
}

/// Content configurations (Containers/ContentConfiguration.swift): a list content configuration
/// fills the cell's content view and sizes the row; a background configuration colours the cell.
@Suite @MainActor struct ContentConfigurationTests {
    final class Source: NSObject, UITableViewDataSource {
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = indexPath.row == 0 ? UIListContentConfiguration.cell() : UIListContentConfiguration.subtitleCell()
            content.text = "Title"
            if indexPath.row == 1 { content.secondaryText = "Subtitle" }
            cell.contentConfiguration = content
            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = .systemYellow
            cell.backgroundConfiguration = background
            return cell
        }
    }

    @Test func listContentFillsTheCellAndSizesTheRow() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        let source = Source()
        table.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        guard let first = table.cellForRow(at: IndexPath(row: 0, section: 0)), let second = table.cellForRow(at: IndexPath(row: 1, section: 0)) else { Issue.record("no cells"); return }
        #expect(first.frame.height == 56)
        #expect(second.frame.height > 56)
        let content = first.contentView.subviews.compactMap { $0 as? UIListContentView }.first
        #expect(content != nil)
        #expect(content?.frame.size == first.contentView.bounds.size)
        #expect(content?.textLabel.text == "Title")
        #expect(content?.textLabel.frame.minX == 20)
        #expect(first.backgroundColor == .systemYellow)
        first.contentConfiguration = nil
        #expect(first.contentView.subviews.compactMap { $0 as? UIListContentView }.isEmpty)
    }
}
