import SwiftUI
import AppKit
import Observation

// DYNVCLAIM / object-owned: SwiftUI's reference model for "state belongs to
// the object, its readers are its dependents" — an @Observable shared by two
// views, one of them behind an .equatable() that always compares equal (a
// view SwiftUI will not re-evaluate for its inputs). Does a write redraw both?
// And a class DynamicProperty shared by two views: how often does update()
// run, and does a @State write through it redraw either? macOS 15, offscreen.

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
@MainActor final class Log { static var lines: [String] = []; static var updates = 0 }

@Observable final class Shared { var n = 0 }

struct Reader: View, Equatable {
    let name: String
    let model: Shared
    nonisolated static func == (a: Self, b: Self) -> Bool { true }
    var body: some View {
        Log.lines.append("\(name) \(model.n)")
        return Text("\(name) \(model.n)")
    }
}
struct Pair: View {
    let model: Shared
    var body: some View {
        VStack {
            Reader(name: "a", model: model).equatable()
            Reader(name: "b", model: model)
        }
    }
}

final class ClassProp: DynamicProperty {
    @State var count = 0
    func update() { MainActor.assumeIsolated { Log.updates += 1 } }
}
@MainActor var bindings: [String: Binding<Int>] = [:]
struct Holder: View {
    let name: String
    let prop: ClassProp
    var body: some View {
        bindings[name] = prop.$count
        Log.lines.append("\(name) \(prop.count)")
        return Text("\(name) \(prop.count)")
    }
}
struct Holders: View {
    let prop: ClassProp
    var body: some View { VStack { Holder(name: "a", prop: prop); Holder(name: "b", prop: prop) } }
}

@MainActor func run() {
    let model = Shared()
    let h = host(Pair(model: model))
    spin(); h.layoutSubtreeIfNeeded()
    print("observable first draw:", Log.lines)
    Log.lines.removeAll()
    model.n = 9
    spin(0.5); h.layoutSubtreeIfNeeded(); spin(0.3)
    print("observable after write (equatable a, plain b):", Log.lines)

    Log.lines.removeAll()
    let prop = ClassProp()
    let h2 = host(Holders(prop: prop))
    spin(); h2.layoutSubtreeIfNeeded()
    print("class property first draw:", Log.lines, "updates:", Log.updates)
    Log.lines.removeAll(); Log.updates = 0
    bindings["a"]?.wrappedValue = 5
    spin(0.5); h2.layoutSubtreeIfNeeded(); spin(0.3)
    print("class property after a's binding := 5:", Log.lines, "updates:", Log.updates,
          "read now:", prop.count)
    exit(0)
}
MainActor.assumeIsolated { run() }
