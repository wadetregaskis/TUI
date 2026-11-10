import SwiftUI
import AppKit

// Text-and-styling hunt (2026-11-10): where SwiftUI puts a label beside text
// that wraps onto several lines. A `LabeledContent` whose value wraps, a
// `Label` whose title wraps, and the reverse (a wrapping label, a one-line
// value): is the one-line part level with the FIRST line of the other, or
// centred on the block? Offscreen NSHostingView; each part reports its frame
// in the hosting view's space, top-left origin, in points.

let canvas = CGSize(width: 400, height: 300)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: canvas)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: canvas), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

struct Frames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func report(_ name: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: Frames.self, value: [name: g.frame(in: .named("root"))])
        })
    }
}

@MainActor final class Sink { var frames: [String: CGRect] = [:] }

@MainActor func show<V: View>(_ title: String, _ view: V) {
    let sink = Sink()
    let root = view
        .frame(width: 160, alignment: .topLeading)
        .coordinateSpace(name: "root")
        .onPreferenceChange(Frames.self) { sink.frames = $0 }
        .font(.system(size: 13))
    _ = host(root)
    spin()
    print(title)
    for (name, rect) in sink.frames.sorted(by: { $0.key < $1.key }) {
        print("    \(name): y \(Int(rect.minY))..\(Int(rect.maxY)) x \(Int(rect.minX))..\(Int(rect.maxX))")
    }
}

let long = "one two three four five six seven eight nine ten"

MainActor.assumeIsolated {
    show("LabeledContent, wrapping value", LabeledContent { Text(long).report("value") } label: { Text("Name").report("label") })
    show("LabeledContent, wrapping label", LabeledContent { Text("Value").report("value") } label: { Text(long).report("label") })
    show("Label, wrapping title", Label { Text(long).report("title") } icon: { Image(systemName: "star").report("icon") })
    show("Label, one-line title", Label { Text("Title").report("title") } icon: { Image(systemName: "star").report("icon") })
    // A tall icon that is not a symbol and not text: is the title at its top,
    // at its centre, or on its bottom edge (a shape's baseline)?
    show("Label, tall shape icon, one-line title", Label { Text("Title").report("title") } icon: {
        Color.red.frame(width: 16, height: 40).report("icon")
    })
    show("Label, tall shape icon, wrapping title", Label { Text(long).report("title") } icon: {
        Color.red.frame(width: 16, height: 40).report("icon")
    })
}
