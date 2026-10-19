import SwiftUI
import AppKit

// In a Form, where do a bare labelled control's label and control go, against
// a plain LabeledContent row (A, short label)? Where does a row under padding
// go — a LabeledContent, a Toggle, a Picker, a Button — and one under each of
// the other modifiers listed (a background, help, a tag, an id, the lifecycle
// and event modifiers, `.labelsHidden()`)? B's label is longer than A's, so the
// label column is B's label's width when B takes part in it. The control's
// extent is read off the drawn pixels: the first and last column in B's row,
// right of B's label, that differs from the pixel just right of the label (in a
// grouped form the last is the section box's edge). Frames in window
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

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("LabeledContent", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row"))),
        ("Picker menu", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { bLabel() }.probe("b.row"))),
        ("Picker segmented", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { bLabel() }.pickerStyle(.segmented).probe("b.row"))),
        ("Picker radioGroup", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { bLabel() }.pickerStyle(.radioGroup).probe("b.row"))),
        ("Picker inline", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { bLabel() }.pickerStyle(.inline).probe("b.row"))),
        ("Picker menu labelsHidden", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { bLabel() }.labelsHidden().probe("b.row"))),
        ("Slider", AnyView(Slider(value: .constant(0.5)) { bLabel() }.probe("b.row"))),
        ("Stepper", AnyView(Stepper(value: .constant(3)) { bLabel() }.probe("b.row"))),
        ("DatePicker", AnyView(DatePicker(selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date) { bLabel() }.probe("b.row"))),
        ("ColorPicker", AnyView(ColorPicker(selection: .constant(.red)) { bLabel() }.probe("b.row"))),
        ("Toggle", AnyView(Toggle(isOn: .constant(true)) { bLabel() }.probe("b.row"))),
        ("Toggle switch", AnyView(Toggle(isOn: .constant(true)) { bLabel() }.toggleStyle(.switch).probe("b.row"))),
        ("TextField", AnyView(TextField(text: .constant("typed")) { bLabel() }.probe("b.row"))),
        ("Gauge", AnyView(Gauge(value: 0.5) { bLabel() }.probe("b.row"))),
        ("ProgressView", AnyView(ProgressView(value: 0.5) { bLabel() }.probe("b.row"))),
        ("LC .padding(.leading, 40)", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").padding(.leading, 40))),
        ("LC .padding()", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").padding())),
        ("LC .padding(.trailing, 40)", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").padding(.trailing, 40))),
        ("Toggle .padding(.leading, 40)", AnyView(Toggle(isOn: .constant(true)) { bLabel() }.probe("b.row").padding(.leading, 40))),
        ("Toggle .padding(.leading, 200)", AnyView(Toggle(isOn: .constant(true)) { bLabel() }.probe("b.row").padding(.leading, 200))),
        ("Picker .padding(.leading, 40)", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1) } label: { bLabel() }.probe("b.row").padding(.leading, 40))),
        ("Button .padding(.leading, 40)", AnyView(Button {} label: { bLabel() }.probe("b.row").padding(.leading, 40))),
        ("LC .background(.yellow)", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").background(.yellow))),
        ("Slider .help", AnyView(Slider(value: .constant(0.5)) { bLabel() }.probe("b.row").help("h"))),
        ("LC .tag(1)", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").tag(1))),
        ("LC .id(1)", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").id(1))),
        ("LC .onAppear", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").onAppear {})),
        ("LC .onChange", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").onChange(of: 1) {})),
        ("LC .task", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").task {})),
        ("LC .onTapGesture", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").onTapGesture {})),
        ("LC .overlay", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").overlay { Color.clear })),
        ("LC .border", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").border(.red))),
        ("LC .contextMenu", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").contextMenu { Button("x") {} })),
        ("LC .labelsHidden", AnyView(LabeledContent { TextField("", text: .constant("v")) } label: { bLabel() }.probe("b.row").labelsHidden())),
        ("Toggle .onChange", AnyView(Toggle(isOn: .constant(true)) { bLabel() }.probe("b.row").onChange(of: 1) {})),
        ("Picker .onChange", AnyView(Picker(selection: .constant(1)) { Text("One").tag(1) } label: { bLabel() }.probe("b.row").onChange(of: 1) {})),
        ("Button .keyboardShortcut", AnyView(Button {} label: { bLabel() }.probe("b.row").keyboardShortcut(.defaultAction))),
        ("Button bare", AnyView(Button {} label: { bLabel() }.probe("b.row"))),
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
