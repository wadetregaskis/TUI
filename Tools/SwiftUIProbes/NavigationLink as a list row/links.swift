// What does a NavigationLink do as a row of a List: with a selection, without
// one, in a split view and in a stack? Prints the selection and the path after
// each key press and click.
import AppKit
import SwiftUI

enum Cat: String, Identifiable, Hashable, CaseIterable, CustomStringConvertible {
    case fruit, veg, nuts
    var id: String { "id-" + rawValue }
    var description: String { rawValue }
}

@MainActor final class Model: ObservableObject {
    @Published var sel: Cat?
    @Published var setSel: Set<Cat> = []
    @Published var intSel: Int?
    @Published var path: [Cat] = []
    @Published var strPath: [String] = []
    @Published var shown: [String] = []
    func report() -> String {
        "sel=\(sel.map(String.init(describing:)) ?? "nil") set=\(setSel.map(\.rawValue).sorted()) "
            + "int=\(intSel.map(String.init) ?? "nil") path=\(path.map(\.rawValue)) strPath=\(strPath)"
    }
}

@MainActor func findTables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for s in v.subviews { out += findTables(s) }
    return out
}

@MainActor func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func key(_ w: NSWindow, _ name: String) {
    let (code, ch): (UInt16, String) = switch name {
    case "down": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!))
    case "up": (126, String(UnicodeScalar(NSUpArrowFunctionKey)!))
    case "return": (36, "\r")
    case "space": (49, " ")
    default: fatalError(name)
    }
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let ev = NSEvent.keyEvent(
            with: type, location: .zero,
            modifierFlags: name == "down" || name == "up" ? [.numericPad, .function] : [],
            timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: ch,
            charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(ev)
    }
    spin(0.5)
}

@MainActor func click(_ w: NSWindow, _ table: NSTableView, row: Int) {
    let r = table.rect(ofRow: row)
    let p = table.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let ev = NSEvent.mouseEvent(
            with: type, location: p, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(ev)
    }
    spin(0.6)
}

@MainActor func run<V: View>(_ title: String, _ m: Model, gestures: [String], @ViewBuilder view: () -> V) {
    print("=== \(title)")
    let h = NSHostingView(rootView: view().frame(width: 700, height: 300))
    h.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
    let w = NSWindow(
        contentRect: NSRect(x: -3000, y: -3000, width: 700, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.8)
    guard let table = findTables(h).first else {
        print("no table")
        w.orderOut(nil)
        return
    }
    w.makeFirstResponder(table)
    print("rows", table.numberOfRows, "firstResponder is table:", w.firstResponder === table, "start:", m.report())
    for g in gestures {
        if g.hasPrefix("click") {
            if let live = findTables(h).first {
                click(w, live, row: Int(g.dropFirst(5))!)
            } else {
                print(" (no table on screen)")
            }
        } else {
            key(w, g)
        }
        print(" \(g):", m.report(), "shown=\(m.shown.last ?? "-")")
    }
    w.orderOut(nil)
    spin(0.2)
}

struct Shown: View {
    @ObservedObject var m: Model
    let text: String
    var body: some View { Text(text).onAppear { m.shown.append(text) } }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
            let gestures = ["down", "down", "return", "space", "click0", "click2"]
            var m = Model()
            run("A split view, data form, selection value = link value, id differs", m, gestures: gestures) {
                SplitA(m: m)
            }
            m = Model()
            run("A2 split view, ForEach, multi-selection", m, gestures: gestures) { SplitSet(m: m) }
            m = Model()
            run("B stack + selecting list + typed path", m, gestures: gestures) { StackSel(m: m) }
            m = Model()
            run("C stack + list without selection", m, gestures: ["down", "return", "space", "click0"]) {
                StackPlain(m: m)
            }
            m = Model()
            run("D selecting list, link value is another type, no tag", m, gestures: gestures) { Mismatch(m: m) }
            m = Model()
            run("E selecting list, explicit tag on a link (Int), value String", m, gestures: gestures) {
                Tagged(m: m)
            }
            m = Model()
            run("F selecting list, link inside an HStack in the row", m, gestures: gestures) { Nested(m: m) }
            m = Model()
            run("F2 selecting list, link inside an HStack, row id another type", m, gestures: gestures) {
                NestedOtherID(m: m)
            }
            m = Model()
            run("K split view, sidebar without a selection, stack in the detail", m, gestures: gestures) {
                SidebarNoSelection(m: m)
            }
            m = Model()
            run("G selecting list, row id = selection type, link value another type", m, gestures: gestures) {
                IdRow(m: m)
            }
            m = Model()
            run("H link with a view destination in a selecting list", m, gestures: gestures) { ViewDest(m: m) }
            m = Model()
            run("I selecting list, link with a padding", m, gestures: gestures) { Padded(m: m) }
            m = Model()
            run("J selecting list, nil-value link first", m, gestures: gestures) { NilValue(m: m) }
        }
    }
}

struct SplitA: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationSplitView {
            List(Cat.allCases, selection: $m.sel) { c in NavigationLink(c.rawValue, value: c) }
        } content: {
            if let s = m.sel { Shown(m: m, text: "content:\(s)") } else { Text("none") }
        } detail: {
            Text("detail")
        }
    }
}

struct SplitSet: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationSplitView {
            List(selection: $m.setSel) { ForEach(Cat.allCases) { c in NavigationLink(c.rawValue, value: c) } }
        } detail: {
            Shown(m: m, text: "detail:\(m.setSel.map(\.rawValue).sorted())")
        }
    }
}

struct StackSel: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.path) {
            List(Cat.allCases, selection: $m.sel) { c in NavigationLink(c.rawValue, value: c) }
                .navigationDestination(for: Cat.self) { c in Shown(m: m, text: "pushed:\(c)") }
        }
    }
}

struct StackPlain: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.path) {
            List(Cat.allCases) { c in NavigationLink(c.rawValue, value: c) }
                .navigationDestination(for: Cat.self) { c in Shown(m: m, text: "pushed:\(c)") }
        }
    }
}

struct Mismatch: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.strPath) {
            List(Cat.allCases, selection: $m.sel) { c in NavigationLink(c.rawValue, value: c.rawValue) }
                .navigationDestination(for: String.self) { s in Shown(m: m, text: "pushed:\(s)") }
        }
    }
}

struct Tagged: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.strPath) {
            List(selection: $m.intSel) {
                NavigationLink("a", value: "A").tag(0)
                NavigationLink("b", value: "B").tag(1)
                NavigationLink("c", value: "C").tag(2)
            }
            .navigationDestination(for: String.self) { s in Shown(m: m, text: "pushed:\(s)") }
        }
    }
}

struct Nested: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.path) {
            List(selection: $m.sel) {
                ForEach(Cat.allCases, id: \.self) { c in
                    HStack {
                        Text("x")
                        NavigationLink(c.rawValue, value: c)
                    }
                }
            }
            .navigationDestination(for: Cat.self) { c in Shown(m: m, text: "pushed:\(c)") }
        }
    }
}

struct NestedOtherID: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.path) {
            List(Cat.allCases, selection: $m.sel) { c in
                HStack {
                    Text("x")
                    NavigationLink(c.rawValue, value: c)
                }
            }
            .navigationDestination(for: Cat.self) { c in Shown(m: m, text: "pushed:\(c)") }
        }
    }
}

struct SidebarNoSelection: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationSplitView {
            List(Cat.allCases) { c in NavigationLink(c.rawValue, value: c) }
                .navigationDestination(for: Cat.self) { c in Shown(m: m, text: "pushed:\(c)") }
        } detail: {
            NavigationStack(path: $m.path) { Text("root") }
        }
    }
}

struct IdRow: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack(path: $m.strPath) {
            List(selection: $m.sel) {
                ForEach(Cat.allCases, id: \.self) { c in NavigationLink(c.rawValue, value: c.rawValue) }
            }
            .navigationDestination(for: String.self) { s in Shown(m: m, text: "pushed:\(s)") }
        }
    }
}

struct ViewDest: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationStack {
            List(selection: $m.sel) {
                ForEach(Cat.allCases, id: \.self) { c in
                    NavigationLink(c.rawValue) { Shown(m: m, text: "pushed:\(c)") }
                }
            }
        }
    }
}

struct Padded: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationSplitView {
            List(Cat.allCases, selection: $m.sel) { c in NavigationLink(c.rawValue, value: c).padding(4) }
        } detail: {
            Text("d")
        }
    }
}

struct NilValue: View {
    @ObservedObject var m: Model
    var body: some View {
        NavigationSplitView {
            List(selection: $m.sel) {
                NavigationLink("none", value: Optional<Cat>.none)
                NavigationLink("veg", value: Optional(Cat.veg))
                NavigationLink("nuts", value: Optional(Cat.nuts))
            }
        } detail: {
            Text("d")
        }
    }
}
