import SwiftUI
import AppKit

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) -> NSHostingView<AnyView> {
    let h = NSHostingView(rootView: AnyView(v))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

/// Frames reported by tagged leaves.
@MainActor final class Frames { static var all: [String: CGRect] = [:] }

extension View {
    func probe(_ name: String) -> some View {
        self.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { Frames.all[name] = $0 }
    }
}

@MainActor func measure(_ title: String, size: CGSize = CGSize(width: 300, height: 300), _ v: some View) {
    Frames.all = [:]
    _ = host(v.coordinateSpace(.named("root")).frame(width: size.width, height: size.height, alignment: .topLeading), size: size)
    spin(0.3)
    let s = Frames.all.sorted { ($0.value.minY, $0.value.minX, $0.key) < ($1.value.minY, $1.value.minX, $1.key) }
    print("== \(title)")
    for (k, r) in s { print("   \(k): x\(Int(r.minX)) y\(Int(r.minY)) w\(Int(r.width)) h\(Int(r.height))") }
}

struct Counter: Layout {
    let tag: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var s = "\(tag): count=\(subviews.count)"
        s += " tags=" + subviews.map { String(describing: $0.containerValues.tag(for: Int.self)) }.joined(separator: ",")
        s += " sizes=" + subviews.map { let z = $0.sizeThatFits(.unspecified); return "\(Int(z.width))x\(Int(z.height))" }.joined(separator: ",")
        print(s)
        return CGSize(width: 10, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: .unspecified) }
    }
}
