import SwiftUI
import AppKit

// DYNV (2026-10-11): SwiftUI's behaviour for the suspects of lane DYNV's bug
// hunt that DYNP/optional/op.swift did not measure. Offscreen NSHostingView,
// as op.swift. Each case logs its body's reads; a poke writes through a
// binding a body handed out, then the run loop spins.
//
//   let      a property in a `let` field: does update()'s change reach body?
//   mirror   a view with a customMirror listing no wrapper: is its @State kept?
//   twice    one view value placed twice, under lineLimit 1 and 2: which one
//            does the first-handed binding write?
//   value    one DynamicProperty value handed to two children: which child
//            does child a's binding write?
//   unowned  a view holding an unowned object that has died, body never
//            reading it: does a state change re-run body without a crash?
//   cycle    class properties reaching each other: any crash?

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
    static var first: Binding<Int>?
}

@MainActor func line(_ tag: String, _ what: String) -> some View {
    Log.lines.append("\(tag): \(what)")
    return Text(what)
}

struct Counting: DynamicProperty {
    var count = 0
    mutating func update() { count += 1 }
}

// let
struct LetView: View {
    let p = Counting()
    var body: some View { line("let", "count=\(p.count)") }
}

// mirror
struct ReflectingCounter: View, CustomReflectable {
    @State var count = 0
    var body: some View {
        Log.bindings["mirror"] = $count
        return line("mirror", "count=\(count)")
    }
    nonisolated var customMirror: Mirror { Mirror(self, children: ["summary": "counter"]) }
}

// twice
struct PlainCounter: View {
    @State var count = 0
    @Environment(\.lineLimit) var limit
    var body: some View {
        if Log.first == nil { Log.first = $count }
        return line("twice", "limit=\(limit.map(String.init) ?? "nil") count=\(count)")
    }
}
struct SameTwice: View {
    var body: some View {
        let counter = PlainCounter()
        return VStack {
            counter.lineLimit(1)
            counter.lineLimit(2)
        }
    }
}

// value
struct KeptCount: DynamicProperty { @State var count = 0 }
struct ValueChild: View {
    let name: String
    let kept: KeptCount
    var body: some View {
        Log.bindings["value-\(name)"] = kept.$count
        return line("value", "\(name) count=\(kept.count)")
    }
}
struct TwoValues: View {
    var body: some View {
        let kept = KeptCount()
        return VStack {
            ValueChild(name: "a", kept: kept)
            ValueChild(name: "b", kept: kept)
        }
    }
}

// unowned
final class OwnerObject {
    deinit { print("   (OwnerObject deinit)") }
}
@MainActor var ownerStrong: OwnerObject? = OwnerObject()
struct UnownedChild: View {
    @State var x = 0
    unowned let owner: OwnerObject
    var body: some View {
        Log.bindings["unowned"] = $x
        return line("unowned", "x=\(x)")
    }
}
struct UnownedParent: View {
    var body: some View { UnownedChild(owner: ownerStrong!) }
}

// cycle
final class Coordinator: DynamicProperty {
    weak var parent: Coordinator?
    var child: Coordinator?
    func update() {}
}
@MainActor let cycleRoot: Coordinator = {
    let root = Coordinator(), child = Coordinator()
    root.child = child
    child.parent = root
    return root
}()
struct CycleView: View {
    @State var x = 0
    let coordinator = cycleRoot
    var body: some View {
        Log.bindings["cycle"] = $x
        return line("cycle", "x=\(x)")
    }
}

@MainActor func run() {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        Log.lines = []
    }
    func write(_ binding: Binding<Int>?, _ value: Int, _ what: String) {
        print("-- \(what) := \(value)\(binding == nil ? " (no binding)" : "")")
        binding?.wrappedValue = value
        spin(0.5)
    }
    print("#### let"); host(LetView()); spin(); report("first draw")
    print("#### mirror"); host(ReflectingCounter()); spin(); report("first draw")
    write(Log.bindings["mirror"], 3, "mirror count"); report("after")
    print("#### twice"); host(SameTwice()); spin(); report("first draw")
    write(Log.first, 5, "first-handed binding"); report("after")
    print("#### value"); host(TwoValues()); spin(); report("first draw")
    write(Log.bindings["value-a"], 5, "child a's kept"); report("after")
    print("#### unowned"); host(UnownedParent()); spin(); report("first draw")
    print("-- ownerStrong := nil"); ownerStrong = nil; spin()
    write(Log.bindings["unowned"], 1, "child's x"); report("after (owner dead)")
    print("#### cycle"); host(CycleView()); spin(); report("first draw")
    write(Log.bindings["cycle"], 1, "x"); report("after")
    print("DONE")
}

MainActor.assumeIsolated { run() }
