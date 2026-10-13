import SwiftUI
import AppKit

// DYNV revision (2026-10-11): SwiftUI's behaviour for the suspects the
// critic named that dv.swift did not measure. Offscreen NSHostingView, as
// dv.swift. Run as `./dv2 main` and `./dv2 deadfirst` (the second may trap).
//
//   txn        a modifier holding an app property, wrapped by
//              ViewModifier.transaction(_:): how many update()s does its
//              body see?
//   concat     the same modifier joined to another by .concat(_:)
//   subclass   a view field declared as a plain class, holding a subclass
//              that is a DynamicProperty: is update() called? (control: the
//              same object in a field declared as the subclass)
//   unownedprop  an unowned field whose type is a class DynamicProperty,
//              whose object dies after the first draw; then a state change
//              re-runs body. Does SwiftUI call update() on it, or trap?
//   deadfirst  the same, but the object dies before the view is first hosted

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

@MainActor enum Log {
    static var lines: [String] = []
    static var bindings: [String: Binding<Int>] = [:]
    static var updates: [String: Int] = [:]
}

@MainActor func line(_ tag: String, _ what: String) -> some View {
    Log.lines.append("\(tag): \(what)")
    return Text(what)
}

struct Counting: DynamicProperty {
    var count = 0
    mutating func update() { count += 1 }
}

// txn, concat
struct ShowCount: ViewModifier {
    let tag: String
    var counting = Counting()
    func body(content: Content) -> some View {
        HStack { content; line(tag, "count=\(counting.count)") }
    }
}
struct Plain: ViewModifier {
    func body(content: Content) -> some View { content }
}
struct TxnView: View {
    var body: some View { Text("x").modifier(ShowCount(tag: "txn").transaction { _ in }) }
}
struct ConcatView: View {
    var body: some View { Text("x").modifier(ShowCount(tag: "concat").concat(Plain())) }
}
struct DirectView: View {
    var body: some View { Text("x").modifier(ShowCount(tag: "direct")) }
}

// subclass
class PlainBase {}
final class CountingSubclass: PlainBase, DynamicProperty {
    var count = 0
    func update() {
        count += 1
        MainActor.assumeIsolated { Log.updates["subclass", default: 0] += 1 }
    }
}
struct BaseFieldView: View {
    let object: PlainBase
    var body: some View { line("subclass-as-base", "count=\((object as? CountingSubclass)?.count ?? -1)") }
}
struct SubFieldView: View {
    let object: CountingSubclass
    var body: some View { line("subclass-as-sub", "count=\(object.count)") }
}

// unownedprop
final class ClassProp: DynamicProperty {
    var count = 0
    func update() {
        count += 1
        MainActor.assumeIsolated { Log.updates["unownedprop", default: 0] += 1 }
    }
    deinit { print("   (ClassProp deinit)") }
}
@MainActor var propStrong: ClassProp? = ClassProp()
struct UnownedPropView: View {
    @State var x = 0
    unowned let p: ClassProp
    var body: some View {
        Log.bindings["unownedprop"] = $x
        return line("unownedprop", "x=\(x)")
    }
}
struct UnownedPropParent: View {
    var body: some View { UnownedPropView(p: propStrong!) }
}

@MainActor func run(_ mode: String) {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        print("   updates: \(Log.updates.sorted { $0.key < $1.key })")
        Log.lines = []
        Log.updates = [:]
    }
    func write(_ binding: Binding<Int>?, _ value: Int, _ what: String) {
        print("-- \(what) := \(value)\(binding == nil ? " (no binding)" : "")")
        binding?.wrappedValue = value
        spin(0.5)
    }
    if mode == "main" {
        print("#### direct"); host(DirectView()); spin(); report("first draw")
        print("#### txn"); host(TxnView()); spin(); report("first draw")
        print("#### concat"); host(ConcatView()); spin(); report("first draw")
        print("#### subclass (field declared PlainBase)"); host(BaseFieldView(object: CountingSubclass())); spin(); report("first draw")
        print("#### subclass (field declared CountingSubclass)"); host(SubFieldView(object: CountingSubclass())); spin(); report("first draw")
        print("#### unownedprop"); host(UnownedPropParent()); spin(); report("first draw")
        print("-- propStrong := nil"); propStrong = nil; spin()
        write(Log.bindings["unownedprop"], 1, "x"); report("after (object dead)")
    } else {
        print("#### deadfirst")
        let view = UnownedPropView(p: propStrong!)
        print("-- propStrong := nil"); propStrong = nil
        host(view); spin(); report("first draw (object dead)")
    }
    print("DONE")
}

MainActor.assumeIsolated { run(CommandLine.arguments.dropFirst().first ?? "main") }
