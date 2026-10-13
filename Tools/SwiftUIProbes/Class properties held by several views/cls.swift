import SwiftUI
import AppKit
import Observation

// DYNVCLAIM (2026-10-12), angle "swiftui-first": what SwiftUI does with a
// CLASS DynamicProperty holding @State, a nested struct property holding
// @State, and @Environment, when one object is held by several views at once,
// by a view swapped by if/else, by ViewThatFits candidates, by ForEach rows
// that are removed, and by a child of a view that keeps the object in @State.
// macOS 15 SDK, offscreen NSHostingView, as DYNP/optional/op.swift.
// Run one case per process: ./cls CASE

setvbuf(stdout, nil, _IONBF, 0)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, width: CGFloat = 300) {
    let size = CGSize(width: width, height: 200)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor enum Log {
    static var lines: [String] = []
    static var bindings: [String: Binding<Int>] = [:]
    static var pokes: [String: () -> Void] = [:]
    static func report(_ title: String) {
        print("== \(title)")
        for l in lines { print("   \(l)") }
        lines = []
    }
}

private struct Accent: EnvironmentKey { static let defaultValue = "default" }
extension EnvironmentValues {
    var accent: String {
        get { self[Accent.self] }
        set { self[Accent.self] = newValue }
    }
}

@Observable final class Model { var name = "model" }

struct Inner: DynamicProperty {
    @State var m = 0
}

final class Obj: DynamicProperty {
    let tag: String
    @State var n = 0
    @Environment(\.accent) var accent
    var inner = Inner()
    var updates = 0
    init(tag: String) { self.tag = tag }
    func update() {
        updates += 1
        MainActor.assumeIsolated { Log.lines.append("  update \(tag) #\(updates)") }
    }
    var summary: String { "n=\(n) inner.m=\(inner.m) accent=\(accent) updates=\(updates)" }
}

struct Holder: View {
    let name: String
    let obj: Obj
    var body: some View {
        Log.lines.append("body \(name): \(obj.summary)")
        Log.bindings[name] = obj.$n
        Log.bindings[name + ".inner"] = obj.inner.$m
        let obj = obj
        Log.pokes[name + ".read"] = { Log.lines.append("closure \(name) reads accent=\(obj.accent) n=\(obj.n)") }
        return Text("\(name) \(obj.n)")
    }
}

// two: one object, two holders under different environments; then a write
// through a's binding; then a parent tick with the holders' inputs unchanged.
struct Two: View {
    let obj: Obj
    @State var tick = 0
    var body: some View {
        Log.lines.append("parent body tick=\(tick)")
        Log.pokes["tick"] = { tick += 1 }
        return VStack {
            Holder(name: "a", obj: obj).environment(\.accent, "red")
            Holder(name: "b", obj: obj).environment(\.accent, "blue")
            Text("\(tick)")
        }
    }
}

// swap: if/else swaps the holder.
struct Swap: View {
    let obj: Obj
    @State var flag = true
    var body: some View {
        Log.pokes["flip"] = { flag.toggle() }
        return Group {
            if flag { Holder(name: "first", obj: obj) } else { Holder(name: "second", obj: obj) }
        }
    }
}

// vtf: ViewThatFits whose candidates both hold the object.
struct Wide: View {
    let obj: Obj
    var body: some View {
        Log.lines.append("body wide: \(obj.summary)")
        return Text("wide wide wide wide wide wide wide wide wide wide wide wide wide wide wide").fixedSize()
    }
}
struct Narrow: View {
    let obj: Obj
    var body: some View {
        Log.lines.append("body narrow: \(obj.summary)")
        return Text("n")
    }
}
struct Fits: View {
    let obj: Obj
    var body: some View {
        ViewThatFits { Wide(obj: obj); Narrow(obj: obj) }
    }
}

// rows: ForEach rows each holding the object; a row is removed.
struct Rows: View {
    let obj: Obj
    @State var ids = [1, 2, 3]
    var body: some View {
        Log.pokes["remove"] = { ids.removeFirst() }
        return VStack { ForEach(ids, id: \.self) { Holder(name: "row\($0)", obj: obj) } }
    }
}

// held: the parent keeps the object in @State and hands it to a child.
struct Held: View {
    @State private var obj = Obj(tag: "held")
    @State var tick = 0
    var body: some View {
        Log.lines.append("held parent body tick=\(tick): \(obj.summary)")
        Log.pokes["tick"] = { tick += 1 }
        return VStack { Holder(name: "child", obj: obj); Text("\(tick)") }
    }
}

// envModel: an @Environment(Model.self) inside a class property, read in body.
final class ModelObj: DynamicProperty {
    @Environment(Model.self) var model
}
struct ModelHolder: View {
    let obj: ModelObj
    var body: some View {
        Log.lines.append("model holder body: about to read")
        let name = obj.model.name
        Log.lines.append("model holder read \(name)")
        return Text(name)
    }
}

// perValue: an object made anew with each value of its view (DYNV2 4.11).
final class Pager: DynamicProperty {
    @State var page = 0
    init() { MainActor.assumeIsolated { Log.lines.append("  Pager init") } }
}
struct PerValue: View {
    let pager = Pager()
    var body: some View {
        Log.lines.append("perValue body page=\(pager.page)")
        Log.bindings["page"] = pager.$page
        return Text("\(pager.page)")
    }
}
struct PerValueParent: View {
    @State var tick = 0
    var body: some View {
        Log.pokes["tick"] = { tick += 1 }
        return VStack { PerValue(); Text("\(tick)") }
    }
}

@MainActor func run(_ which: String) {
    switch which {
    case "two":
        let obj = Obj(tag: "shared")
        host(Two(obj: obj)); spin(); Log.report("two: first draw")
        Log.pokes["a.read"]?(); Log.pokes["b.read"]?(); Log.report("two: closures after first draw")
        Log.bindings["a"]?.wrappedValue = 5; Log.bindings["a.inner"]?.wrappedValue = 6
        spin(0.5); Log.report("two: after a.$n := 5, a.inner.$m := 6")
        Log.lines.append("direct read n=\(obj.n) inner.m=\(obj.inner.m)"); Log.report("two: direct")
        Log.pokes["tick"]?(); spin(0.5); Log.report("two: after parent tick (holders' inputs unchanged)")
    case "swap":
        let obj = Obj(tag: "swap")
        host(Swap(obj: obj)); spin(); Log.report("swap: first draw")
        Log.bindings["first"]?.wrappedValue = 4; spin(0.5); Log.report("swap: after first.$n := 4")
        Log.pokes["flip"]?(); spin(0.5); Log.report("swap: after flip")
    case "vtf":
        let obj = Obj(tag: "vtf")
        host(Fits(obj: obj), width: 120); spin(); Log.report("vtf: narrow window first draw")
    case "rows":
        let obj = Obj(tag: "rows")
        host(Rows(obj: obj)); spin(); Log.report("rows: first draw")
        Log.pokes["remove"]?(); spin(0.5); Log.report("rows: after removing row1")
    case "held":
        host(Held()); spin(); Log.report("held: first draw")
        Log.bindings["child"]?.wrappedValue = 3; spin(0.5); Log.report("held: after child.$n := 3")
        Log.pokes["tick"]?(); spin(0.5); Log.report("held: after parent tick")
    case "perValue":
        host(PerValueParent()); spin(); Log.report("perValue: first draw")
        Log.bindings["page"]?.wrappedValue = 5; spin(0.5); Log.report("perValue: after page := 5")
        Log.pokes["tick"]?(); spin(0.5); Log.report("perValue: after parent tick")
    case "envModel":
        host(ModelHolder(obj: ModelObj()).environment(Model())); spin(); Log.report("envModel: first draw")
    default:
        print("unknown case \(which)")
    }
}

MainActor.assumeIsolated { run(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "two") }
print("DONE")
