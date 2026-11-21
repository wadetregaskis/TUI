import AppKit
import SwiftUI

// AnyView type swap (2026-11-21): what happens to the @State of an AnyView's
// content when the erased type changes, when the same type is wrapped again
// in a new AnyView on every body run, and when the first type comes back.
// Then, as a control for a tuple drawn whole: does a view after an `if` that
// adds two views keep its @State when the condition flips?
//
// Each view's @State is stamped, once, with a serial when SwiftUI makes it
// (the initial value is evaluated on every init, but kept only when the state
// is new); a second @State `n` is written by the probe through a closure the
// body leaves behind. The same stamp after a step means the state was kept.
//
// macOS 15, offscreen NSHostingView.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 300)
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.3) {
    RunLoop.main.run(until: Date().addingTimeInterval(s / 2))
    for window in keep {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(s / 2))
}

@MainActor enum Serial {
    static var count = 0
    static func next() -> Int { count += 1; return count }
}
@MainActor enum Seen {
    static var lines: [String: String] = [:]
    static var writers: [String: (Int) -> Void] = [:]
    static func report(_ step: String) {
        print(step + ": " + lines.keys.sorted().map { "\($0)[\(lines[$0]!)]" }.joined(separator: " "))
        lines = [:]
    }
}

/// A view with a stamped @State and a writable @State, as its first two states.
struct A: View {
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    @State private var n = 0
    var body: some View {
        MainActor.assumeIsolated {
            Seen.lines["A"] = "born=\(born) n=\(n)"
            Seen.writers["A"] = { n = $0 }
        }
        return Text("A \(born) \(n)")
    }
}
/// The same state layout as A, a different type.
struct B: View {
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    @State private var n = 0
    var body: some View {
        MainActor.assumeIsolated {
            Seen.lines["B"] = "born=\(born) n=\(n)"
            Seen.writers["B"] = { n = $0 }
        }
        return Text("B \(born) \(n)")
    }
}
/// A third view whose state layout differs: its first state is a String.
struct C: View {
    @State private var name = "c"
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    var body: some View {
        MainActor.assumeIsolated { Seen.lines["C"] = "born=\(born)" }
        return Text("C \(name) \(born)")
    }
}

@MainActor @Observable final class Model {
    var which = 0
    var tick = 0
    var flag = false
}

struct Swapped: View {
    @Environment(Model.self) var m
    var body: some View {
        _ = m.tick
        return screen()
    }
    func screen() -> AnyView {
        switch m.which {
        case 0: return AnyView(A())
        case 1: return AnyView(B())
        case 2: return AnyView(C())
        default: return AnyView(A().padding(1))
        }
    }
}

/// A tuple whose middle member adds two views when `flag` flips, followed by a stateful view.
struct Counter: View {
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    var body: some View {
        MainActor.assumeIsolated { Seen.lines["Counter"] = "born=\(born)" }
        return Text("counter \(born)")
    }
}
struct Tupled: View {
    @Environment(Model.self) var m
    var body: some View {
        Text("a")
        if m.flag {
            Text("x")
            Text("y")
        }
        Counter()
    }
}

@main @MainActor struct Probe {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let m = Model()
        _ = host(Swapped().environment(m))
        spin(); Seen.report("A first")
        Seen.writers["A"]?(5); spin(); Seen.report("A n written 5")
        m.tick += 1; spin(); Seen.report("A re-wrapped in a new AnyView (same type)")
        m.which = 1; spin(); Seen.report("swapped to B (same state layout)")
        Seen.writers["B"]?(7); spin(); Seen.report("B n written 7")
        m.which = 0; spin(); Seen.report("swapped back to A")
        m.which = 2; spin(); Seen.report("swapped to C (other state layout)")
        m.which = 0; spin(); Seen.report("swapped back to A again")
        Seen.writers["A"]?(9); spin(); Seen.report("A n written 9")
        m.which = 3; spin(); Seen.report("swapped to A.padding(1) (A inside another type)")
        m.which = 0; spin(); Seen.report("swapped back to plain A")

        let t = Model()
        _ = host(Tupled().environment(t))
        spin(); Seen.report("tuple, if false")
        t.flag = true; spin(); Seen.report("tuple, if true")
        t.flag = false; spin(); Seen.report("tuple, if false again")
    }
}
