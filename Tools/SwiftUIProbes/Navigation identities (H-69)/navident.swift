// Navigation identities (H-69, 2026-11-23). Three questions about which
// screen SwiftUI's NavigationStack shows, and when a screen is new:
//
// 1. A destination with a stamped @State, a written @State counter, a .task and
//    onAppear/onDisappear. The path holds [1]; the counter is written 4; then
//    the path is changed in one action to hold 2 in place of 1: `ints = [2]`,
//    `ints[0] = 2`, removeLast + append in one action, and for a NavigationPath
//    `path = NavigationPath([2])`. Is the screen for 2 new (a new stamp, the
//    counter 0), does the task restart, does onAppear fire? Controls: the same
//    value written again (`ints = [1]`), a buried value replaced under an
//    unchanged top (`[1, 2]` → `[3, 2]`) and the same value at two depths.
// 2. A subclass instance pushed when navigationDestination(for:) is registered
//    for its superclass: through a NavigationPath appended as the superclass,
//    appended as the subclass, through a typed [Shape] path, and through a
//    NavigationLink(value:) whose value is typed as the superclass (followed by
//    Down in a List row, as in ../NavigationLink as a list row). And the reverse:
//    registered for the subclass, pushed typed as the superclass.
// 3. One type (String) registered both on the root and on a pushed screen (the
//    Int 1 screen): which registration builds a String pushed over that screen?
//    And with String registered on the Int 1 screen alone: after that screen is
//    popped, does its registration still answer a String pushed from the root?
// 4. A three-column NavigationSplitView, each column a stamped screen, whose
//    horizontalSizeClass is written .compact and then .regular: does the split
//    collapse on macOS, and does each column keep its state?
//
// Each screen's @State `born` is stamped once with a serial when SwiftUI makes
// it (the initial value is evaluated on every init, but kept only when the state
// is new). `log` is the order of onAppear, onDisappear, task start and task
// cancel. `on` is the texts whose onAppear ran without an onDisappear since, in
// the order they appeared. `bodies` is the last body text of each screen still
// on, by stamp; a star marks the ones whose body ran in that step.
//
// A @main program, built alone with -parse-as-library; macOS 15, a window
// placed off-screen.
import AppKit
import SwiftUI

@MainActor enum Serial {
    static var count = 0
    static func next() -> Int { count += 1; return count }
}

@MainActor enum Seen {
    static var log: [String] = []
    static var on: [String] = []
    static var bodies: [Int: String] = [:]   // stamp -> last body
    static var ran: Set<Int> = []   // stamps whose body ran since the last report
    static var tappers: [Int: () -> Void] = [:]   // stamp -> taps += 1
    static func stamp(_ s: String) -> Int? {
        s.range(of: "born=").map { Int(s[$0.upperBound...])! }
    }
    static func appear(_ s: String) { log.append("appear " + s); on.append(s) }
    static func disappear(_ s: String) { log.append("disappear " + s); on.removeAll { $0 == s } }
    static func report(_ step: String) {
        let live = Set(on.compactMap(stamp))
        let shown = bodies.keys.filter(live.contains).sorted().map { "\($0)\(ran.contains($0) ? "*" : ""): \(bodies[$0]!)" }
        print(" \(step): on=\(on) log=\(log)")
        if !shown.isEmpty { print("   bodies (* = ran this step): \(shown)") }
        log = []
        ran = []
    }
}

/// The destination for an Int: a stamped @State, a counter, a task.
struct Screen: View {
    let value: Int
    @State private var born = MainActor.assumeIsolated { Serial.next() }
    @State private var taps = 0
    var body: some View {
        let text = "int \(value) born=\(born) taps=\(taps)"
        MainActor.assumeIsolated {
            Seen.bodies[born] = text
            Seen.ran.insert(born)
            Seen.tappers[born] = { taps += 1 }
        }
        return Text(text)
            .onAppear { Seen.appear("int \(value) born=\(born)") }
            .onDisappear { Seen.disappear("int \(value) born=\(born)") }
            .task {
                let tag = "\(value) born=\(born)"
                Seen.log.append("task start " + tag)
                do { try await Task.sleep(for: .seconds(1000)) } catch {
                    Seen.log.append("task cancel " + tag)
                }
            }
    }
}

struct Shown: View {
    let text: String
    var body: some View {
        Text(text)
            .onAppear { Seen.appear(text) }
            .onDisappear { Seen.disappear(text) }
    }
}

class Shape: Hashable, CustomStringConvertible {
    let id: Int
    init(_ id: Int) { self.id = id }
    static func == (a: Shape, b: Shape) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    var description: String { "\(type(of: self))(\(id))" }
}
final class Circle: Shape {}

@MainActor final class Model: ObservableObject {
    @Published var path = NavigationPath()
    @Published var ints: [Int] = []
    @Published var shapes: [Shape] = []
    @Published var compact = false
    var mode = "ints"   // "ints", "path", "shapes", "split"
}

/// What a root registers, chosen per case.
enum Registrations {
    case ints
    case shape, circle
    case strings
    case innerStrings
}

struct Root: View {
    @ObservedObject var m: Model
    let reg: Registrations
    let link: Shape?
    var body: some View {
        Group {
            switch m.mode {
            case "path": NavigationStack(path: $m.path) { content }
            case "shapes": NavigationStack(path: $m.shapes) { content }
            case "split":
                NavigationSplitView {
                    Screen(value: 100)
                } content: {
                    Screen(value: 200)
                } detail: {
                    Screen(value: 300)
                }
                .environment(\.horizontalSizeClass, m.compact ? .compact : .regular)
            default: NavigationStack(path: $m.ints) { content }
            }
        }
        .frame(width: 500, height: 300)
    }
    @ViewBuilder var content: some View {
        let list = List {
            if let link { NavigationLink("link", value: link) } else { Text("root") }
        }
        .onAppear { Seen.appear("root") }
        .onDisappear { Seen.disappear("root") }
        switch reg {
        case .ints:
            list.navigationDestination(for: Int.self) { Screen(value: $0) }
        case .shape:
            list.navigationDestination(for: Shape.self) { Shown(text: "Shape destination for \($0)") }
        case .circle:
            list.navigationDestination(for: Circle.self) { Shown(text: "Circle destination for \($0)") }
        case .strings:
            list
                .navigationDestination(for: String.self) { Shown(text: "root's String destination \($0)") }
                .navigationDestination(for: Int.self) { i in
                    Shown(text: "int \(i)")
                        .navigationDestination(for: String.self) { Shown(text: "int screen's String destination \($0)") }
                }
        case .innerStrings:
            list.navigationDestination(for: Int.self) { i in
                Shown(text: "int \(i)")
                    .navigationDestination(for: String.self) { Shown(text: "int screen's String destination \($0)") }
            }
        }
    }
}

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: TimeInterval = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func findTables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for s in v.subviews { out += findTables(s) }
    return out
}

@MainActor func down(_ w: NSWindow) {
    let ch = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        NSApp.sendEvent(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
            windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch,
            isARepeat: false, keyCode: 125)!)
    }
}

typealias Step = (String, @MainActor (Model, NSWindow, NSView) -> Void)

@MainActor func run(_ title: String, mode: String, reg: Registrations, link: Shape? = nil, _ steps: [Step]) {
    let m = Model()
    m.mode = mode
    Seen.on = []; Seen.log = []
    print("=== \(title) [\(mode)]")
    let h = NSHostingView(rootView: Root(m: m, reg: reg, link: link))
    h.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    let w = NSWindow(
        contentRect: NSRect(x: -3000, y: -3000, width: 500, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    keep.append(w)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.8)
    Seen.report("start")
    for (name, step) in steps {
        step(m, w, h)
        spin()
        Seen.report(name)
    }
    w.orderOut(nil)
    spin(0.3)
}

/// Writes the counter of the screen with the highest stamp still on 4 times.
@MainActor let tap4: Step = ("taps written 4 on the newest screen", { _, _, _ in
    guard let born = Seen.on.compactMap(Seen.stamp).max() else { return }
    for _ in 0..<4 { Seen.tappers[born]?() }
})
/// Writes the counter of every screen still on 4 times.
@MainActor let tapAll: Step = ("taps written 4 on every screen", { _, _, _ in
    for born in Seen.on.compactMap(Seen.stamp) { for _ in 0..<4 { Seen.tappers[born]?() } }
})
@MainActor func set(_ name: String, _ f: @escaping @MainActor (Model) -> Void) -> Step {
    (name, { m, _, _ in f(m) })
}
@MainActor let followLink: Step = ("Down on the link row", { _, w, h in
    if let t = findTables(h).first { w.makeFirstResponder(t) }
    down(w)
})

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            NSApplication.shared.setActivationPolicy(.accessory)

            // 1. Replacing the value on top.
            run("1A [1] -> [2] by assigning the array", mode: "ints", reg: .ints,
                [set("ints = [1]") { $0.ints = [1] }, tap4, set("ints = [2]") { $0.ints = [2] }])
            run("1B [1] -> [2] by ints[0] = 2", mode: "ints", reg: .ints,
                [set("ints = [1]") { $0.ints = [1] }, tap4, set("ints[0] = 2") { $0.ints[0] = 2 }])
            run("1C removeLast + append(2) in one action", mode: "ints", reg: .ints,
                [set("ints = [1]") { $0.ints = [1] }, tap4,
                 set("removeLast; append(2)") { $0.ints.removeLast(); $0.ints.append(2) }])
            run("1D NavigationPath [1] -> NavigationPath([2])", mode: "path", reg: .ints,
                [set("path.append(1)") { $0.path.append(1) }, tap4,
                 set("path = NavigationPath([2])") { $0.path = NavigationPath([2]) }])
            run("1E NavigationPath removeLast + append(2) in one action", mode: "path", reg: .ints,
                [set("path.append(1)") { $0.path.append(1) }, tap4,
                 set("removeLast; append(2)") { $0.path.removeLast(); $0.path.append(2) }])
            run("1F control: the same value written again", mode: "ints", reg: .ints,
                [set("ints = [1]") { $0.ints = [1] }, tap4, set("ints = [1] again") { $0.ints = [1] }])
            run("1G a buried value replaced under an unchanged top", mode: "ints", reg: .ints,
                [set("ints = [1, 2]") { $0.ints = [1, 2] }, tap4,
                 set("ints = [3, 2]") { $0.ints = [3, 2] }, set("removeLast") { $0.ints.removeLast() }])
            run("1H the same value at two depths, then the top replaced by another", mode: "ints", reg: .ints,
                [set("ints = [1, 1]") { $0.ints = [1, 1] }, tap4,
                 set("ints = [1, 2]") { $0.ints = [1, 2] }, set("ints = [1, 1]") { $0.ints = [1, 1] }])

            // 2. A subclass pushed where the superclass is registered.
            let c = Circle(7)
            run("2A Shape registered; NavigationPath.append(circle as Shape)", mode: "path", reg: .shape,
                [set("append(c as Shape)") { $0.path.append(c as Shape) }])
            run("2B Shape registered; NavigationPath.append(circle) (static Circle)", mode: "path", reg: .shape,
                [set("append(c)") { $0.path.append(c) }])
            run("2C Shape registered; typed [Shape] path holding a Circle", mode: "shapes", reg: .shape,
                [set("shapes = [c]") { $0.shapes = [c] }])
            run("2D Shape registered; NavigationLink(value: circle as Shape)", mode: "path", reg: .shape,
                link: c as Shape, [followLink])
            run("2E Circle registered; NavigationPath.append(circle as Shape)", mode: "path", reg: .circle,
                [set("append(c as Shape)") { $0.path.append(c as Shape) }])
            run("2F Circle registered; NavigationLink(value: circle as Shape)", mode: "path", reg: .circle,
                link: c as Shape, [followLink])

            // 3. One type registered on the root and on a pushed screen.
            run("3A String on the root and on int 1's screen; push a String over int 1", mode: "path",
                reg: .strings,
                [set("append(1)") { $0.path.append(1) }, set("append(\"x\")") { $0.path.append("x") },
                 set("removeLast; removeLast") { $0.path.removeLast(2) },
                 set("append(\"y\") from the root") { $0.path.append("y") }])
            run("3B String pushed over int 1 in one action from an empty path", mode: "path", reg: .strings,
                [set("path = [1, \"x\"]") { var p = NavigationPath(); p.append(1); p.append("x"); $0.path = p }])
            run("3C String on int 1's screen alone; push a String over it, pop both, push one from the root",
                mode: "path", reg: .innerStrings,
                [set("append(1)") { $0.path.append(1) }, set("append(\"x\")") { $0.path.append("x") },
                 set("removeLast; removeLast") { $0.path.removeLast(2) },
                 set("append(\"y\") from the root") { $0.path.append("y") }])

            // 4. A three-column split whose size class is written compact, then regular again.
            run("4A split: horizontalSizeClass regular -> compact -> regular", mode: "split", reg: .ints,
                [tapAll, set("compact") { $0.compact = true }, set("regular") { $0.compact = false }])
        }
    }
}
