// What a nested stack, and a view of the app's own, state about the spacing
// beside them (lane LAYOUT, 2026-10-18; decisions B-BITEMS1-3): a row's
// leading and trailing edges are its first and last child's, a column's and a
// ZStack's are every child's merged, a lazy stack states nothing, and a view
// of one's own states its body's through a stack, an if/else or a padding.
// The harness is spacing.swift's.
//
// Build and run (from this folder):
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 nested.swift -o "$TMPDIR/nested"
//   "$TMPDIR/nested" | diff nested.out -

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


/// An app view whose body is a stack holding a tight row.
struct WrappedStack: View {
    let name: String
    var body: some View { HStack { Row(tight: .all) { Box(name) } } }
}
/// An app view whose body is an if/else of tight rows.
struct WrappedBranch: View {
    let name: String
    var body: some View { if true { Row(tight: .all) { Box(name) } } else { Box(name) } }
}
/// An app view whose body is a padded tight row.
struct WrappedPadded: View {
    let name: String
    var body: some View { Row(tight: .all) { Box(name) }.padding(0) }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            measure("hstack vstack(all)|box", HStack { VStack { Row(tight: .all) { Box("a") } }; Box("b") })
            measure("hstack vstack(all, box)|box", HStack { VStack { Row(tight: .all) { Box("a") }; Box("x") }; Box("b") })
            measure("hstack vstack(box)|box", HStack { VStack { Box("a") }; Box("b") })
            measure("hstack hstack(box)|box", HStack { HStack { Box("a") }; Box("b") })
            measure("hstack hstack(all, box)|box", HStack { HStack { Row(tight: .all) { Box("a") }; Box("x") }; Box("b") })
            measure("hstack hstack(box, all)|box", HStack { HStack { Box("x"); Row(tight: .all) { Box("a") } }; Box("b") })
            measure("hstack box|hstack(all, box)", HStack { Box("b"); HStack { Row(tight: .all) { Box("a") }; Box("x") } })
            measure("hstack zstack(all)|box", HStack { ZStack { Row(tight: .all) { Box("a") } }; Box("b") })
            measure("hstack wrappedStack|box", HStack { WrappedStack(name: "a"); Box("b") })
            measure("hstack wrappedBranch|box", HStack { WrappedBranch(name: "a"); Box("b") })
            measure("hstack wrappedPadded|box", HStack { WrappedPadded(name: "a"); Box("b") })
            measure("hstack lazyvstack(all)|box", HStack { LazyVStack { Row(tight: .all) { Box("a") } }; Box("b") })
            measure("hstack lazyhstack(all)|box", HStack { LazyHStack { Row(tight: .all) { Box("a") } }; Box("b") })
            measure("hstack vstack(box, spacer)|box", HStack { VStack { Box("a"); Spacer() }; Box("b") })
            measure("hstack vstack(spacer, box)|box", HStack { VStack { Spacer(); Box("a") }; Box("b") })
            measure("hstack hstack(box, spacer)|box", size: CGSize(width: 100, height: 50), HStack { HStack { Box("a"); Spacer() }; Box("b") })
            measure("hstack zstack(box, spacer)|box", HStack { ZStack { Box("a"); Spacer() }; Box("b") })
            measure("hstack spacer-only vstack|box", HStack { Box("a"); VStack { Spacer() }; Box("b") })
            measure("vstack hstack(box, spacer)/box", vertical: true, VStack { HStack { Box("a"); Spacer() }; Box("b") })
            measure("hstack vstack(all, spacer)|box", HStack { VStack { Row(tight: .all) { Box("a") }; Spacer() }; Box("b") })
        }
    }
}
