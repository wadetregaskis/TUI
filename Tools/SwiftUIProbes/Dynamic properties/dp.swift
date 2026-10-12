import SwiftUI
import AppKit
import Observation

// DYNP review round 1: what SwiftUI does with DynamicProperty.update() in the
// cases the review questioned. macOS 15, offscreen NSHostingView.

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

@MainActor final class Log { static var lines: [String] = []; static var updates: [String: Int] = [:] }

/// Counts its update()s in a struct field: what body reads says whether the
/// change was written back.
struct Counting: DynamicProperty {
    let tag: String
    var count = 0
    mutating func update() {
        count += 1
        MainActor.assumeIsolated { Log.updates[tag, default: 0] += 1 }
    }
}

// 1. A struct view's own field (baseline).
struct PlainView: View {
    var c = Counting(tag: "plain")
    var body: some View {
        Log.lines.append("plain body count=\(c.count)")
        return Text("\(c.count)")
    }
}

// 2. An Optional field.
struct OptionalView: View {
    var c: Counting? = Counting(tag: "optional")
    var body: some View {
        Log.lines.append("optional body count=\(c?.count ?? -1)")
        return Text("\(c?.count ?? -1)")
    }
}

// 2b. An Optional field whose property reads the environment and keeps state.
struct Reading: DynamicProperty {
    @Environment(\.lineLimit) var limit
    @State var kept = 5
}
struct OptionalReadingView: View {
    var r: Reading? = Reading()
    var body: some View {
        Log.lines.append("optional-reading body limit=\(String(describing: r?.limit)) kept=\(String(describing: r?.kept))")
        return Text("x")
    }
}
struct PlainReadingView: View {
    var r = Reading()
    var body: some View {
        Log.lines.append("plain-reading body limit=\(String(describing: r.limit)) kept=\(r.kept)")
        return Text("x")
    }
}

// 3. An enum view.
enum EnumView: View {
    case main(Counting)
    case blank
    var body: some View {
        switch self {
        case .main(let c):
            Log.lines.append("enum body count=\(c.count)")
            return Text("\(c.count)")
        case .blank:
            Log.lines.append("enum body blank")
            return Text("blank")
        }
    }
}

// 4. A class DynamicProperty, held strongly and weakly.
final class Box: DynamicProperty {
    let tag: String
    var n = 0
    init(tag: String) { self.tag = tag }
    func update() {
        n += 1
        MainActor.assumeIsolated { Log.updates[tag, default: 0] += 1 }
    }
}
@MainActor let strongBox = Box(tag: "strongClass")
@MainActor let weakBox = Box(tag: "weakClass")
@MainActor let unownedBox = Box(tag: "unownedClass")
struct UnownedView: View {
    unowned let held: Box = unownedBox
    var body: some View {
        Log.lines.append("unowned body held.n=\(held.n)")
        return Text("\(held.n)")
    }
}
struct ClassView: View {
    let strong: Box = strongBox
    weak var weakOne: Box? = weakBox
    var body: some View {
        Log.lines.append("class body strong.n=\(strong.n) weak.n=\(weakOne?.n ?? -1)")
        return Text("\(strong.n)")
    }
}

// 5. Observation: a read made in update(), not in body.
@Observable final class Model { var value = 0 }
@MainActor let model = Model()
struct Caching: DynamicProperty {
    let model: Model
    var cached = -1
    mutating func update() { cached = model.value }
}
struct ObservingView: View {
    var c = Caching(model: model)
    var body: some View {
        Log.lines.append("observing body cached=\(c.cached)")
        return Text("\(c.cached)")
    }
}

/// Control for 5: holds the model, reads nothing of it.
struct Holding: DynamicProperty {
    let model: Model
    var cached = -1
    mutating func update() { cached = 0 }
}
struct ControlView: View {
    var c = Holding(model: model2)
    var body: some View {
        Log.lines.append("control body cached=\(c.cached)")
        return Text("\(c.cached)")
    }
}
@MainActor let model2 = Model()

// 6. A metatype field beside a wrapper (what the type walk sees).
struct ThinView: View {
    var c = Counting(tag: "thin")
    let style: Int.Type = Int.self
    let pair: (Int.Type, String) = (Int.self, "a string long enough to be on the heap")
    var body: some View {
        Log.lines.append("thin body count=\(c.count) pair=\(pair.1.count)")
        return Text("\(c.count)")
    }
}

// 7. An enum view first drawn blank, then with a payload.
struct EnumSwitch: View {
    @State var showMain = false
    static var flip: (() -> Void)?
    var body: some View {
        let _ = { EnumSwitch.flip = { showMain = true } }()
        return showMain ? EnumView.main(Counting(tag: "enum2")) : EnumView.blank
    }
}

@MainActor func run() {
    func report(_ title: String) {
        print("== \(title)")
        for l in Log.lines { print("   \(l)") }
        print("   updates: \(Log.updates.sorted { $0.key < $1.key })")
        Log.lines = []; Log.updates = [:]
    }
    _ = host(PlainView()); spin(); report("1 plain struct field")
    _ = host(OptionalView()); spin(); report("2 optional field")
    _ = host(OptionalReadingView().lineLimit(3)); spin(); report("2b optional field: environment inside")
    _ = host(PlainReadingView().lineLimit(3)); spin(); report("2c plain field: environment inside (control)")
    _ = host(EnumView.main(Counting(tag: "enum"))); spin(); report("3 enum view")
    _ = host(ClassView()); spin(); report("4 class fields: strong + weak")
    _ = host(UnownedView()); spin(); report("4b class field: unowned")
    let h = host(ObservingView()); spin(); report("5a observing first draw")
    model.value = 7
    spin(0.5); h.layoutSubtreeIfNeeded(); spin(0.3); report("5b after model.value = 7 (body rerun?)")
    let h2 = host(ControlView()); spin(); report("5c control first draw")
    model2.value = 7
    spin(0.5); h2.layoutSubtreeIfNeeded(); spin(0.3); report("5d control after model2.value = 7 (expect no body)")
    _ = host(ThinView()); spin(); report("6 metatype fields")
    _ = host(EnumSwitch()); spin(); report("7a enum blank first")
    EnumSwitch.flip?(); spin(0.5); report("7b enum then main")
}

MainActor.assumeIsolated { run() }
