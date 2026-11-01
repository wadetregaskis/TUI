import SwiftUI
import AppKit
import Observation

// When does SwiftUI run a plain child's body again? A key press writes state
// either in a sibling leaf or in the parent whose body builds the children, and
// each child counts its body runs. One child per kind of stored field, so what
// SwiftUI compares and what it treats as changed can be read off the counts.
// macOS 15, offscreen.

@MainActor enum Log {
    static var runs: [String: Int] = [:]
    static func note(_ tag: String) { runs[tag, default: 0] += 1 }
    static func take() -> [String: Int] { defer { runs = [:] }; return runs }
}
@MainActor var leafWrite: (() -> Void)?
@MainActor var parentWrite: (() -> Void)?
@MainActor var modelTick = 0

struct Leaf: View {
    @State private var n = 0
    var body: some View {
        Log.note("leaf")
        leafWrite = { n += 1 }
        return Text("leaf \(n)")
    }
}

struct PodChild: View {
    let value: Int
    var body: some View { Log.note("pod Int field"); return Text("\(value)") }
}
struct ShortStringChild: View {
    let value: String
    var body: some View { Log.note("short String field"); return Text(value) }
}
struct LongStringChild: View {
    let value: String
    var body: some View { Log.note("long String field, built anew"); return Text(value) }
}
struct ArrayChild: View {
    let value: [Int]
    var body: some View { Log.note("Array field, built anew"); return Text("\(value.count)") }
}
final class Plain { var x = 0 }
struct ClassChild: View {
    let value: Plain
    var body: some View { Log.note("class field, same object"); return Text("\(value.x)") }
}
struct NewClassChild: View {
    let value: Plain
    var body: some View { Log.note("class field, new object each build"); return Text("\(value.x)") }
}
struct ClosureNoCaptureChild: View {
    let value: () -> Void
    var body: some View { Log.note("closure, no capture"); return Text("c") }
}
struct ClosureCaptureChild: View {
    let value: () -> Void
    var body: some View { Log.note("closure, captures a let"); return Text("c") }
}
struct ClosureCaptureStateChild: View {
    let value: () -> Void
    var body: some View { Log.note("closure, captures parent's state value"); return Text("c") }
}
struct ClosureEquatableChild: View, Equatable {
    let id: Int
    let value: () -> Void
    nonisolated static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    var body: some View { Log.note("closure, Equatable view (id only)"); return Text("c") }
}
struct BindingChild: View {
    @Binding var value: Int
    var body: some View { Log.note("Binding field, not read"); return Text("b") }
}
struct BindingReadChild: View {
    @Binding var value: Int
    var body: some View { Log.note("Binding field, read"); return Text("\(value)") }
}
struct StateChild: View {
    @State private var value = 0
    var body: some View { Log.note("own @State, unchanged"); return Text("\(value)") }
}
struct EnvChild: View {
    @Environment(\.isEnabled) private var value
    var body: some View { Log.note("@Environment, unchanged"); return Text("\(value)") }
}
@Observable final class Model { var a = 0; var b = 0 }
struct ObsChild: View {
    let model: Model
    var body: some View { Log.note("@Observable, property unchanged"); return Text("\(model.a)") }
}
struct AnyViewChild: View {
    let value: AnyView
    var body: some View { Log.note("AnyView field"); return Text("a") }
}
struct ExistentialChild: View {
    let value: any CustomStringConvertible
    var body: some View { Log.note("existential field, Int inside"); return Text("e") }
}
struct ViewBuilderChild<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { Log.note("ViewBuilder content field, Text"); return content }
}
struct PaddedChild: View {
    var body: some View { Log.note("no fields, under padding"); return Text("p") }
}

// The state in a leaf beside them: the parent's body has no reason to run.
struct LeafPage: View {
    let shared: Plain
    let model: Model
    @State private var bound = 0
    var body: some View {
        Log.note("page")
        return VStack {
            Leaf()
            Children(shared: shared, model: model, bound: $bound, tick: 0)
        }
    }
}

// The state in the parent, read by it, so its body runs and builds the children
// again. Nothing a child holds has a value that changed.
struct ParentPage: View {
    let shared: Plain
    let model: Model
    @State private var tick = 0
    @State private var bound = 0
    var body: some View {
        Log.note("page")
        parentWrite = { tick += 1 }
        return VStack {
            Text("tick \(tick)")
            Children(shared: shared, model: model, bound: $bound, tick: 0)
        }
    }
}

// The children, one level down, built in a body that runs when `ParentPage`'s
// does because its own values differ only in what it holds by address.
struct Children: View {
    let shared: Plain
    let model: Model
    @Binding var bound: Int
    let tick: Int

    var body: some View {
        Log.note("children")
        let captured = tick
        return VStack {
            PodChild(value: 1)
            ShortStringChild(value: "short")
            LongStringChild(value: String(repeating: "long string ", count: 4))
            ArrayChild(value: Array(1...3))
            ClassChild(value: shared)
            NewClassChild(value: Plain())
            ClosureNoCaptureChild(value: {})
            ClosureCaptureChild(value: { _ = captured })
            ClosureEquatableChild(id: 1, value: { _ = captured }).equatable()
            BindingChild(value: $bound)
            BindingReadChild(value: $bound)
            StateChild()
            EnvChild()
            ObsChild(model: model)
            AnyViewChild(value: AnyView(Text("x")))
            ExistentialChild(value: 3)
            ViewBuilderChild { Text("vb") }
            PaddedChild().padding(1)
        }
    }
}

// The same children built directly in the body that re-runs, with no `Children`
// between: a closure there captures the parent's state, as a row's action does.
struct DirectPage: View {
    let shared: Plain
    let model: Model
    @State private var tick = 0
    @State private var bound = 0
    var body: some View {
        Log.note("page")
        parentWrite = { tick += 1 }
        let local = 5
        return VStack {
            Text("tick \(tick)")
            PodChild(value: 1)
            ShortStringChild(value: "short")
            LongStringChild(value: String(repeating: "long string ", count: 4))
            ArrayChild(value: Array(1...3))
            ClassChild(value: shared)
            NewClassChild(value: Plain())
            ClosureNoCaptureChild(value: {})
            ClosureCaptureChild(value: { _ = local })
            ClosureCaptureStateChild(value: { [tick] in _ = tick })
            ClosureEquatableChild(id: 1, value: { _ = local }).equatable()
            BindingChild(value: $bound)
            BindingReadChild(value: $bound)
            StateChild()
            EnvChild()
            ObsChild(model: model)
            AnyViewChild(value: AnyView(Text("x")))
            ExistentialChild(value: 3)
            ViewBuilderChild { Text("vb") }
            PaddedChild().padding(1)
        }
    }
}

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 400, height: 800)
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

@MainActor func report(_ title: String, _ runs: [String: Int]) {
    print("--- \(title)")
    for (tag, count) in runs.sorted(by: { $0.key < $1.key }) { print("\(count)\t\(tag)") }
}

@MainActor func run() {
    let shared = Plain()
    let model = Model()

    let h1 = host(LeafPage(shared: shared, model: model))
    spin(); h1.layoutSubtreeIfNeeded(); spin()
    report("first draw, the state in a leaf", Log.take())
    leafWrite?()
    spin(0.5); h1.layoutSubtreeIfNeeded(); spin()
    report("after the leaf's write", Log.take())
    model.b = 9
    spin(0.5); h1.layoutSubtreeIfNeeded(); spin()
    report("after a write to an @Observable property nobody read", Log.take())

    let h2 = host(ParentPage(shared: shared, model: model))
    spin(); h2.layoutSubtreeIfNeeded(); spin()
    report("first draw, the state in the parent, a composite between", Log.take())
    parentWrite?()
    spin(0.5); h2.layoutSubtreeIfNeeded(); spin()
    report("after the parent's write, a composite between", Log.take())

    let h3 = host(DirectPage(shared: shared, model: model))
    spin(); h3.layoutSubtreeIfNeeded(); spin()
    report("first draw, children built directly in the writer's body", Log.take())
    parentWrite?()
    spin(0.5); h3.layoutSubtreeIfNeeded(); spin()
    report("after the write, children built directly in the writer's body", Log.take())
    for nth in ["second", "third", "fourth"] {
        parentWrite?()
        spin(0.5); h3.layoutSubtreeIfNeeded(); spin()
        report("after a \(nth) write, children built directly in the writer's body", Log.take())
    }
    exit(0)
}
MainActor.assumeIsolated { run() }
