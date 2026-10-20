// twoplaces.swift: one view value drawn at two places (`HStack { tally; tally }`, and one value handed to
// two children): does each place keep its own @Namespace? (decisions DYNVFIX, B-DYNVFIX-5; dv.swift measured
// @State and @Environment the same way.) @FocusState is not measured here: an offscreen window never becomes
// key, so no focus write lands. Output: twoplaces.out.
// Build: swiftc -sdk <Xcode SDK> -target arm64-apple-macos15.0 twoplaces.swift -o twoplaces

import SwiftUI
import AppKit

setvbuf(stdout, nil, _IONBF, 0)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) {
    let size = CGSize(width: 300, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Log { static var lines: [String] = [] }

/// A view with a namespace, reporting it with the place it was drawn at.
struct Tally: View {
    @Namespace var ns
    let place: String
    var body: some View {
        MainActor.assumeIsolated { Log.lines.append("  \(place): namespace \(ns)") }
        return Text("x").matchedGeometryEffect(id: 0, in: ns)
    }
}

/// One value, drawn twice, each under an environment saying where.
struct SameTwice: View {
    let tally = Tally(place: "?")
    var body: some View {
        HStack {
            Placed(name: "first", content: tally)
            Placed(name: "second", content: tally)
        }
    }
}

/// Draws `content` but reports under its own name.
struct Placed: View {
    let name: String
    let content: Tally
    var body: some View { Tally(place: name + " (fresh)"); TallyCopy(name: name, tally: content) }
}

/// The handed value's namespace, read where it is drawn.
struct TallyCopy: View {
    let name: String
    let tally: Tally
    var body: some View {
        MainActor.assumeIsolated { Log.lines.append("  \(name): handed value's namespace \(tally.ns)") }
        return tally
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    print("#### one value drawn twice")
    host(SameTwice())
    spin()
    for line in Log.lines { print(line) }
}
