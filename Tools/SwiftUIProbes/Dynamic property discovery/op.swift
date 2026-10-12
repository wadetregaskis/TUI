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

// B1. A plain field (baseline).
struct PlainView: View {
    var p = Full(tag: "plain")
    @State var tick = 0
    var body: some View {
        registerPoke("plain", p.$kept, $tick)
        return line("plain", tick, p.summary)
    }
}

// B2. An optional field.
struct OptionalView: View {
    var p: Full? = Full(tag: "optional")
    @State var tick = 0
    var body: some View {
        registerPoke("optional", p?.$kept, $tick)
        return line("optional", tick, p?.summary ?? "nil")
    }
}

// (i) A plain struct field that does not conform to DynamicProperty.
struct Holder { var p: Full }
struct HolderView: View {
    var h = Holder(p: Full(tag: "holder"))
    @State var tick = 0
    var body: some View {
        registerPoke("holder", h.p.$kept, $tick)
        return line("holder", tick, h.p.summary)
    }
}

// (ii) The same, the holder conforming (control).
struct HolderDP: DynamicProperty { var p: Full }
struct HolderDPView: View {
    var h = HolderDP(p: Full(tag: "holderDP"))
    @State var tick = 0
    var body: some View {
        registerPoke("holderDP", h.p.$kept, $tick)
        return line("holderDP", tick, h.p.summary)
    }
}

// (iii) A field of a custom enum, not conforming; and one conforming.
enum E { case a(Full), b }
struct EnumFieldView: View {
    var e = E.a(Full(tag: "enumField"))
    @State var tick = 0
    var body: some View {
        guard case let .a(p) = e else { return line("enumField", tick, "b") }
        registerPoke("enumField", p.$kept, $tick)
        return line("enumField", tick, p.summary)
    }
}
enum EDP: DynamicProperty { case a(Full), b }
struct EnumDPFieldView: View {
    var e = EDP.a(Full(tag: "enumDPField"))
    @State var tick = 0
    var body: some View {
        guard case let .a(p) = e else { return line("enumDPField", tick, "b") }
        registerPoke("enumDPField", p.$kept, $tick)
        return line("enumDPField", tick, p.summary)
    }
}

// (iv) A tuple field and an array field.
struct TupleView2: View {
    var t: (Full, Int) = (Full(tag: "tuple"), 1)
    @State var tick = 0
    var body: some View {
        registerPoke("tuple", t.0.$kept, $tick)
        return line("tuple", tick, t.0.summary)
    }
}
struct ArrayView: View {
    var a: [Full] = [Full(tag: "array")]
    @State var tick = 0
    var body: some View {
        registerPoke("array", a[0].$kept, $tick)
        return line("array", tick, a[0].summary)
    }
}

// (vi) An optional field nil at first draw, then holding a property.
struct FlipChild: View {
    var p: Full?
    @State var tick = 0
    var body: some View {
        registerPoke("flip", p?.$kept, $tick)
        return line("flip", tick, p?.summary ?? "nil")
    }
}
struct FlipParent: View {
    @State var on = false
    var body: some View {
        let _ = { Log.pokes["flip-on"] = { on = true } }()
        return FlipChild(p: on ? Full(tag: "flip") : nil)
    }
}

// (vii-a) Existential fields.
struct ExistentialView: View {
    var p: any DynamicProperty = Full(tag: "existential")
    @State var tick = 0
    var body: some View {
        let f = p as! Full
        registerPoke("existential", f.$kept, $tick)
        return line("existential", tick, f.summary)
    }
}
struct AnyFieldView: View {
    var p: Any = Full(tag: "anyField")
    @State var tick = 0
    var body: some View {
        let f = p as! Full
        registerPoke("anyField", f.$kept, $tick)
        return line("anyField", tick, f.summary)
    }
}

// (vii-b) A generic field whose type argument is the property.
struct GenericView<T>: View {
    var t: T
    @State var tick = 0
    var body: some View {
        let f = t as! Full
        registerPoke("generic", f.$kept, $tick)
        return line("generic", tick, f.summary)
    }
}

// (vii-c) A ViewModifier stored in a view's field: not applied, and applied.
struct FullModifier: ViewModifier {
    var p: Full
    func body(content: Content) -> some View {
        Log.lines.append("modifier body p: \(p.summary)")
        // Not `content` alone: SwiftUI 6.5.4 runs neither the body nor the
        // properties' update() of a modifier whose body returns its content
        // unchanged (measured, scratch probe 2026-10-10).
        return content.padding(1)
    }
}
struct ModifierStoredView: View {
    var m = FullModifier(p: Full(tag: "modStored"))
    @State var tick = 0
    var body: some View {
        registerPoke("modStored", m.p.$kept, $tick)
        return line("modStored", tick, m.p.summary)
    }
}
struct ModifierAppliedView: View {
    var m = FullModifier(p: Full(tag: "modApplied"))
    @State var tick = 0
    var body: some View {
        registerPoke("modApplied", m.p.$kept, $tick)
        return line("modApplied", tick, m.p.summary).modifier(m)
    }
}

// (vii-d) A Binding held plainly and in an optional, by children of a parent
// whose body does not read the state: which child's body runs on a change?
struct BindingChild: View {
    var b: Binding<Int>
    var body: some View {
        Log.lines.append("binding child body b=\(b.wrappedValue)")
        return Text("\(b.wrappedValue)")
    }
}
struct OptionalBindingChild: View {
    var b: Binding<Int>?
    var body: some View {
        Log.lines.append("optional-binding child body b=\(String(describing: b?.wrappedValue))")
        return Text("\(b?.wrappedValue ?? -1)")
    }
}
struct BindingParent: View {
    @State var value = 1
    var body: some View {
        let binding = $value
        let _ = { Log.pokes["binding"] = { binding.wrappedValue = 2 } }()
        Log.lines.append("binding parent body")
        return VStack { BindingChild(b: binding); OptionalBindingChild(b: binding) }
    }
}

// (vii-f) A class property, held strongly, holding @Environment and @State.
// update() runs on it (dp.swift case 4); are the properties inside it given
// their values? `count` is the instance's, so it counts every update().
final class FullBox: DynamicProperty {
    var count = 0
    @Environment(\.lineLimit) var limit
    @State var kept = 5
    func update() {
        count += 1
        MainActor.assumeIsolated { Log.updates["classProp", default: 0] += 1 }
    }
    var summary: String { "count=\(count) limit=\(String(describing: limit)) kept=\(kept)" }
}
@MainActor let fullBox = FullBox()
struct ClassPropView: View {
    let p: FullBox = fullBox
    @State var tick = 0
    var body: some View {
        registerPoke("classProp", p.$kept, $tick)
        return line("classProp", tick, p.summary)
    }
}

#if OPTCONF
// (vii-e, OPTCONF only) A weak field of a class property: with Optional
// conforming, its type Optional<Box> now passes the conformance check.
final class Box: DynamicProperty {
    var n = 0
    func update() { n += 1; MainActor.assumeIsolated { Log.updates["weakClass", default: 0] += 1 } }
}
@MainActor let weakBox = Box()
struct WeakView: View {
    weak var w: Box? = weakBox
    var body: some View {
        Log.lines.append("weak body n=\(w?.n ?? -1)")
        return Text("x")
    }
}
#endif

@MainActor func run() {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        print("   updates: \(Log.updates.sorted { $0.key < $1.key })")
        Log.lines = []; Log.updates = [:]
    }
    func poke(_ name: String) {
        print("-- poke \(name)")
        Log.pokes[name]?()
        spin(0.5)
    }
    func measure<V: View>(_ name: String, _ title: String, _ view: V) {
        print("#### \(name)")
        _ = host(view.lineLimit(3)); spin(); report("\(title): first draw")
        poke(name); report("\(title): after poke (kept := 9, tick += 1)")
    }
    #if OPTCONF
    print("BUILD: OPTCONF (Optional: DynamicProperty where Wrapped: DynamicProperty)")
    #else
    print("BUILD: plain")
    #endif
    measure("plain", "B1 plain field", PlainView())
    measure("optional", "B2 optional field", OptionalView())
    measure("holder", "(i) non-DP struct field", HolderView())
    measure("holderDP", "(ii) DP struct field", HolderDPView())
    measure("enumField", "(iii) non-DP enum field", EnumFieldView())
    measure("enumDPField", "(iii-b) DP enum field", EnumDPFieldView())
    measure("tuple", "(iv) tuple field", TupleView2())
    measure("array", "(iv-b) array field", ArrayView())
    measure("existential", "(vii-a) any DynamicProperty field", ExistentialView())
    measure("anyField", "(vii-a2) Any field", AnyFieldView())
    measure("generic", "(vii-b) generic field T = Full", GenericView(t: Full(tag: "generic")))
    measure("modStored", "(vii-c) ViewModifier field, not applied", ModifierStoredView())
    measure("modApplied", "(vii-c2) ViewModifier field, applied", ModifierAppliedView())
    measure("classProp", "(vii-f) class property held strongly", ClassPropView())

    print("#### flip")
    _ = host(FlipParent().lineLimit(3)); spin(); report("(vi) optional nil at first draw")
    poke("flip-on"); report("(vi) after nil -> some")
    poke("flip"); report("(vi) after poke (kept := 9, tick += 1)")

    print("#### binding")
    _ = host(BindingParent()); spin(); report("(vii-d) Binding children: first draw")
    poke("binding"); report("(vii-d) after value := 2")

    #if OPTCONF
    print("#### weak")
    _ = host(WeakView()); spin(); report("(vii-e) weak class field under OPTCONF")
    #endif
    print("DONE")
}

MainActor.assumeIsolated { run() }
