import SwiftUI
import AppKit

// In a Form, where does a row with no label go — a control written with none
// (`Slider(value:)`), one whose label is an `EmptyView`, a `LabeledContent`
// whose label is an `EmptyView`, a `Picker("")` — against a `LabeledContent`
// row (A) with a long label, which sets the label column? A `Text` written bare
// and a `Toggle` with an empty label are there for comparison. B's row frame is
// the control's (or the content's); the drawn extent is read off the pixels
// across the row, from the form's leading edge (in a grouped form, from inside
// the section box). Frames in window coordinates (points).

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
    LabeledContent { TextField("", text: .constant("v")).probe("a.value") } label: { Text("A much longer label").probe("a.label") }
}

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("Text plain", AnyView(Text("plain").probe("b.row"))),
        ("Slider no label", AnyView(Slider(value: .constant(0.5)).probe("b.row"))),
        ("Slider EmptyView lo/hi", AnyView(Slider(value: .constant(0.5)) { EmptyView() } minimumValueLabel: { Text("lo") } maximumValueLabel: { Text("hi") }.probe("b.row"))),
        ("LC Text, EmptyView label", AnyView(LabeledContent { Text("Alice") } label: { EmptyView() }.probe("b.row"))),
        ("LC TextField, EmptyView", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { EmptyView() }.probe("b.row"))),
        ("Picker EmptyView label", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { EmptyView() }.probe("b.row"))),
        ("Picker \"\"", AnyView(Picker("", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.probe("b.row"))),
        ("Stepper EmptyView label", AnyView(Stepper(value: .constant(3)) { EmptyView() }.probe("b.row"))),
        ("Toggle EmptyView label", AnyView(Toggle(isOn: .constant(true)) { EmptyView() }.probe("b.row"))),
        ("ColorPicker EmptyView", AnyView(ColorPicker(selection: .constant(.red)) { EmptyView() }.probe("b.row"))),
        ("DatePicker EmptyView", AnyView(DatePicker(selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date) { EmptyView() }.probe("b.row"))),
    ]
    for style in ["columns", "grouped"] {
        print("Form(.\(style)): A LabeledContent with a long label, then B")
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
            if let row = frames["b.row"] {
                extent = drawnExtent(h, after: (style == "columns" ? 0 : 22), ys: row.minY...row.maxY)
            }
            print(
                name.padding(toLength: 26, withPad: " ", startingAt: 0) + "A label " + f("a.label") + " value "
                    + f("a.value") + " | B row " + f("b.row") + " " + extent)
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
