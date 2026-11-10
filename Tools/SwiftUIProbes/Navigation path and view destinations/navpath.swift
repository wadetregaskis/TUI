// 2026-11-10: does a screen pushed with a view destination go into a
// NavigationStack's path binding? For a NavigationPath binding and, to compare,
// a typed [Int] one: what the binding holds (count, and whether it is still
// codable) after navigationDestination(isPresented:) and (item:) push — one
// written on the root (`flag`, `item`), one on value 1's screen (`inner`) — and
// after a view-destination NavigationLink in a List row is followed (Down, as
// in ../NavigationLink as a list row); then what is on screen, and what the
// flags say, after the app pops, appends to or clears the path. `on` is the
// screens whose onAppear ran without an onDisappear since, in the order they
// appeared. A `@main` program, built alone with `-parse-as-library`.
import AppKit
import SwiftUI

@MainActor final class Model: ObservableObject {
    @Published var path = NavigationPath()
    @Published var ints: [Int] = []
    @Published var flag = false
    @Published var inner = false
    @Published var item: Int?
    var typed = false
    var on: [String] = []
    func report() -> String {
        let p = typed
            ? "ints=\(ints)"
            : "path.count=\(path.count) codable=\(path.codable == nil ? "nil" : "yes")"
        return "\(p) flag=\(flag) inner=\(inner) item=\(item.map(String.init) ?? "nil") on=\(on)"
    }
}

struct Shown: View {
    let m: Model
    let text: String
    var body: some View {
        Text(text)
            .onAppear { m.on.append(text) }
            .onDisappear { m.on.removeAll { $0 == text } }
    }
}

struct Screens: ViewModifier {
    let m: Model
    @ObservedObject var o: Model
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Int.self) { i in
                if i == 1 {
                    Shown(m: m, text: "int 1")
                        .navigationDestination(isPresented: $o.inner) { Shown(m: m, text: "inner") }
                } else {
                    Shown(m: m, text: "int \(i)")
                }
            }
            .navigationDestination(isPresented: $o.flag) { Shown(m: m, text: "flag") }
            .navigationDestination(item: $o.item) { i in Shown(m: m, text: "item \(i)") }
    }
}

struct Root: View {
    @ObservedObject var m: Model
    var body: some View {
        Group {
            if m.typed {
                NavigationStack(path: $m.ints) { content }
            } else {
                NavigationStack(path: $m.path) { content }
            }
        }
        .frame(width: 500, height: 300)
    }
    var content: some View {
        List {
            NavigationLink("to a view") { Shown(m: m, text: "view link") }
        }
        .modifier(Screens(m: m, o: m))
        .onAppear { m.on.append("root") }
        .onDisappear { m.on.removeAll { $0 == "root" } }
    }
}

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

typealias Step = (String, @MainActor (Model, NSWindow, NSHostingView<Root>) -> Void)

@MainActor func run(_ title: String, typed: Bool, _ steps: [Step]) {
    let m = Model()
    m.typed = typed
    print("=== \(title) [\(typed ? "[Int]" : "NavigationPath")]")
    let h = NSHostingView(rootView: Root(m: m))
    h.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    let w = NSWindow(
        contentRect: NSRect(x: -3000, y: -3000, width: 500, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.8)
    print(" start:", m.report())
    for (name, step) in steps {
        step(m, w, h)
        spin()
        print(" \(name):", m.report())
    }
    w.orderOut(nil)
    spin(0.2)
}

@MainActor func append(_ i: Int) -> Step {
    ("append \(i)", { m, _, _ in if m.typed { m.ints.append(i) } else { m.path.append(i) } })
}
@MainActor let removeLast: Step = ("removeLast", { m, _, _ in
    if m.typed { if !m.ints.isEmpty { m.ints.removeLast() } } else if !m.path.isEmpty { m.path.removeLast() }
})
@MainActor let clear: Step = ("clear", { m, _, _ in if m.typed { m.ints = [] } else { m.path = NavigationPath() } })
@MainActor let flagOn: Step = ("flag=true", { m, _, _ in m.flag = true })
@MainActor let flagOff: Step = ("flag=false", { m, _, _ in m.flag = false })
@MainActor let innerOn: Step = ("inner=true", { m, _, _ in m.inner = true })

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            setvbuf(stdout, nil, _IOLBF, 0)
            NSApplication.shared.setActivationPolicy(.accessory)
            for typed in [false, true] {
                run("A isPresented on an empty path, then the flag cleared", typed: typed, [flagOn, flagOff])
                run("B root isPresented over a value, then the app pops", typed: typed,
                    [append(1), flagOn, removeLast])
                run("C isPresented declared on value 1's screen, then the app pops the value", typed: typed,
                    [append(1), innerOn, removeLast])
                run("D isPresented on value 1's screen, then the app appends and pops", typed: typed,
                    [append(1), innerOn, append(2), removeLast, removeLast])
                run("E root isPresented on an empty path, then the app appends and clears", typed: typed,
                    [flagOn, append(1), clear])
                run("G isPresented on value 1's screen, then the app clears the path", typed: typed,
                    [append(1), innerOn, clear])
                run("H root item on an empty path, then the app appends and pops", typed: typed,
                    [("item=5", { m, _, _ in m.item = 5 }), append(1), removeLast])
                run("F a view-destination link in a List row, followed by Down", typed: typed, [
                    ("Down", { _, w, h in
                        if let t = findTables(h).first { w.makeFirstResponder(t) }
                        down(w)
                    }),
                    append(1), removeLast, append(2), clear,
                ])
            }
        }
    }
}
