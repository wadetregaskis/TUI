import SwiftUI
import AppKit

// In a Form, is a row written as a view of the app's own laid out as the row
// its body is? Each control is written twice after a `LabeledContent` row (A)
// with a long label, which sets the label column: directly, and as the whole
// body of a `struct` of the app's own. Where its label (B label) and its row (B
// row) go, and the drawn extent of the row past the label column, are compared;
// the same frames both ways mean the form reads through the view's body. Frames
// in window coordinates (points).

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

@MainActor func picker() -> some View {
    Picker(selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) } label: { Text("Mode").probe("b.label") }
        .probe("b.row")
}
@MainActor func toggle() -> some View {
    Toggle(isOn: .constant(true)) { Text("Enabled").probe("b.label") }.probe("b.row")
}
@MainActor func switchToggle() -> some View {
    Toggle(isOn: .constant(true)) { Text("Enabled").probe("b.label") }.toggleStyle(.switch).probe("b.row")
}
@MainActor func slider() -> some View {
    Slider(value: .constant(0.5)) { Text("Level").probe("b.label") }.probe("b.row")
}
@MainActor func stepper() -> some View {
    Stepper(value: .constant(3)) { Text("Count").probe("b.label") }.probe("b.row")
}
@MainActor func button() -> some View {
    Button { } label: { Text("Go").probe("b.label") }.probe("b.row")
}
@MainActor func labeled() -> some View {
    LabeledContent { Text("Alice") } label: { Text("Name").probe("b.label") }.probe("b.row")
}
@MainActor func textField() -> some View {
    TextField(text: .constant("x")) { Text("Title").probe("b.label") }.probe("b.row")
}

struct PickerRow: View { var body: some View { picker() } }
struct ToggleRow: View { var body: some View { toggle() } }
struct SwitchRow: View { var body: some View { switchToggle() } }
struct SliderRow: View { var body: some View { slider() } }
struct StepperRow: View { var body: some View { stepper() } }
struct ButtonRow: View { var body: some View { button() } }
struct LabeledRow: View { var body: some View { labeled() } }
struct FieldRow: View { var body: some View { textField() } }
/// A view of the app's own around a view of the app's own.
struct OuterPickerRow: View { var body: some View { PickerRow() } }
/// A view of the app's own whose body is the control under a modifier.
struct PaddedPickerRow: View { var body: some View { picker().padding(.vertical, 0) } }

@MainActor func run() {
    let cases: [(String, AnyView)] = [
        ("Picker", AnyView(picker())), ("struct Picker", AnyView(PickerRow())),
        ("struct struct Picker", AnyView(OuterPickerRow())), ("struct Picker.padding", AnyView(PaddedPickerRow())),
        ("Toggle", AnyView(toggle())), ("struct Toggle", AnyView(ToggleRow())),
        ("Toggle .switch", AnyView(switchToggle())), ("struct Toggle .switch", AnyView(SwitchRow())),
        ("Slider", AnyView(slider())), ("struct Slider", AnyView(SliderRow())),
        ("Stepper", AnyView(stepper())), ("struct Stepper", AnyView(StepperRow())),
        ("Button", AnyView(button())), ("struct Button", AnyView(ButtonRow())),
        ("LabeledContent", AnyView(labeled())), ("struct LabeledContent", AnyView(LabeledRow())),
        ("TextField", AnyView(textField())), ("struct TextField", AnyView(FieldRow())),
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
            if let row = frames["b.row"], let label = frames["b.label"] {
                extent = drawnExtent(h, after: max(label.maxX, style == "columns" ? 0 : 22), ys: row.minY...row.maxY)
            }
            print(
                name.padding(toLength: 24, withPad: " ", startingAt: 0) + "A label " + f("a.label") + " | B label "
                    + f("b.label") + " row " + f("b.row") + " " + extent)
        }
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
