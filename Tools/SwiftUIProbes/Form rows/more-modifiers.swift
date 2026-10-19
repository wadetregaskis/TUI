import SwiftUI
import AppKit

// In a Form, does a row stay in its place under the modifiers rows.swift did
// not try: `.onKeyPress`, `.transition`, `.zIndex`, `.layoutPriority`,
// `.focusedValue`, `.preference`, `.onGeometryChange`, a presentation (`.sheet`,
// `.popover`, `.alert`, `.confirmationDialog`) and `.badge`? Each is written on a
// `LabeledContent`, a `Picker` and a `Button`, after a plain `LabeledContent`
// row (A, short label); read as rows.swift reads it. Frames in window
// coordinates (points).

nonisolated(unsafe) var canvas = CGSize(width: 560, height: 220)
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

/// The drawn extent right of `after` within the rows `ys`, in points.
@MainActor func drawnExtent(_ h: NSView, after: CGFloat, ys: ClosedRange<CGFloat>) -> String {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return "no rep" }
    h.cacheDisplay(in: h.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / h.bounds.width
    func px(_ x: CGFloat, _ y: CGFloat) -> NSColor? { rep.colorAt(x: Int(x * scale), y: Int(y * scale)) }
    let mid = (ys.lowerBound + ys.upperBound) / 2
    guard let ref = px(after + 2, mid) else { return "no ref" }
    func differs(_ c: NSColor?) -> Bool {
        guard let c, let a = c.usingColorSpace(.deviceRGB), let b = ref.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent) > 0.06
    }
    var first: CGFloat?
    var last: CGFloat?
    var x = after + 3
    while x < h.bounds.width - 1 {
        var y = ys.lowerBound + 1
        var hit = false
        while y < ys.upperBound - 1 {
            if differs(px(x, y)) { hit = true; break }
            y += 1
        }
        if hit { if first == nil { first = x }; last = x }
        x += 1
    }
    guard let first, let last else { return "control  nothing" }
    return String(format: "control %4.0f..%-4.0f", first, last + 1)
}

@MainActor func aRow() -> some View {
    LabeledContent { TextField("", text: .constant("v")).probe("a.value") } label: { Text("A").probe("a.label") }
}

let long = "A much longer label"

@MainActor func bLabel() -> some View { Text(long).probe("b.label") }


struct FVKey: FocusedValueKey { typealias Value = Int }
extension FocusedValues { var fvProbe: Int? { get { self[FVKey.self] } set { self[FVKey.self] = newValue } } }
struct PKey: PreferenceKey { static let defaultValue = 0; static func reduce(value: inout Int, nextValue: () -> Int) {} }

@MainActor func lc() -> some View { LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row") }
@MainActor func pk() -> some View { Picker(selection: .constant(1)) { Text("One").tag(1) } label: { bLabel() }.probe("b.row") }
@MainActor func bt() -> some View { Button {} label: { bLabel() }.probe("b.row") }

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("LC bare", AnyView(lc())),
        ("LC .onKeyPress", AnyView(lc().onKeyPress(.space) { .handled })),
        ("LC .transition", AnyView(lc().transition(.opacity))),
        ("LC .zIndex", AnyView(lc().zIndex(1))),
        ("LC .layoutPriority", AnyView(lc().layoutPriority(1))),
        ("LC .focusedValue", AnyView(lc().focusedValue(\.fvProbe, 1))),
        ("LC .preference", AnyView(lc().preference(key: PKey.self, value: 1))),
        ("LC .onGeometryChange", AnyView(lc().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in })),
        ("LC .sheet", AnyView(lc().sheet(isPresented: .constant(false)) { Text("s") })),
        ("LC .popover", AnyView(lc().popover(isPresented: .constant(false)) { Text("s") })),
        ("LC .badge", AnyView(lc().badge(3))),
        ("Picker bare", AnyView(pk())),
        ("Picker .onKeyPress", AnyView(pk().onKeyPress(.space) { .handled })),
        ("Picker .transition", AnyView(pk().transition(.opacity))),
        ("Picker .zIndex", AnyView(pk().zIndex(1))),
        ("Picker .layoutPriority", AnyView(pk().layoutPriority(1))),
        ("Button bare", AnyView(bt())),
        ("Button .alert", AnyView(bt().alert("t", isPresented: .constant(false)) { Button("OK") {} })),
        ("Button .confirmationDialog", AnyView(bt().confirmationDialog("t", isPresented: .constant(false)) { Button("OK") {} })),
        ("Button .sheet", AnyView(bt().sheet(isPresented: .constant(false)) { Text("s") })),
        ("Button .transition", AnyView(bt().transition(.opacity))),
        ("Button .layoutPriority", AnyView(bt().layoutPriority(1))),
    ]
    for style in ["columns", "grouped"] {
        print("Form(.\(style)): A plain LabeledContent, then B")
        for (name, b) in cases {
            frames = [:]
            let form = Form { aRow(); b }
            let root = Group {
                if style == "columns" { form.formStyle(.columns) } else { form.formStyle(.grouped) }
            }
            let h = host(root.frame(width: canvas.width, height: canvas.height, alignment: .topLeading))
            spin()
            h.layoutSubtreeIfNeeded()
            spin(0.1)
            let f = { (k: String) in fmt(frames[k]) }
            var extent = ""
            if let label = frames["b.label"], let row = frames["b.row"] {
                extent = drawnExtent(h, after: label.maxX, ys: row.minY...row.maxY)
            }
            print(
                name.padding(toLength: 31, withPad: " ", startingAt: 0) + "A label " + f("a.label") + " value "
                    + f("a.value") + " | B label " + f("b.label") + " row " + f("b.row") + " " + extent)
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
