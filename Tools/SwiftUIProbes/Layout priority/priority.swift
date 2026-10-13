import SwiftUI
import AppKit

// L12 (2026-10-13): how SwiftUI's HStack and VStack give space by
// layoutPriority. Offscreen NSHostingView (after ../Alignment guides/guide2.swift);
// each child's width is read with a GeometryReader in its background. Monospaced
// text, so one character's advance stands in for a terminal cell; the row is
// offered a width in characters.

let fontSize: CGFloat = 20
let advance = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width
let font = Font.system(size: fontSize, design: .monospaced)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<V> {
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
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Sizes { static var sizes: [String: CGSize] = [:] }

/// Records the size its view was given, under `name`.
struct Measured: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { p in
            let s = p.size
            let _ = MainActor.assumeIsolated { Sizes.sizes[name] = s }
            Color.clear
        })
    }
}
extension View { func measured(_ name: String) -> some View { modifier(Measured(name: name)) } }

func cells(_ v: CGFloat) -> String {
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}
func lines(_ v: CGFloat) -> String {
    let line = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).boundingRectForFont.height
    return String(format: "%.2f", v / line)
}

@MainActor func run<V: View>(_ name: String, widthCells: CGFloat, height: CGFloat = 200, names: [String], @ViewBuilder _ v: () -> V) {
    Sizes.sizes = [:]
    let row = HStack(spacing: 0) { v() }.font(font).frame(width: widthCells * advance, alignment: .leading)
    _ = host(row.fixedSize(horizontal: false, vertical: true), size: CGSize(width: widthCells * advance + 40, height: height))
    spin()
    let report = names.map { "\($0)=\(Sizes.sizes[$0].map { cells($0.width) } ?? "?")" }.joined(separator: " ")
    print("\(name)\t[\(Int(widthCells))]\t\(report)")
}

@MainActor func runV<V: View>(_ name: String, heightLines: CGFloat, names: [String], @ViewBuilder _ v: () -> V) {
    Sizes.sizes = [:]
    let line = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).boundingRectForFont.height
    let column = VStack(spacing: 0) { v() }.font(font).frame(width: 300, height: heightLines * line, alignment: .top)
    _ = host(column, size: CGSize(width: 340, height: heightLines * line + 40))
    spin()
    let report = names.map { "\($0)=\(Sizes.sizes[$0].map { lines($0.height) } ?? "?")" }.joined(separator: " ")
    print("\(name)\t[\(Int(heightLines))]\t\(report)")
}

MainActor.assumeIsolated {
    let a = "aaaaaaaaaa"  // 10
    let b = "bbbbbbbbbb"  // 10
    // 1. Over-wide, no priority: both truncate.
    run("equal", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).measured("b")
    }
    // 2. Over-wide, the second has priority: it keeps its width, the first truncates.
    run("b-priority", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).measured("b")
    }
    // 3. The first has priority.
    run("a-priority", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).layoutPriority(1).measured("a"); Text(b).lineLimit(1).measured("b")
    }
    // 4. Fits: priority changes nothing.
    run("fits", widthCells: 30, names: ["a", "b"]) {
        Text(a).measured("a"); Text(b).layoutPriority(1).measured("b")
    }
    // 5. A flexible child with priority beside a Spacer: who takes the surplus?
    run("flex-priority-vs-spacer", widthCells: 40, names: ["f", "s"]) {
        Text(a).frame(maxWidth: .infinity).layoutPriority(1).measured("f"); Spacer().measured("s")
    }
    run("flex-priority-vs-text", widthCells: 40, names: ["f", "t"]) {
        Text(a).frame(maxWidth: .infinity).layoutPriority(1).measured("f"); Text(b).lineLimit(1).measured("t")
    }
    run("flex-vs-text", widthCells: 40, names: ["f", "t"]) {
        Text(a).frame(maxWidth: .infinity).measured("f"); Text(b).lineLimit(1).measured("t")
    }
    run("min-of-text", widthCells: 2, names: ["t"]) {
        Text(b).lineLimit(1).measured("t")
    }
    run("flex-vs-spacer", widthCells: 40, names: ["f", "s"]) {
        Text(a).frame(maxWidth: .infinity).measured("f"); Spacer().measured("s")
    }
    // 6. Three levels.
    run("three-levels", widthCells: 15, names: ["a", "b", "c"]) {
        Text(a).lineLimit(1).layoutPriority(2).measured("a")
        Text(b).lineLimit(1).measured("b")
        Text("cccccccccc").lineLimit(1).layoutPriority(1).measured("c")
    }
    // 7. Negative priority: shrinks before an unprioritised one.
    run("negative", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(-1).measured("b")
    }
    // 8. A modifier after layoutPriority: does the priority still count?
    run("modifier-after", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).padding(0).measured("b")
    }
    // 8b. Which modifiers keep a priority written inside them.
    run("after-foreground", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).foregroundStyle(.red).measured("b")
    }
    run("after-bold-font", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).font(font).measured("b")
    }
    run("after-opacity", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).opacity(0.9).measured("b")
    }
    run("after-background", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).background(Color.yellow).measured("b")
    }
    run("after-frame", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).frame(minWidth: 0).measured("b")
    }
    run("after-id", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).id(1).measured("b")
    }
    run("after-tag", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).layoutPriority(1).tag(1).measured("b")
    }
    run("after-padding-outside", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).padding(0).layoutPriority(1).measured("b")
    }
    run("in-group", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Group { Text(b).lineLimit(1).layoutPriority(1).measured("b") }
    }
    // 9. Priority on a fixed-width child too wide for the row.
    run("fixed-wide", widthCells: 12, names: ["a", "b"]) {
        Text(a).lineLimit(1).measured("a"); Text(b).lineLimit(1).frame(width: 14 * advance).layoutPriority(1).measured("b")
    }
    // 10. Two in the same higher group share it.
    run("group-share", widthCells: 16, names: ["a", "b", "c"]) {
        Text(a).lineLimit(1).layoutPriority(1).measured("a")
        Text(b).lineLimit(1).layoutPriority(1).measured("b")
        Text("cccccccccc").lineLimit(1).measured("c")
    }
    // 11. VStack: a multi-line text with priority keeps its lines.
    runV("v-priority", heightLines: 4, names: ["a", "b"]) {
        Text("one\ntwo\nthree").measured("a"); Text("four\nfive\nsix").layoutPriority(1).measured("b")
    }
    runV("v-equal", heightLines: 4, names: ["a", "b"]) {
        Text("one\ntwo\nthree").measured("a"); Text("four\nfive\nsix").measured("b")
    }
    print("done")
}
