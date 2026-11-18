// Probe: which parts of each control `.foregroundStyle(_:)` colours (FGSWEEP, macOS 15.8).
//
// Each sample is hosted in an off-screen window, drawn with `cacheDisplay`, and
// read back: `red` counts the pixels of the stated red (pure red, or red
// blended over the light background by antialiasing or a hierarchical level),
// and `x`/`y` give their bounding box in points; `minG` is the least green
// among them, near 0 for the full colour and about 0.5 for a secondary level of
// it. Where a sample reads only right of `fromX`, `darkest` is the darkest grey
// there. A sample is drawn twice, with and without the style, so a control that
// is red of its own shows as such.
// `labelsHidden` variants and samples whose label is pinned blue isolate the
// control's own parts (its value, its chrome) from its label.
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 common.swift fgsweep.swift -o "$TMPDIR/fgsweep"
//   "$TMPDIR/fgsweep" | diff fgsweep.out -
import AppKit
import SwiftUI

let red = Color(.sRGB, red: 1, green: 0, blue: 0)
let blue = Color(.sRGB, red: 0, green: 0, blue: 1)

@MainActor func reds<V: View>(_ view: V, size: CGSize, titled: Bool, fromX: Double = 0) -> String {
    let h: NSView
    if titled {
        let hosting = NSHostingView(rootView: AnyView(view))
        let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = hosting
        w.orderFrontRegardless()
        keep.append(w)
        h = w.contentView!.superview ?? hosting
    } else {
        h = host(view, size: size)
    }
    spin(0.5)
    h.layoutSubtreeIfNeeded()
    // The window's background is white: SwiftUI's own drawing over a clear
    // window does not reach `cacheDisplay`.
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return "no rep" }
    h.cacheDisplay(in: h.bounds, to: rep)
    let sx = Double(rep.pixelsWide) / Double(h.bounds.width)
    var minG = 1.0, darkest = 1.0
    var count = 0, x0 = Int.max, x1 = -1, y0 = Int.max, y1 = -1
    for y in 0..<rep.pixelsHigh {
        for x in Int(fromX * sx)..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
            darkest = min(darkest, (r + g + b) / 3)
            if r > 0.8, r - g > 0.35, abs(g - b) < 0.12 {
                count += 1
                minG = min(minG, g)
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
    }
    let ink = fromX > 0 ? " darkest=\(String(format: "%.2f", darkest))" : ""
    guard count > 0 else { return "red=0" + ink }
    return "red=\(count) x=\(Int(Double(x0) / sx))...\(Int(Double(x1) / sx)) y=\(Int(Double(y0) / sx))...\(Int(Double(y1) / sx)) minG=\(String(format: "%.2f", minG))" + ink
}

@MainActor func sample<V: View>(_ name: String, width: CGFloat = 320, height: CGFloat = 60, titled: Bool = false,
    fromX: Double = 0, @ViewBuilder _ view: () -> V) {
    let size = CGSize(width: width, height: height)
    let built = view()
    let styled = reds(built.foregroundStyle(red).padding(8).frame(width: width, height: height, alignment: .topLeading).background(Color.white),
        size: size, titled: titled, fromX: fromX)
    let plain = reds(built.padding(8).frame(width: width, height: height, alignment: .topLeading).background(Color.white),
        size: size, titled: titled, fromX: fromX)
    print("\(name): styled \(styled) | plain \(plain)")
}

struct Row: Identifiable { let id: Int; let name: String }

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            sample("Text") { Text("Hello") }
            sample("Label") { Label("Hello", systemImage: "star") }
            sample("Button.automatic") { Button("Hello") {} }
            sample("Button.bordered") { Button("Hello") {}.buttonStyle(.bordered) }
            sample("Button.borderedProminent") { Button("Hello") {}.buttonStyle(.borderedProminent) }
            sample("Button.borderless") { Button("Hello") {}.buttonStyle(.borderless) }
            sample("Button.plain") { Button("Hello") {}.buttonStyle(.plain) }
            sample("Button.link") { Button("Hello") {}.buttonStyle(.link) }
            sample("Toggle.switch") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.switch) }
            sample("Toggle.switch labelsHidden") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.switch).labelsHidden() }
            sample("Toggle.checkbox") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.checkbox) }
            sample("Toggle.checkbox labelsHidden") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.checkbox).labelsHidden() }
            sample("Toggle.button") { Toggle("Hello", isOn: .constant(false)).toggleStyle(.button) }
            sample("Picker.menu") { Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu).fixedSize() }
            sample("Picker.menu labelsHidden") { Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu).labelsHidden().fixedSize() }
            sample("Picker.segmented labelsHidden") { Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
            sample("Picker.radioGroup labelsHidden", height: 80) { Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.radioGroup).labelsHidden() }
            sample("Picker.inline labelsHidden", height: 80) { Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.inline).labelsHidden() }
            sample("Stepper") { Stepper("Hello", value: .constant(1)) }
            sample("Stepper labelsHidden") { Stepper("Hello", value: .constant(1)).labelsHidden() }
            sample("Slider") { Slider(value: .constant(0.5)) { Text("Hello") }.frame(width: 200) }
            sample("Slider labelsHidden") { Slider(value: .constant(0.5)) { Text("Hello") }.labelsHidden().frame(width: 200) }
            sample("TextField text") { TextField("Name", text: .constant("Hello")).frame(width: 200) }
            sample("TextField placeholder") { TextField("Name", text: .constant("")).frame(width: 200) }
            sample("TextField.plain text") { TextField("Name", text: .constant("Hello")).textFieldStyle(.plain).frame(width: 200) }
            sample("TextField.roundedBorder text") { TextField("Name", text: .constant("Hello")).textFieldStyle(.roundedBorder).frame(width: 200) }
            sample("TextField.squareBorder text") { TextField("Name", text: .constant("Hello")).textFieldStyle(.squareBorder).frame(width: 200) }
            sample("SecureField text") { SecureField("Name", text: .constant("Hello")).frame(width: 200) }
            sample("SecureField placeholder") { SecureField("Name", text: .constant("")).frame(width: 200) }
            sample("TextEditor", height: 80) { TextEditor(text: .constant("Hello")).frame(width: 200, height: 50) }
            sample("DatePicker") { DatePicker("Hello", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date).fixedSize() }
            sample("DatePicker labelsHidden") { DatePicker("Hello", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date).labelsHidden().fixedSize() }
            sample("ColorPicker") { ColorPicker("Hello", selection: .constant(.blue)).fixedSize() }
            sample("ColorPicker labelsHidden") { ColorPicker("Hello", selection: .constant(.blue)).labelsHidden().fixedSize() }
            sample("Link") { Link("Hello", destination: URL(string: "https://swift.org")!) }
            sample("Menu") { Menu("Hello") { Button("One") {} }.fixedSize() }
            sample("Menu.borderlessButton") { Menu("Hello") { Button("One") {} }.menuStyle(.borderlessButton).fixedSize() }
            sample("Menu.button") { Menu("Hello") { Button("One") {} }.menuStyle(.button).fixedSize() }
            sample("DisclosureGroup") { DisclosureGroup("Hello") { Text("Body") } }
            sample("DisclosureGroup label blue") { DisclosureGroup { Text("Body") } label: { Text("Hello").foregroundStyle(blue) } }
            sample("List row", height: 80) { List { Text("Hello") } }
            sample("List section header (row blue)", height: 100) { List { Section("Header") { Text("Row").foregroundStyle(blue) } } }
            sample("Table cells and header", height: 100) { Table([Row(id: 1, name: "Hello")]) { TableColumn("Name", value: \Row.name) } }
            sample("Table header (cells blue)", height: 100) {
                Table([Row(id: 1, name: "Hello")]) { TableColumn("Name") { (row: Row) in Text(row.name).foregroundStyle(blue) } }
            }
            sample("Form.grouped TextField label", height: 100) { Form { TextField("Label", text: .constant("Value")) }.formStyle(.grouped) }
            // Right of x=150, the value alone: `darkest` is the darkest grey there,
            // near 0 for the primary ink and about 0.5 for the secondary.
            sample("Form.grouped LabeledContent Text value (x>=150)", height: 100, fromX: 150) {
                Form { LabeledContent("Name", value: "Alice") }.formStyle(.grouped)
            }
            sample("Form.grouped LabeledContent TextField value (x>=150)", height: 100, fromX: 150) {
                Form { LabeledContent("Email") { TextField("", text: .constant("bob")) } }.formStyle(.grouped)
            }
            sample("Form.columns Toggle", height: 80) { Form { Toggle("Label", isOn: .constant(true)) }.formStyle(.columns) }
            sample("GroupBox (content blue)", height: 100) { GroupBox("Title") { Text("Body").foregroundStyle(blue) } }
            sample("GroupBox (title blue)", height: 100) { GroupBox { Text("Body") } label: { Text("Title").foregroundStyle(blue) } }
            sample("LabeledContent") { LabeledContent("Key", value: "Value").frame(width: 200) }
            sample("LabeledContent (key blue)") { LabeledContent { Text("Value") } label: { Text("Key").foregroundStyle(blue) }.frame(width: 200) }
            sample("ProgressView label", height: 80) { ProgressView("Hello", value: 0.5).frame(width: 200) }
            sample("ProgressView labelsHidden") { ProgressView("Hello", value: 0.5).labelsHidden().frame(width: 200) }
            sample("Gauge", height: 80) { Gauge(value: 0.5) { Text("Hello") }.frame(width: 200) }
            sample("Gauge labelsHidden", height: 80) { Gauge(value: 0.5) { Text("Hello") }.labelsHidden().frame(width: 200) }
            sample("TabView labels (content blue)", height: 120) { TabView { Text("Body").foregroundStyle(blue).tabItem { Text("Tab") } } }
            sample("NavigationLink", height: 80) { NavigationStack { NavigationLink("Hello") { Text("x") } } }
            sample("NavigationLink in List", height: 80) { NavigationStack { List { NavigationLink("Hello") { Text("x") } } } }
            sample("searchable (content blue)", width: 500, height: 120, titled: true) {
                NavigationStack { Text("Body").foregroundStyle(blue).searchable(text: .constant("Hello")) }
            }
        }
    }
}
