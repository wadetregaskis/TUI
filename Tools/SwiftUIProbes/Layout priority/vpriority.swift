import SwiftUI
import AppKit

// 2026-11-10: what a multi-line `Text` keeps in an overfull `VStack`, and
// whether a sibling's `layoutPriority` takes its lines. Heights in lines of
// the monospaced font, a line measured as a one-line `Text`'s height. A
// `Layout` asks each text its size under a width and a height of 0 (its
// minimum), nil (its ideal) and a few lines; a hosted column records what
// each child was given.

let fontSize: CGFloat = 20
let font = Font.system(size: fontSize, design: .monospaced)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Sizes {
    static var sizes: [String: CGSize] = [:]
    static var line: CGFloat = 0
    static var asked: [String] = []
}

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

/// Asks its one subview its size under each proposal and records it.
struct Asker: Layout {
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        let line = MainActor.assumeIsolated { Sizes.line }
        if line > 0 {
            let proposals: [(String, CGFloat?)] = [("0", 0), ("nil", nil), ("1", line), ("2", 2 * line), ("inf", .infinity)]
            let report = proposals.map { name, height in
                let h = s.sizeThatFits(ProposedViewSize(width: 300, height: height)).height
                return "h=\(name):\(String(format: "%.2f", h / line))"
            }.joined(separator: " ")
            MainActor.assumeIsolated { Sizes.asked.append("\(label)\t\(report)") }
        }
        return s.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor func runV<V: View>(_ name: String, heightLines: CGFloat, names: [String], @ViewBuilder _ v: () -> V) {
    Sizes.sizes = [:]
    let line = Sizes.line
    let column = VStack(spacing: 0) { v() }.font(font).frame(width: 300, height: heightLines * line, alignment: .top)
    host(column, size: CGSize(width: 340, height: heightLines * line + 40))
    spin()
    let report = names.map { n in
        "\(n)=\(Sizes.sizes[n].map { String(format: "%.2f", $0.height / line) } ?? "?")"
    }.joined(separator: " ")
    print("\(name)\t[\(Int(heightLines))]\t\(report)")
}

MainActor.assumeIsolated {
    // The line: a one-line text's height.
    host(Text("x").font(font).measured("line"), size: CGSize(width: 340, height: 200))
    spin()
    Sizes.line = Sizes.sizes["line"]?.height ?? 1
    print("line\t\(Sizes.line) points")

    let three = "one\ntwo\nthree"
    let other = "four\nfive\nsix"
    // 1. A three-line text's size under a width, at heights 0, nil, 1, 2 lines, infinity.
    host(
        VStack {
            Asker(label: "plain") { Text(three) }
            Asker(label: "lineLimit(3)") { Text(three).lineLimit(3) }
            Asker(label: "lineLimit(3,reserves)") { Text(three).lineLimit(3, reservesSpace: true) }
            Asker(label: "lineLimit(2...)") { Text(three).lineLimit(2...) }
            Asker(label: "fixedSize(v)") { Text(three).fixedSize(horizontal: false, vertical: true) }
            Asker(label: "one-line") { Text("one") }
        }.font(font), size: CGSize(width: 340, height: 600))
    spin()
    for line in Sizes.asked.uniqued() { print("min\t\(line)") }

    // 2. Two three-line texts in a column four lines tall.
    runV("v-b-priority", heightLines: 4, names: ["a", "b"]) {
        Text(three).measured("a"); Text(other).layoutPriority(1).measured("b")
    }
    runV("v-a-priority", heightLines: 4, names: ["a", "b"]) {
        Text(three).layoutPriority(1).measured("a"); Text(other).measured("b")
    }
    runV("v-equal", heightLines: 4, names: ["a", "b"]) {
        Text(three).measured("a"); Text(other).measured("b")
    }
    runV("v-b-priority-a-fixed", heightLines: 4, names: ["a", "b"]) {
        Text(three).fixedSize(horizontal: false, vertical: true).measured("a")
        Text(other).layoutPriority(1).measured("b")
    }
    runV("v-b-priority-a-reserves", heightLines: 4, names: ["a", "b"]) {
        Text(three).lineLimit(2...).measured("a"); Text(other).layoutPriority(1).measured("b")
    }
    runV("v-b-priority-a-limit3", heightLines: 4, names: ["a", "b"]) {
        Text(three).lineLimit(3).measured("a"); Text(other).layoutPriority(1).measured("b")
    }
    print("done")
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
