// The arithmetic behind `spacing.out`: what `ViewSpacing`'s own values answer
// `distance(to:along:)` with, and what `LayoutSubview.spacing` holds for the
// views `spacing.swift` lays out (decisions B20).
//
// Build and run (from this folder):
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 distances.swift -o "$TMPDIR/distances"
//   "$TMPDIR/distances" | diff distances.out -

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

func d(_ a: ViewSpacing, _ b: ViewSpacing, _ axis: Axis = .horizontal) -> String {
    "\(Int(a.distance(to: b, along: axis).rounded()))"
}

/// Prints the distances between its subviews' spacings, once, and lays them out in a row.
struct Reader: Layout {
    let title: String

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if !Printed.titles.contains(title) {
            Printed.titles.insert(title)
            var line = "== \(title):"
            for index in subviews.indices.dropFirst() {
                let a = subviews[index - 1].spacing, b = subviews[index].spacing
                line += " h\(d(a, b)) v\(d(a, b, .vertical))"
            }
            print(line)
        }
        return CGSize(width: 100, height: 20)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: .unspecified) }
    }
}

enum Printed { nonisolated(unsafe) static var titles: Set<String> = [] }

/// A layout that states `stated` around itself.
struct Stating: Layout {
    let stated: ViewSpacing
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: 20, height: 10) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing { stated }
}

/// The default `spacing(subviews:cache:)`: its subviews' merged.
struct Merging: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: 20, height: 10) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let zero = ViewSpacing.zero, plain = ViewSpacing()
            print("== values: init|init h\(d(plain, plain)) v\(d(plain, plain, .vertical))"
                + " init|zero h\(d(plain, zero)) zero|init h\(d(zero, plain)) zero|zero h\(d(zero, zero))")
            var unioned = ViewSpacing.zero
            unioned.formUnion(plain)
            print("== values: zero.union(init)|init h\(d(unioned, plain)) init|zero.union(init) h\(d(plain, unioned))")
            let box = Color.red.frame(width: 20, height: 10)
            let views: [(String, AnyView)] = [
                ("box|box", AnyView(Reader(title: "box|box") { box; box })),
                ("text|text", AnyView(Reader(title: "text|text") { Text("a"); Text("b") })),
                ("box|text", AnyView(Reader(title: "box|text") { box; Text("b") })),
                ("color|color", AnyView(Reader(title: "color|color") { Color.red; Color.blue })),
                ("button|button", AnyView(Reader(title: "button|button") { Button("a") {}; Button("b") {} })),
                ("zero|box", AnyView(Reader(title: "zero|box") { Stating(stated: zero) { box }; box })),
                ("init|box", AnyView(Reader(title: "init|box") { Stating(stated: plain) { box }; box })),
                ("init|init", AnyView(Reader(title: "init|init") { Stating(stated: plain) { box }; Stating(stated: plain) { box } })),
                ("merging(box)|box", AnyView(Reader(title: "merging(box)|box") { Merging { box }; box })),
                ("merging(text)|text", AnyView(Reader(title: "merging(text)|text") { Merging { Text("a") }; Text("b") })),
                ("merging()|box", AnyView(Reader(title: "merging()|box") { Merging {}; box })),
                ("hstack(box)|box", AnyView(Reader(title: "hstack(box)|box") { HStack { box }; box })),
                ("padding(box)|box", AnyView(Reader(title: "padding(box)|box") { box.padding(); box })),
                ("spacer|box", AnyView(Reader(title: "spacer|box") { Spacer(); box })),
            ]
            for (_, view) in views { host(view, size: CGSize(width: 200, height: 100)) }
            spin()
            print("== done")
        }
    }
}
