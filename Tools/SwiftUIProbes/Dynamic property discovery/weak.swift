// weak.swift: op.swift's harness with the retroactive Optional: DynamicProperty always on
// (#if true). Which object does SwiftUI call update() on for a `weak var w: Box?`
// field once Optional conforms? Output: weak.out. Build: swiftc -sdk <Xcode SDK>
// -target arm64-apple-macos15.0 weak.swift -o weak

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

#if true
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

final class Box: DynamicProperty {
    var n = 0
    func update() {
        n += 1
        let me = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        MainActor.assumeIsolated { Log.lines.append("update() self=0x\(String(me, radix: 16))") }
    }
}
@MainActor let weakBox = Box()
@MainActor let strongBox = Box()
struct WeakView: View {
    weak var w: Box? = weakBox
    var body: some View {
        Log.lines.append("weak body n=\(w?.n ?? -1)")
        return Text("x")
    }
}
struct StrongOptView: View {
    var s: Box? = strongBox
    var body: some View {
        Log.lines.append("strong-optional body n=\(s?.n ?? -1)")
        return Text("x")
    }
}
@MainActor func run() {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        Log.lines = []
    }
    print("weakBox   =0x\(String(UInt(bitPattern: Unmanaged.passUnretained(weakBox).toOpaque()), radix: 16))")
    print("strongBox =0x\(String(UInt(bitPattern: Unmanaged.passUnretained(strongBox).toOpaque()), radix: 16))")
    _ = host(StrongOptView()); spin(); report("strong Optional<Box> field, Optional conforming")
    _ = host(WeakView()); spin(); report("weak Box? field, Optional conforming")
    print("weakBox.n=\(weakBox.n) strongBox.n=\(strongBox.n)")
}
MainActor.assumeIsolated { run() }
