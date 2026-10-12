import SwiftUI
import AppKit

// Lane SKEY (2026-10-11): what SwiftUI does with the @State inside an enum
// view's cases, an enum property's cases, a multi-value payload, and (under
// -D OPTCONF) an optional property going nil and back. Offscreen
// NSHostingView, as ../Dynamic property discovery/op.swift. Each probe prints what the body
// reads; pokes write through `$state` bindings the bodies hand out.

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
    static var bindings: [String: Binding<Int>] = [:]
    static func flush(_ title: String) {
        print("== \(title)")
        for l in lines { print("   \(l)") }
        lines = []
    }
}

#if OPTCONF
extension Optional: @retroactive DynamicProperty where Wrapped: DynamicProperty {}
#endif

@MainActor func say(_ s: String) -> Text { Log.lines.append(s); return Text(s) }

struct One: DynamicProperty {
    @State var kept = 5
}
struct Two: DynamicProperty {
    @State var first = 1
    @State var second = 2
}

// E1. An enum view whose cases hold different properties.
enum Screen: View {
    case a(One)
    case b(Two)
    var body: some View {
        switch self {
        case .a(let one):
            Log.bindings["a.kept"] = one.$kept
            return say("a kept=\(one.kept)")
        case .b(let two):
            Log.bindings["b.first"] = two.$first
            return say("b first=\(two.first) second=\(two.second)")
        }
    }
}
// E1b. An enum view whose two cases hold the same property type.
enum Same: View {
    case a(One)
    case b(One)
    var body: some View {
        switch self {
        case .a(let one):
            Log.bindings["sa.kept"] = one.$kept
            return say("same.a kept=\(one.kept)")
        case .b(let one):
            Log.bindings["sb.kept"] = one.$kept
            return say("same.b kept=\(one.kept)")
        }
    }
}
// E5. An enum view whose case stays, its payload's other value changing.
enum Tagged: View {
    case a(One, Int)
    var body: some View {
        switch self {
        case let .a(one, n):
            Log.bindings["t.kept"] = one.$kept
            return say("tagged n=\(n) kept=\(one.kept)")
        }
    }
}
// E2. An enum property in a struct view.
enum EDP: DynamicProperty {
    case a(One)
    case b(Two)
    var summary: String {
        switch self {
        case .a(let one): "a kept=\(one.kept)"
        case .b(let two): "b first=\(two.first) second=\(two.second)"
        }
    }
    @MainActor func publish() {
        switch self {
        case .a(let one): Log.bindings["edp.a.kept"] = one.$kept
        case .b(let two): Log.bindings["edp.b.first"] = two.$first
        }
    }
}
struct EDPView: View {
    let p: EDP
    @State var own = 0
    var body: some View {
        p.publish()
        Log.bindings["edp.own"] = $own
        return say("edp \(p.summary) own=\(own)")
    }
}
// E4. An optional property (meaningful under OPTCONF).
struct OptView: View {
    let p: One?
    @State var own = 0
    var body: some View {
        if let p { Log.bindings["opt.kept"] = p.$kept }
        Log.bindings["opt.own"] = $own
        return say("opt kept=\(p.map { String($0.kept) } ?? "nil") own=\(own)")
    }
}

@MainActor final class Driver: ObservableObject {
    @Published var which = 0
    @Published var n = 0
}

// The same Screen at one position in the parent, its case chosen by value.
struct RootValue: View {
    @ObservedObject var d: Driver
    var body: some View {
        d.which == 0 ? Screen.a(One()) : Screen.b(Two())
    }
}
struct RootSame: View {
    @ObservedObject var d: Driver
    var body: some View { d.which == 0 ? Same.a(One()) : Same.b(One()) }
}
struct RootTagged: View {
    @ObservedObject var d: Driver
    var body: some View { Tagged.a(One(), d.n) }
}
struct RootEDP: View {
    @ObservedObject var d: Driver
    var body: some View { EDPView(p: d.which == 0 ? .a(One()) : .b(Two())) }
}
struct RootOpt: View {
    @ObservedObject var d: Driver
    var body: some View { OptView(p: d.which == 0 ? One() : nil) }
}

@MainActor func run() {
    #if OPTCONF
    print("BUILD: OPTCONF")
    #else
    print("BUILD: plain")
    #endif
    func set(_ key: String, _ v: Int) {
        print("-- \(key) := \(v)")
        Log.bindings[key]?.wrappedValue = v
        spin()
    }

    print("#### E1 enum view, cases One / Two, chosen by value at one position")
    let d1 = Driver()
    _ = host(RootValue(d: d1)); spin(); Log.flush("first draw (a)")
    set("a.kept", 9); Log.flush("a.kept := 9")
    d1.which = 1; spin(); Log.flush("a -> b")
    set("b.first", 7); Log.flush("b.first := 7")
    d1.which = 0; spin(); Log.flush("b -> a (does a.kept come back 9, or reset to 5?)")
    d1.which = 1; spin(); Log.flush("a -> b (does b.first come back 7, or reset to 1?)")

    print("#### E1b enum view, cases a(One) / b(One)")
    let d2 = Driver()
    _ = host(RootSame(d: d2)); spin(); Log.flush("first draw (a)")
    set("sa.kept", 9); Log.flush("sa.kept := 9")
    d2.which = 1; spin(); Log.flush("a -> b (does b inherit 9?)")
    d2.which = 0; spin(); Log.flush("b -> a")

    print("#### E5 enum view, same case, payload's Int changing")
    let d3 = Driver()
    _ = host(RootTagged(d: d3)); spin(); Log.flush("first draw")
    set("t.kept", 9); Log.flush("t.kept := 9 (installed from a two-value payload?)")
    d3.n = 1; spin(); Log.flush("n := 1, same case")

    print("#### E2 enum property in a struct view")
    let d4 = Driver()
    _ = host(RootEDP(d: d4)); spin(); Log.flush("first draw (a)")
    set("edp.a.kept", 9); Log.flush("edp.a.kept := 9")
    set("edp.own", 3); Log.flush("edp.own := 3")
    d4.which = 1; spin(); Log.flush("a -> b")
    set("edp.b.first", 7); Log.flush("edp.b.first := 7")
    d4.which = 0; spin(); Log.flush("b -> a (a.kept 9 or 5? own 3?)")

    print("#### E4 optional property: some -> nil -> some")
    let d5 = Driver()
    _ = host(RootOpt(d: d5)); spin(); Log.flush("first draw (some)")
    set("opt.kept", 9); Log.flush("opt.kept := 9")
    set("opt.own", 3); Log.flush("opt.own := 3")
    d5.which = 1; spin(); Log.flush("some -> nil")
    d5.which = 0; spin(); Log.flush("nil -> some (kept 9 or 5? own 3?)")
    print("DONE")
}

MainActor.assumeIsolated { run() }
