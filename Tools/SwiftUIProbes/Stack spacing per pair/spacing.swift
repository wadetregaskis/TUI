// What a stack's `spacing: nil` puts between two views that state their own
// spacing preferences (decisions B20): two custom layouts whose
// `spacing(subviews:cache:)` asks for no space on the facing edges, beside
// each other and beside plain views, through the wrappers a stack's content
// passes them through, in each stack.
//
// Build and run (from this folder):
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 spacing.swift -o "$TMPDIR/spacing"
//   "$TMPDIR/spacing" | diff spacing.out -

import AppKit
import SwiftUI

@MainActor var keep: [NSWindow] = []

@MainActor func host<V: View>(_ view: V, size: CGSize) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    keep.append(window)
    hosting.layoutSubtreeIfNeeded()
}

@MainActor func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// Frames reported by tagged leaves.
@MainActor final class Frames { static var all: [String: CGRect] = [:] }

extension View {
    func probe(_ name: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { Frames.all[name] = $0 }
    }
}

/// Lays `view` out at the top left of `size` and prints each tagged leaf's frame, left to right, and the
/// gap between each leaf and the one before it on its axis.
@MainActor func measure(_ title: String, size: CGSize = CGSize(width: 400, height: 200), vertical: Bool = false, _ view: some View) {
    Frames.all = [:]
    host(view.coordinateSpace(.named("root")).frame(width: size.width, height: size.height, alignment: .topLeading), size: size)
    spin()
    let sorted = Frames.all.sorted { (vertical ? $0.value.minY : $0.value.minX) < (vertical ? $1.value.minY : $1.value.minX) }
    var line = "== \(title):"
    var previous: CGRect?
    for (name, frame) in sorted {
        let start = vertical ? frame.minY : frame.minX
        if let previous {
            let gap = start - (vertical ? previous.maxY : previous.maxX)
            line += " +\(Int(gap.rounded()))"
        }
        line += " \(name)@\(Int(start.rounded()))"
        previous = frame
    }
    print(line)
}

/// A 20x10 box that reports its frame.
struct Box: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View { Color.red.frame(width: 20, height: 10).probe(name) }
}

/// Which edges a `Row` asks to be left without space.
enum Tightness { case none, all, leading, trailing }

/// Lays its subviews in a row with no space between them, and states the spacing `tight` says around itself:
/// the default, `ViewSpacing()`, on the edges it does not name, and `.zero` merged into the ones it does.
/// (`distances.swift` shows why it is spelled that way round: `.zero` merged with the default is `.zero`.)
struct Row: Layout {
    let tight: Tightness

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
            x += size.width
        }
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
        var stated = ViewSpacing()
        switch tight {
        case .none: break
        case .all: stated.formUnion(.zero)
        case .leading: stated.formUnion(.zero, edges: .leading)
        case .trailing: stated.formUnion(.zero, edges: .trailing)
        }
        return stated
    }
}

/// Lays its subviews in a row and keeps `Layout`'s own `spacing(subviews:cache:)`: its subviews', merged.
struct Merging: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Row(tight: .none).sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        Row(tight: .none).placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

/// An app's own view whose body is a tight row.
struct Wrapped: View {
    let name: String
    var body: some View { Row(tight: .all) { Box(name) } }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            measure("hstack box|box", HStack { Box("a"); Box("b") })
            measure("hstack text|text", HStack { Text("a").probe("a"); Text("b").probe("b") })
            measure("hstack none|none", HStack { Row(tight: .none) { Box("a") }; Row(tight: .none) { Box("b") } })
            measure("hstack all|all", HStack { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } })
            measure("hstack all|box", HStack { Row(tight: .all) { Box("a") }; Box("b") })
            measure("hstack box|all", HStack { Box("a"); Row(tight: .all) { Box("b") } })
            measure("hstack trailing|leading", HStack { Row(tight: .trailing) { Box("a") }; Row(tight: .leading) { Box("b") } })
            measure("hstack leading|trailing", HStack { Row(tight: .leading) { Box("a") }; Row(tight: .trailing) { Box("b") } })
            measure("hstack trailing|trailing", HStack { Row(tight: .trailing) { Box("a") }; Row(tight: .trailing) { Box("b") } })
            measure("hstack all|all|all", HStack { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") }; Row(tight: .all) { Box("c") } })
            measure("hstack all|box|all", HStack { Row(tight: .all) { Box("a") }; Box("b"); Row(tight: .all) { Box("c") } })
            measure("hstack all|empty|all", HStack { Row(tight: .all) { Box("a") }; EmptyView(); Row(tight: .all) { Box("b") } })
            measure("hstack all|spacer|all", size: CGSize(width: 100, height: 50), HStack { Row(tight: .all) { Box("a") }; Spacer(); Row(tight: .all) { Box("b") } })
            measure("hstack(spacing: 5) all|all", HStack(spacing: 5) { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } })
            measure("hstack(spacing: 0) box|box", HStack(spacing: 0) { Box("a"); Box("b") })
            measure("hstack all.padding(0)|all", HStack { Row(tight: .all) { Box("a") }.padding(0); Row(tight: .all) { Box("b") } })
            measure("hstack all.id|all", HStack { Row(tight: .all) { Box("a") }.id(1); Row(tight: .all) { Box("b") } })
            measure("hstack all.foregroundStyle|all", HStack { Row(tight: .all) { Box("a") }.foregroundStyle(.red); Row(tight: .all) { Box("b") } })
            measure("hstack all.frame|all", HStack { Row(tight: .all) { Box("a") }.frame(width: 20); Row(tight: .all) { Box("b") } })
            measure("hstack all.padding(4)|box", HStack { Row(tight: .all) { Box("a") }.padding(4); Box("b") })
            measure("hstack all.border|box", HStack { Row(tight: .all) { Box("a") }.border(.blue); Box("b") })
            measure("hstack all.background|box", HStack { Row(tight: .all) { Box("a") }.background(Color.blue); Box("b") })
            measure("hstack all.offset|box", HStack { Row(tight: .all) { Box("a") }.offset(x: 3); Box("b") })
            measure("hstack merging(box)|box", HStack { Merging { Box("a") }; Box("b") })
            measure("hstack merging(box,all)|box", HStack { Merging { Box("a"); Row(tight: .all) { Box("x") } }; Box("b") })
            measure("hstack box|all|box", HStack { Box("a"); Row(tight: .all) { Box("b") }; Box("c") })
            measure("hstack box|leading|box", HStack { Box("a"); Row(tight: .leading) { Box("b") }; Box("c") })
            measure("hstack box|trailing|box", HStack { Box("a"); Row(tight: .trailing) { Box("b") }; Box("c") })
            measure("hstacklayout box|all|box", HStackLayout { Box("a"); Row(tight: .all) { Box("b") }; Box("c") })
            measure("lazyhstack box|all|box", LazyHStack { Box("a"); Row(tight: .all) { Box("b") }; Box("c") })
            measure("hstack(spacing: 5) box|all|box", HStack(spacing: 5) { Box("a"); Row(tight: .all) { Box("b") }; Box("c") })
            measure("hstack wrapped|wrapped", HStack { Wrapped(name: "a"); Wrapped(name: "b") })
            measure("hstack anylayout all|all", HStack { AnyLayout(Row(tight: .all)) { Box("a") }; AnyLayout(Row(tight: .all)) { Box("b") } })
            measure("hstack foreach all x3", HStack { ForEach(0..<3, id: \.self) { index in Row(tight: .all) { Box("r\(index)") } } })
            measure("hstack group all|all", HStack { Group { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } } })
            measure("hstack if all|all", HStack { if true { Row(tight: .all) { Box("a") } }; Row(tight: .all) { Box("b") } })
            measure("hstacklayout all|all", HStackLayout { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } })
            measure("lazyhstack all|all", LazyHStack { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } })
            measure("hstack hstack(all|all)|box", HStack { HStack { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } }; Box("c") })
            measure("hstack hstack(all)|all", HStack { HStack { Row(tight: .all) { Box("a") } }; Row(tight: .all) { Box("b") } })
            measure("vstack box|box", vertical: true, VStack { Box("a"); Box("b") })
            measure("vstack all|all", vertical: true, VStack { Row(tight: .all) { Box("a") }; Row(tight: .all) { Box("b") } })
            measure("vstack all|box", vertical: true, VStack { Row(tight: .all) { Box("a") }; Box("b") })
        }
    }
}
