// Where a drop between the rows of a hierarchical SwiftUI Table lands: which
// loop's `dropDestination(for:action:)` hears it, and at what offset. The
// table is an NSOutlineView; the probe hands its data source a drop at
// (item, childIndex) as NSOutlineView would propose one, carrying a string,
// and records which loop's action ran.
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 common.swift outlineinsert.swift -o "$TMPDIR/oi" && "$TMPDIR/oi"
import AppKit
import SwiftUI

@MainActor var log: [String] = []

struct Node: Identifiable, Hashable {
    let id: String
    var children: [Node] = []
}

let roots = [
    Node(id: "A", children: [Node(id: "a1"), Node(id: "a2")]),
    Node(id: "B", children: [Node(id: "b1")]),
    Node(id: "C"),
]

struct Probe: View {
    let childLoops: Bool
    let rootLoop: Bool

    @TableRowBuilder<Node>
    func row(_ root: Node) -> some TableRowContent<Node> {
        if root.children.isEmpty {
            TableRow(root)
        } else {
            DisclosureTableRow(root, isExpanded: .constant(true)) {
                if childLoops {
                    ForEach(root.children) { TableRow($0) }
                        .dropDestination(for: String.self) { index, items in
                            log.append("children of \(root.id): offset \(index) \(items)")
                        }
                } else {
                    ForEach(root.children) { TableRow($0) }
                }
            }
        }
    }

    var body: some View {
        Table(of: Node.self) {
            TableColumn("Name") { Text($0.id) }
        } rows: {
            if rootLoop {
                ForEach(roots) { root in row(root) }
                    .dropDestination(for: String.self) { index, items in
                        log.append("roots: offset \(index) \(items)")
                    }
            } else {
                ForEach(roots) { root in row(root) }
            }
        }
        .frame(width: 300, height: 300)
    }
}

final class FakeDrag: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    weak var window: NSWindow?
    init(_ window: NSWindow) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("probe-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("payload", forType: .string)
        self.window = window
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor func outlines(_ v: NSView) -> [NSOutlineView] {
    var out: [NSOutlineView] = []
    if let t = v as? NSOutlineView { out.append(t) }
    for c in v.subviews { out += outlines(c) }
    return out
}

@MainActor func run(_ name: String, childLoops: Bool, rootLoop: Bool) {
    let h = host(Probe(childLoops: childLoops, rootLoop: rootLoop), size: CGSize(width: 300, height: 300))
    spin(0.6)
    guard let outline = outlines(h).first, let source = outline.dataSource else {
        print("\(name): no outline view"); return
    }
    var rows: [String] = []
    for r in 0..<outline.numberOfRows {
        let item = outline.item(atRow: r)
        rows.append("\(r):level\(outline.level(forRow: r))")
        _ = item
    }
    print("\(name): rows \(rows.joined(separator: " "))")
    let itemA = outline.item(atRow: 0)
    let itemB = outline.item(atRow: 3)
    let cases: [(String, Any?, Int)] = [
        ("root, child 0", nil, 0), ("root, child 1", nil, 1), ("root, child 2", nil, 2), ("root, child 3", nil, 3),
        ("A, child 0", itemA, 0), ("A, child 1", itemA, 1), ("A, child 2", itemA, 2),
        ("B, child 1", itemB, 1),
    ]
    for (label, item, index) in cases {
        log = []
        let drag = FakeDrag(h.window!)
        let op = source.outlineView?(outline, validateDrop: drag, proposedItem: item, proposedChildIndex: index) ?? []
        let accepted = source.outlineView?(outline, acceptDrop: drag, item: item, childIndex: index) ?? false
        spin(0.4)
        print("\(name) | \(label): validate=\(op.rawValue) accept=\(accepted) heard=\(log)")
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            run("both", childLoops: true, rootLoop: true)
            run("rootsOnly", childLoops: false, rootLoop: true)
            run("childrenOnly", childLoops: true, rootLoop: false)
        }
    }
}
