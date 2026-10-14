// How long a Spacer is when nothing is spare: its own minimum and ideal, and a
// row's/column's with one between two boxes (decisions A-BITEMS1-1,
// 2026-10-13). Each line: the view's size offered zero, nothing (its ideal) and
// 1000 points square.
//
// Build and run (from this folder):
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 spacer.swift -o "$TMPDIR/spacer"
//   "$TMPDIR/spacer" | diff spacer.out -
import AppKit
import SwiftUI

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ view: V, size: CGSize) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    keep.append(window)
    hosting.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
/// Each title's line, printed in the order the views are listed once all are laid out:
/// the hosting windows lay out in no fixed order.
enum Printed { nonisolated(unsafe) static var lines: [String: String] = [:] }
func f(_ s: CGSize) -> String { "\(Int(s.width.rounded()))x\(Int(s.height.rounded()))" }

/// Prints its one subview's size at zero, unspecified, and 1000x1000.
struct Sizes: Layout {
    let title: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if Printed.lines[title] == nil {
            let s = subviews[0]
            Printed.lines[title] = "== \(title): zero \(f(s.sizeThatFits(.zero))) ideal \(f(s.sizeThatFits(.unspecified))) big \(f(s.sizeThatFits(ProposedViewSize(width: 1000, height: 1000))))"
        }
        return CGSize(width: 100, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: .unspecified) }
    }
}

@main struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let box = Color.red.frame(width: 10, height: 10)
        let views: [(String, AnyView)] = [
            ("spacer", AnyView(Sizes(title: "spacer") { Spacer() })),
            ("spacer(min 0)", AnyView(Sizes(title: "spacer(min 0)") { Spacer(minLength: 0) })),
            ("spacer(min 3)", AnyView(Sizes(title: "spacer(min 3)") { Spacer(minLength: 3) })),
            ("hstack box|spacer|box", AnyView(Sizes(title: "hstack box|spacer|box") { HStack { box; Spacer(); box } })),
            ("hstack box|spacer(min 0)|box", AnyView(Sizes(title: "hstack box|spacer(min 0)|box") { HStack { box; Spacer(minLength: 0); box } })),
            ("hstack box|spacer(min 3)|box", AnyView(Sizes(title: "hstack box|spacer(min 3)|box") { HStack { box; Spacer(minLength: 3); box } })),
            ("hstack box|box", AnyView(Sizes(title: "hstack box|box") { HStack { box; box } })),
            ("hstack(spacing 0) box|spacer|box", AnyView(Sizes(title: "hstack(spacing 0) box|spacer|box") { HStack(spacing: 0) { box; Spacer(); box } })),
            ("hstack(spacing 5) box|spacer|box", AnyView(Sizes(title: "hstack(spacing 5) box|spacer|box") { HStack(spacing: 5) { box; Spacer(); box } })),
            ("hstack text|spacer|text", AnyView(Sizes(title: "hstack text|spacer|text") { HStack { Text("a"); Spacer(); Text("b") } })),
            ("hstack text|text", AnyView(Sizes(title: "hstack text|text") { HStack { Text("a"); Text("b") } })),
            ("hstack spacer|box", AnyView(Sizes(title: "hstack spacer|box") { HStack { Spacer(); box } })),
            ("hstack box|spacer|spacer|box", AnyView(Sizes(title: "hstack box|spacer|spacer|box") { HStack { box; Spacer(); Spacer(); box } })),
            ("vstack box|spacer|box", AnyView(Sizes(title: "vstack box|spacer|box") { VStack { box; Spacer(); box } })),
            ("vstack box|box", AnyView(Sizes(title: "vstack box|box") { VStack { box; box } })),
            ("vstack text|spacer|text", AnyView(Sizes(title: "vstack text|spacer|text") { VStack { Text("a"); Spacer(); Text("b") } })),
            ("vstack text|text", AnyView(Sizes(title: "vstack text|text") { VStack { Text("a"); Text("b") } })),
        ]
        for (_, view) in views { host(view, size: CGSize(width: 200, height: 100)) }
        spin()
        for (title, _) in views { print(Printed.lines[title] ?? "== \(title): ?") }
        print("== done")
    }
}
