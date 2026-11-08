import SwiftUI
import AppKit
import Observation

// What View._printChanges() prints for each cause of a body re-run: first
// appearance, an @State write, a new input from the parent, an @Environment
// value the body reads, and an @Observable property the body reads.
// macOS 15, offscreen. TUI's _printChanges copies this wording.

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let size = CGSize(width: 300, height: 200)
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
@MainActor func step(_ name: String, _ h: NSView, _ change: () -> Void) {
    print("== \(name)"); fflush(stdout)
    change()
    spin(0.4); h.layoutSubtreeIfNeeded(); spin(0.2)
    fflush(stdout)
}

@Observable final class Model { var count = 0; var other = 0 }

private struct FlavourKey: EnvironmentKey { static let defaultValue = "plain" }
extension EnvironmentValues {
    var flavour: String { get { self[FlavourKey.self] } set { self[FlavourKey.self] = newValue } }
}

@MainActor final class Drivers {
    static var setState: ((Int) -> Void)?
    static var setInput: ((Int) -> Void)?
    static var setFlavour: ((String) -> Void)?
}

struct Leaf: View {
    let input: Int
    let model: Model
    @State private var local = 0
    @Environment(\.flavour) private var flavour
    var body: some View {
        let _ = Self._printChanges()
        let _ = { Drivers.setState = { local = $0 } }()
        return Text("\(input) \(local) \(flavour) \(model.count)")
    }
}

struct Root: View {
    let model: Model
    @State private var input = 0
    @State private var flavour = "plain"
    var body: some View {
        let _ = { Drivers.setInput = { input = $0 }; Drivers.setFlavour = { flavour = $0 } }()
        return Leaf(input: input, model: model).environment(\.flavour, flavour)
    }
}

let model = Model()
let h = MainActor.assumeIsolated { () -> NSHostingView<Root> in
    print("== first appearance"); fflush(stdout)
    let h = host(Root(model: model)); spin(); h.layoutSubtreeIfNeeded(); spin(0.2); fflush(stdout)
    return h
}
MainActor.assumeIsolated {
    step("@State write", h) { Drivers.setState?(1) }
    step("new input from the parent", h) { Drivers.setInput?(1) }
    step("@Environment value read by the body", h) { Drivers.setFlavour?("sour") }
    step("@Observable property read by the body", h) { model.count = 1 }
    step("@Observable property NOT read by the body", h) { model.other = 1 }
    print("== end"); fflush(stdout)
}
