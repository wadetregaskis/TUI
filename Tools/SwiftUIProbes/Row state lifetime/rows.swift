import AppKit
import SwiftUI

// Row state lifetime (2026-10-29): when does SwiftUI drop the @State of a row
// in a List, a lazy stack and an outline? Each row's @State is stamped, once,
// with a serial when SwiftUI makes it (`@State var born = Serial.next()`; the
// initial value is evaluated on every init, but kept only when the state is
// new), and its body logs the stamp: the same stamp after a step means the
// state was kept, a new one that it was made again.
//
// macOS 15, offscreen NSHostingView. Outline expansion is driven through the
// NSOutlineView SwiftUI builds for a `List(_:children:)` / `OutlineGroup`.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, height: CGFloat = 600) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: height)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
/// Runs the loop, then lays out and draws every window: an offscreen window
/// is not displayed on its own, and a lazy stack places its rows only when
/// laid out.
@MainActor func spin(_ s: Double = 0.4) {
    RunLoop.main.run(until: Date().addingTimeInterval(s / 2))
    for window in keep {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(s / 2))
}

@MainActor enum Serial {
    static var count = 0
    static func next() -> Int { count += 1; return count }
}
@MainActor enum Seen {
    static var born: [String: Int] = [:]
    /// onAppear (+) and onDisappear (-) of the rows asked about, since the last report.
    static var events: [String] = []
    static func report(_ step: String, _ names: [String]) {
        let shown = events.filter { event in names.contains { event.dropFirst() == $0 } }
        let stamps: [String] = names.map { name in
            let stamp: String = born[name].map { String($0) } ?? "-"
            return name + "=" + stamp
        }
        let tail: String = shown.isEmpty ? "" : "  [" + shown.joined(separator: " ") + "]"
        print(step + ": " + stamps.joined(separator: " ") + tail)
        born = [:]
        events = []
    }
}

struct Stamped: View {
    let name: String
    @Environment(Model.self) private var model
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    var body: some View {
        // Reading the tick redraws every row on each step, so each one alive reports.
        MainActor.assumeIsolated { Seen.born[name] = born }
        return Text("\(name) \(born) \(model.tick)")
            .onAppear { MainActor.assumeIsolated { Seen.events.append("+\(name)") } }
            .onDisappear { MainActor.assumeIsolated { Seen.events.append("-\(name)") } }
    }
}

struct Node: Identifiable, Hashable {
    let id: String
    var children: [Node]?
}

@MainActor @Observable final class Model {
    var ids = ["a", "b", "c"]
    var tick = 0
    /// Several updates a while apart, so a removal has long been committed.
    func settle() {
        for _ in 0..<3 { tick += 1; spin(0.5) }
    }
    var expanded = true
    var tree: [Node] = [Node(id: "p", children: [Node(id: "p1", children: nil), Node(id: "p2", children: nil)])]
}

func outline(in view: NSView) -> NSOutlineView? {
    if let o = view as? NSOutlineView { return o }
    for sub in view.subviews { if let o = outline(in: sub) { return o } }
    return nil
}

@main @MainActor struct Probe {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let names = ["a", "b", "c"]

        // 1. A List over a ForEach: an id removed, then added back on a later update.
        let m1 = Model()
        struct Listed: View {
            @Environment(Model.self) var m
            var body: some View { List { ForEach(m.ids, id: \.self) { Stamped(name: "list-\($0)") } } }
        }
        _ = host(Listed().environment(m1))
        let list = { (m: Model) in names.map { "list-\($0)" } }
        spin(); Seen.report("list initial", list(m1))
        m1.ids = ["a", "c"]; spin(); m1.settle(); Seen.report("list b removed", list(m1))
        m1.ids = ["a", "b", "c"]; spin(); m1.tick += 1; spin(); Seen.report("list b back", list(m1))
        // …and after 300 other ids have come and gone, a few at a time, past any reuse cache.
        m1.ids = ["a", "c"]; spin()
        for round in 0..<60 { m1.ids = ["a", "c"] + (0..<5).map { "x\(round)-\($0)" }; spin(0.05) }
        m1.ids = ["a", "c"]; spin(); m1.settle(); Seen.born = [:]; Seen.events = []
        m1.ids = ["a", "b", "c"]; spin(); m1.tick += 1; spin(); Seen.report("list b back after 300 others", list(m1))

        // 2. A LazyVStack over a ForEach: the same.
        let m2 = Model()
        struct Lazy: View {
            @Environment(Model.self) var m
            var body: some View { ScrollView { LazyVStack { ForEach(m.ids, id: \.self) { Stamped(name: "lazy-\($0)") } } } }
        }
        _ = host(Lazy().environment(m2))
        let lazy = names.map { "lazy-\($0)" }
        spin(); Seen.report("lazy initial", lazy)
        m2.ids = ["a", "c"]; spin(); m2.settle(); Seen.report("lazy b removed", lazy)
        m2.ids = ["a", "b", "c"]; spin(); m2.tick += 1; spin(); Seen.report("lazy b back", lazy)
        m2.ids = ["a", "c"]; spin()
        for round in 0..<60 { m2.ids = ["a", "c"] + (0..<5).map { "x\(round)-\($0)" }; spin(0.05) }
        m2.ids = ["a", "c"]; spin(); m2.settle(); Seen.born = [:]; Seen.events = []
        m2.ids = ["a", "b", "c"]; spin(); m2.tick += 1; spin(); Seen.report("lazy b back after 300 others", lazy)
        // b removed and NOT drawn since: does its body still run?
        m2.ids = ["a", "c"]; spin(); m2.settle(); Seen.report("lazy b removed again", lazy)

        // 2b. A plain VStack over a ForEach, the control.
        let m7 = Model()
        struct Eager: View {
            @Environment(Model.self) var m
            var body: some View { VStack { ForEach(m.ids, id: \.self) { Stamped(name: "vstack-\($0)") } } }
        }
        _ = host(Eager().environment(m7))
        let eager = names.map { "vstack-\($0)" }
        spin(); Seen.report("vstack initial", eager)
        m7.ids = ["a", "c"]; spin(); m7.settle(); Seen.report("vstack b removed", eager)
        m7.ids = ["a", "b", "c"]; spin(); m7.tick += 1; spin(); Seen.report("vstack b back", eager)

        // 3. A DisclosureGroup in a List, collapsed and expanded again.
        let m3 = Model()
        struct Disclosed: View {
            @Environment(Model.self) var m
            var body: some View {
                @Bindable var m = m
                List {
                    DisclosureGroup(isExpanded: $m.expanded) {
                        Stamped(name: "dg-child")
                    } label: { Stamped(name: "dg-label") }
                }
            }
        }
        _ = host(Disclosed().environment(m3))
        spin(); Seen.report("disclosure initial", ["dg-label", "dg-child"])
        m3.expanded = false; spin(); m3.settle(); Seen.report("disclosure collapsed", ["dg-label", "dg-child"])
        m3.expanded = true; spin(); m3.tick += 1; spin(); Seen.report("disclosure expanded again", ["dg-label", "dg-child"])

        // 4. A DisclosureGroup in a VStack (no List).
        let m4 = Model()
        struct DisclosedStack: View {
            @Environment(Model.self) var m
            var body: some View {
                @Bindable var m = m
                VStack {
                    DisclosureGroup(isExpanded: $m.expanded) { Stamped(name: "vdg-child") } label: { Text("L") }
                }
            }
        }
        _ = host(DisclosedStack().environment(m4))
        spin(); Seen.report("stack disclosure initial", ["vdg-child"])
        m4.expanded = false; spin(); m4.settle(); Seen.report("stack disclosure collapsed", ["vdg-child"])
        m4.expanded = true; spin(); m4.tick += 1; spin(); Seen.report("stack disclosure expanded again", ["vdg-child"])

        // 5. List(_:children:): collapse and expand the parent through its NSOutlineView;
        //    then remove a child from the data, and add it back.
        let m5 = Model()
        struct Tree: View {
            @Environment(Model.self) var m
            var body: some View { List(m.tree, children: \.children) { Stamped(name: "tree-\($0.id)") } }
        }
        let h5 = host(Tree().environment(m5))
        let tree = ["tree-p", "tree-p1", "tree-p2"]
        spin()
        let o5 = outline(in: h5)
        print("tree outline found: \(o5 != nil) rows: \(o5?.numberOfRows ?? -1)")
        if let o5 { o5.expandItem(o5.item(atRow: 0)) }
        spin(); Seen.report("tree expanded", tree)
        if let o5 { o5.collapseItem(o5.item(atRow: 0)) }
        spin(); m5.settle(); Seen.report("tree collapsed", tree)
        if let o5 { o5.expandItem(o5.item(atRow: 0)) }
        spin(); m5.tick += 1; spin(); Seen.report("tree expanded again", tree)
        m5.tree = [Node(id: "p", children: [Node(id: "p2", children: nil)])]
        spin(); m5.settle(); Seen.report("tree p1 removed", tree)
        m5.tree = [Node(id: "p", children: [Node(id: "p1", children: nil), Node(id: "p2", children: nil)])]
        spin(); m5.tick += 1; spin(); Seen.report("tree p1 back", tree)

        // 6. OutlineGroup inside a List: the same steps.
        let m6 = Model()
        struct Group6: View {
            @Environment(Model.self) var m
            var body: some View {
                List { OutlineGroup(m.tree, children: \.children) { Stamped(name: "og-\($0.id)") } }
            }
        }
        let h6 = host(Group6().environment(m6))
        let og = ["og-p", "og-p1", "og-p2"]
        spin()
        let o6 = outline(in: h6)
        print("outlinegroup outline found: \(o6 != nil) rows: \(o6?.numberOfRows ?? -1)")
        if let o6 { o6.expandItem(o6.item(atRow: 0)) }
        spin(); Seen.report("outlinegroup expanded", og)
        if let o6 { o6.collapseItem(o6.item(atRow: 0)) }
        spin(); m6.settle(); Seen.report("outlinegroup collapsed", og)
        if let o6 { o6.expandItem(o6.item(atRow: 0)) }
        spin(); m6.tick += 1; spin(); Seen.report("outlinegroup expanded again", og)
        m6.tree = [Node(id: "p", children: [Node(id: "p2", children: nil)])]
        spin(); m6.settle(); Seen.report("outlinegroup p1 removed", og)
        m6.tree = [Node(id: "p", children: [Node(id: "p1", children: nil), Node(id: "p2", children: nil)])]
        spin(); m6.tick += 1; spin(); Seen.report("outlinegroup p1 back", og)
    }
}
