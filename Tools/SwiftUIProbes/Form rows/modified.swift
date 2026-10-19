import SwiftUI
import AppKit

// DEVS #7: a modified LabeledContent row in a Form — does its label still go in
// the label column? Row A is plain (the column's reference), row B is the row
// under test with a longer label, so the column is B's label's width when B
// takes part and A's when it does not. Frames in window coordinates.

nonisolated(unsafe) var canvas = CGSize(width: 520, height: 260)
@MainActor var keep: [NSWindow] = []
@MainActor var frames: [String: CGRect] = [:]

@MainActor func host<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: canvas)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: canvas), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    return h
}
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

struct Probe: View {
    let name: String
    var body: some View {
        GeometryReader { proxy in
            let f = proxy.frame(in: .global)
            Color.clear.onAppear { MainActor.assumeIsolated { frames[name] = f } }
                .onChange(of: f) { _, new in MainActor.assumeIsolated { frames[name] = new } }
        }
    }
}

extension View {
    func probe(_ name: String) -> some View { background(Probe(name: name)) }
}

func fmt(_ r: CGRect?) -> String {
    guard let r else { return "     —     " }
    return String(format: "%4.0f..%-4.0f", r.minX, r.maxX)
}

@MainActor func measure<V: View>(_ v: V) -> (label: CGRect?, value: CGRect?, row: CGRect?) {
    let h = host(v.frame(width: canvas.width, height: canvas.height, alignment: .topLeading))
    spin()
    h.layoutSubtreeIfNeeded()
    spin(0.1)
    return (frames["label"], frames["value"], frames["row"])
}

@MainActor func line(_ a: String, _ b: String, _ m: (label: CGRect?, value: CGRect?, row: CGRect?)) {
    print(a.padding(toLength: 34, withPad: " ", startingAt: 0) + b.padding(toLength: 22, withPad: " ", startingAt: 0)
        + "label " + fmt(m.label) + "  value " + fmt(m.value) + "  row " + fmt(m.row))
}

@MainActor func row(_ name: String, _ label: String) -> some View {
    LabeledContent { TextField("", text: .constant("v")).probe(name + ".value") } label: { Text(label).probe(name + ".label") }
}

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("bare", AnyView(row("b", "A much longer label"))),
        (".foregroundStyle(.red)", AnyView(row("b", "A much longer label").foregroundStyle(.red))),
        (".disabled(true)", AnyView(row("b", "A much longer label").disabled(true))),
        (".font(.title)", AnyView(row("b", "A much longer label").font(.title))),
        (".padding(.leading, 40)", AnyView(row("b", "A much longer label").padding(.leading, 40))),
        (".frame(width: 300)", AnyView(row("b", "A much longer label").frame(width: 300))),
        (".background(.yellow)", AnyView(row("b", "A much longer label").background(.yellow))),
        (".opacity(0.5)", AnyView(row("b", "A much longer label").opacity(0.5))),
        (".offset(x: 30)", AnyView(row("b", "A much longer label").offset(x: 30))),
        (".help(\"h\")", AnyView(row("b", "A much longer label").help("h"))),
        (".tag(1)", AnyView(row("b", "A much longer label").tag(1))),
        (".id(1)", AnyView(row("b", "A much longer label").id(1))),
        ("HStack { lc }", AnyView(HStack { row("b", "A much longer label") })),
    ]
    for style in ["columns", "grouped"] {
        print("Form(.\(style)): A plain, then B")
        for (name, b) in cases {
            frames = [:]
            let form = Form { row("a", "A"); b }
            let m: Void = style == "columns" ? { _ = measure(form.formStyle(.columns)) }() : { _ = measure(form.formStyle(.grouped)) }()
            _ = m
            let f = { (k: String) in fmt(frames[k]) }
            print(name.padding(toLength: 26, withPad: " ", startingAt: 0) + "A label " + f("a.label") + " value " + f("a.value") + " | B label " + f("b.label") + " value " + f("b.value"))
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
