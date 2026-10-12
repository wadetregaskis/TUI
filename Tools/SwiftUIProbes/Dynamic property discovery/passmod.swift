// passmod.swift: does SwiftUI run a ViewModifier's body, and update() its
// properties, when the body returns `content` unchanged? Output: passmod.out.

import SwiftUI
import AppKit

// A-DYNP-1 follow-up (2026-10-10): which stored fields of a view SwiftUI
// visits for DynamicProperty, measured on macOS 15.8.1 (SwiftUI 6.5.4) with an
// offscreen NSHostingView, as ../Dynamic properties/dp.swift does.
//
// Every case holds the same property, `Full`, somewhere in a view, hosted
// under `.lineLimit(3)`. Its three probes:
//   count  incremented by update(): 1 in body = update ran and was written back
//   limit  an @Environment: Optional(3) = resolved, nil = default (unresolved)
//   kept   an @State, initial 5: after the case's poke writes 9 through
//          `$kept` and bumps the view's own @State `tick`, body reads 9 if the
//          state is installed, 5 if not (an uninstalled State's binding is a
//          constant).
// `updates` counts the update() calls per tag.
//
// Built twice: plain, and with -D OPTCONF, which adds a retroactive
// `Optional: DynamicProperty where Wrapped: DynamicProperty`.

setvbuf(stdout, nil, _IONBF, 0)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 100)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Log {
    static var lines: [String] = []
    static var updates: [String: Int] = [:]
    static var pokes: [String: () -> Void] = [:]
}

#if OPTCONF
extension Optional: @retroactive DynamicProperty where Wrapped: DynamicProperty {}
#endif

struct Full: DynamicProperty {
    let tag: String
    var count = 0
    @Environment(\.lineLimit) var limit
    @State var kept = 5
    init(tag: String) { self.tag = tag }
    mutating func update() {
        count += 1
        MainActor.assumeIsolated { Log.updates[tag, default: 0] += 1 }
    }
    var summary: String { "count=\(count) limit=\(String(describing: limit)) kept=\(kept)" }
}

/// Registers the case's poke: write 9 through `kept` (nil: none to write),
/// then bump the view's own state so its body runs again either way.
@MainActor func registerPoke(_ name: String, _ kept: Binding<Int>?, _ tick: Binding<Int>) {
    Log.pokes[name] = {
        kept?.wrappedValue = 9
        tick.wrappedValue += 1
    }
}

@MainActor func line(_ name: String, _ tick: Int, _ what: String) -> some View {
    Log.lines.append("\(name) body tick=\(tick) \(what)")
    return Text(what)
}

struct PassMod: ViewModifier {
    var p = Full(tag: "passMod")
    func body(content: Content) -> some View {
        Log.lines.append("passMod body p: \(p.summary)")
        return content
    }
}
struct PadMod: ViewModifier {
    var p = Full(tag: "padMod")
    func body(content: Content) -> some View {
        Log.lines.append("padMod body p: \(p.summary)")
        return content.padding(1)
    }
}
struct PassView: View { var body: some View { Text("a").modifier(PassMod()) } }
struct PadView: View { var body: some View { Text("a").modifier(PadMod()) } }
struct PassVStack: View { var body: some View { VStack { Text("a").modifier(PassMod()) } } }
@MainActor func run() {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        print("   updates: \(Log.updates.sorted { $0.key < $1.key })")
        Log.lines = []; Log.updates = [:]
    }
    _ = host(PassView().lineLimit(3)); spin(); report("pass-through modifier")
    _ = host(PadView().lineLimit(3)); spin(); report("padding modifier")
    _ = host(PassVStack().lineLimit(3)); spin(); report("pass-through modifier in VStack")
}
MainActor.assumeIsolated { run() }
