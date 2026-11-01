// Probe: how SwiftUI splits one turn's changes into updates, by transaction, for what txn.swift
// left open: @State as well as @Observable; two withAnimation scopes in a row, the same or not;
// a scope nested in a scope; an Animatable value per change; onChange; completions; several
// bodies; a write made while a body is being evaluated.
//
// Top-level code, built alone:
//   xcrun swiftc -target arm64-apple-macos15.0 txn2.swift -o "$TMPDIR/txn2" && "$TMPDIR/txn2" | diff txn2.out -
import AppKit
import Observation
import SwiftUI

@Observable final class Model { var a = 0; var b = 0; var c = 0 }
final class Log { var seen: [String] = []; func note(_ s: String) { seen.append(s) } }

func describe(_ t: Transaction) -> String {
    guard let animation = t.animation else { return "plain" }
    return "\(animation)".contains("0.25") || "\(animation)".contains("duration: 2") ? "T2" : "T1"
}

let t1 = Animation.linear(duration: 1)
let t2 = Animation.linear(duration: 2)

// MARK: One body, reading observed values.

struct Observed: View {
    let model: Model
    let log: Log
    var body: some View {
        Text("\(model.a) \(model.b) \(model.c)")
            .transaction { t in log.note("a=\(model.a) b=\(model.b) c=\(model.c) \(describe(t))") }
    }
}

@MainActor func observed(_ name: String, _ change: (Model, Log) -> Void) {
    let model = Model()
    let log = Log()
    let host = NSHostingView(rootView: Observed(model: model, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    log.seen.removeAll()
    change(model, log)
    log.note("-- turn ends --")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    print("observed |", name, log.seen)
}

// MARK: One body, reading @State, driven by a closure the body hands out.

final class StateHandle { var write: ((Int, Int) -> Void)?; var read: (() -> (Int, Int))? }

struct Stated: View {
    @State private var a = 0
    @State private var b = 0
    let handle: StateHandle
    let log: Log
    var body: some View {
        let setA = $a
        let setB = $b
        handle.write = { which, value in if which == 0 { setA.wrappedValue = value } else { setB.wrappedValue = value } }
        handle.read = { (setA.wrappedValue, setB.wrappedValue) }
        log.note("body a=\(a) b=\(b)")
        return Text("\(a) \(b)")
            .transaction { t in log.note("a=\(setA.wrappedValue) b=\(setB.wrappedValue) \(describe(t))") }
    }
}

@MainActor func stated(_ name: String, _ change: (StateHandle, Log) -> Void) {
    let handle = StateHandle()
    let log = Log()
    let host = NSHostingView(rootView: Stated(handle: handle, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    log.seen.removeAll()
    change(handle, log)
    log.note("-- turn ends --")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    print("state    |", name, log.seen)
}

// MARK: One body, two animatable values: does each animate under its own change's transaction?

struct Mark: ViewModifier, Animatable {
    var value: Double
    let name: String
    let log: Log
    var animatableData: Double {
        get { value }
        set {
            value = newValue
            log.note("\(name)=\(newValue == newValue.rounded() ? String(Int(newValue)) : "between")")
        }
    }
    func body(content: Content) -> some View { content }
}

struct TwoValues: View {
    let model: Model
    let log: Log
    var body: some View {
        Text("x")
            .modifier(Mark(value: Double(model.a), name: "a", log: log))
            .modifier(Mark(value: Double(model.b), name: "b", log: log))
    }
}

@MainActor func animatable(_ name: String, _ change: (Model) -> Void) {
    let model = Model()
    let log = Log()
    let host = NSHostingView(rootView: TwoValues(model: model, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    log.seen.removeAll()
    change(model)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    var a = Set<String>(), b = Set<String>()
    for entry in log.seen { if entry.hasPrefix("a=") { a.insert(entry) } else { b.insert(entry) } }
    print("values   |", name, "a:", a.sorted(), "b:", b.sorted())
    window.orderOut(nil)
}

// MARK: Two bodies, each reading one value.

struct OneReader: View {
    let read: () -> Int
    let name: String
    let log: Log
    var body: some View {
        Text("\(read())").transaction { t in log.note("\(name)=\(read()) \(describe(t))") }
    }
}

struct TwoBodies: View {
    let model: Model
    let log: Log
    var body: some View {
        VStack {
            OneReader(read: { model.a }, name: "a", log: log)
            OneReader(read: { model.b }, name: "b", log: log)
        }
    }
}

@MainActor func bodies(_ name: String, _ change: (Model) -> Void) {
    let model = Model()
    let log = Log()
    let host = NSHostingView(rootView: TwoBodies(model: model, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    log.seen.removeAll()
    change(model)
    log.note("-- turn ends --")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    print("bodies   |", name, log.seen)
}

// MARK: onChange of each value, and a completion, in order.

struct Changes: View {
    let model: Model
    let log: Log
    var body: some View {
        Text("\(model.a) \(model.b)")
            .onChange(of: model.a) { log.note("onChange a -> \(model.a) (b=\(model.b))") }
            .onChange(of: model.b) { log.note("onChange b -> \(model.b) (a=\(model.a))") }
    }
}

@MainActor func changes(_ name: String, _ change: (Model, Log) -> Void) {
    let model = Model()
    let log = Log()
    let host = NSHostingView(rootView: Changes(model: model, log: log))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    log.seen.removeAll()
    change(model, log)
    log.note("-- turn ends --")
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    print("changes  |", name, log.seen)
    window.orderOut(nil)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared

    observed("two scopes, same animation:") { m, _ in
        withAnimation(t1) { m.a += 1 }
        withAnimation(t1) { m.b += 1 }
    }
    observed("two scopes, different animations:") { m, _ in
        withAnimation(t1) { m.a += 1 }
        withAnimation(t2) { m.b += 1 }
    }
    observed("three writes in one scope:") { m, _ in
        withAnimation(t1) { m.a += 1; m.b += 1; m.c += 1 }
    }
    observed("nested, outer write, inner write, outer write:") { m, _ in
        withAnimation(t1) { m.a += 1; withAnimation(t2) { m.b += 1 }; m.c += 1 }
    }
    observed("plain a, then plain b:") { m, _ in m.a += 1; m.b += 1 }
    observed("plain a, a scope that only reads, then plain b:") { m, _ in
        m.a += 1
        withAnimation(t1) { _ = m.c }
        m.b += 1
    }
    observed("plain a, then a scope with no animation:") { m, _ in
        m.a += 1
        withAnimation(nil) { m.b += 1 }
    }
    observed("plain a, animated c that no value changes (same value):") { m, _ in
        m.a += 1
        withAnimation(t1) { m.c = m.c }
    }

    stated("plain a, then animated b:") { h, _ in
        h.write?(0, 1)
        withAnimation(t1) { h.write?(1, 1) }
    }
    stated("animated b, then plain a:") { h, _ in
        withAnimation(t1) { h.write?(1, 1) }
        h.write?(0, 1)
    }
    stated("animated b only:") { h, _ in withAnimation(t1) { h.write?(1, 1) } }
    stated("plain a only:") { h, _ in h.write?(0, 1) }
    stated("plain a, then empty withAnimation:") { h, _ in
        h.write?(0, 1)
        withAnimation(t1) {}
    }
    stated("two scopes, same animation:") { h, _ in
        withAnimation(t1) { h.write?(0, 1) }
        withAnimation(t1) { h.write?(1, 1) }
    }
    stated("reads its own writes: plain a, scope reads:") { h, log in
        h.write?(0, 1)
        withAnimation(t1) { log.note("read in scope \(h.read?() ?? (-1, -1))"); h.write?(1, 1); log.note("read after write \(h.read?() ?? (-1, -1))") }
    }

    animatable("plain a, then animated b:") { m in m.a += 1; withAnimation(t1) { m.b += 1 } }
    animatable("animated b, then plain a:") { m in withAnimation(t1) { m.b += 1 }; m.a += 1 }

    bodies("plain a, then animated b:") { m in m.a += 1; withAnimation(t1) { m.b += 1 } }
    bodies("animated b, then plain a:") { m in withAnimation(t1) { m.b += 1 }; m.a += 1 }

    changes("plain a, then animated b:") { m, _ in m.a += 1; withAnimation(t1) { m.b += 1 } }
    changes("animated b, then plain a:") { m, _ in withAnimation(t1) { m.b += 1 }; m.a += 1 }
    changes("completion, scope wrote nothing, a plain change pending:") { m, log in
        m.a += 1
        withAnimation(t1) {} completion: { log.note("completion") }
        log.note("after the scope")
    }
    changes("completion, scope wrote b, a plain change pending:") { m, log in
        m.a += 1
        withAnimation(.linear(duration: 0.1)) { m.b += 1 } completion: { log.note("completion") }
        log.note("after the scope")
    }
    changes("completion, scope wrote b, nothing pending:") { m, log in
        withAnimation(.linear(duration: 0.1)) { m.b += 1 } completion: { log.note("completion") }
        log.note("after the scope")
    }
}
