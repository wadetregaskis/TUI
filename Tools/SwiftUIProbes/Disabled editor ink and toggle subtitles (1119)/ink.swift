import AppKit
import SwiftUI

// Two colour questions (probe lane 1119, 2026-11-19):
//
// 1. Does `.disabled(true)` fade or recolour a TextEditor's text: the default
//    ink, a `.foregroundStyle(.red)`, and (macOS 26 API) an attributed
//    editor's runs carrying their own `foregroundColor`? A TextField and an
//    attributed `Text` are drawn beside it for comparison.
// 2. What colour a Toggle's subtitle (the second view of its label) takes
//    under `.foregroundStyle(.red)` and `.foregroundStyle(.red, .blue)`, in the
//    checkbox and switch styles, bare and in a `.grouped` Form.
//
// Each sample is drawn twice with identical layout: the real one, and a blank
// one (the editor's text empty; the toggle's label views at opacity 0). Only
// the pixels that differ belong to the text, so the control's chrome and a
// grouped form's section background drop out. Those pixels are grouped into
// bands of rows (one per text line) and, per band, the probe prints its rows
// (in points), how many pixels differ, and the CORE pixel: the one farthest
// from the blank render's pixel under it, as 8-bit sRGB, with that background
// pixel. Text is drawn at 3x so glyph stems have solid pixels; the core is the
// colour the text is drawn in (over that background), not an antialiased edge.
// The comparison stack shows how a plain `.secondary` Text and a `.secondary`
// shape take a two-level style, apart from any control.
// Calibration rectangles give the exact sRGB of `.red`, `.blue`, `.primary`,
// `.secondary` and `.tertiary` over white.
//
// A TextEditor's NSTextView is read too: its textColor and the storage's
// foreground colour attribute, and whether it is editable and selectable.
// The window is off-screen, borderless and never key; the appearance is Aqua.
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 ink.swift -o "$TMPDIR/ink"
//   "$TMPDIR/ink" | diff ink.out -

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let scale = 3

struct Pixels {
    let width: Int, height: Int
    var rgb: [(Int, Int, Int)]
    func at(_ x: Int, _ y: Int) -> (Int, Int, Int) { rgb[y * width + x] }
}

@MainActor func render<V: View>(_ view: V, size: CGSize) -> (Pixels, NSView) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = hosting
    w.orderFrontRegardless()
    keep.append(w)
    spin()
    hosting.layoutSubtreeIfNeeded()
    let pw = Int(size.width) * scale, ph = Int(size.height) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)!
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    var px = Pixels(width: pw, height: ph, rgb: [])
    px.rgb.reserveCapacity(pw * ph)
    for y in 0..<ph {
        for x in 0..<pw {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            px.rgb.append((Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded())))
        }
    }
    return (px, hosting)
}

func hex(_ c: (Int, Int, Int)) -> String { String(format: "#%02X%02X%02X", c.0, c.1, c.2) }
func dist(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

/// The text's bands: rows where `real` differs from `blank`, grouped.
func bands(_ real: Pixels, _ blank: Pixels) -> [String] {
    var rowsWithInk: [Int: (count: Int, core: (Int, Int, Int), bg: (Int, Int, Int), d: Int)] = [:]
    for y in 0..<real.height {
        var count = 0, best = -1
        var core = (0, 0, 0), bg = (0, 0, 0)
        for x in 0..<real.width {
            let a = real.at(x, y), b = blank.at(x, y)
            let d = dist(a, b)
            guard d > 12 else { continue }
            count += 1
            if d > best { best = d; core = a; bg = b }
        }
        if count > 0 { rowsWithInk[y] = (count, core, bg, best) }
    }
    var out: [String] = []
    var y = 0
    while y < real.height {
        guard rowsWithInk[y] != nil else { y += 1; continue }
        let start = y
        var count = 0, best = -1
        var core = (0, 0, 0), bg = (0, 0, 0)
        while let row = rowsWithInk[y] {
            count += row.count
            if row.d > best { best = row.d; core = row.core; bg = row.bg }
            y += 1
        }
        // A band of a few pixel rows is antialiasing between two lines, not a line.
        guard y - start >= 2 * scale else { continue }
        out.append("y=\(start / scale)...\((y - 1) / scale) n=\(count) core=\(hex(core)) over \(hex(bg))")
    }
    return out
}

@MainActor func sample<V: View, B: View>(_ name: String, width: CGFloat = 320, height: CGFloat = 70,
    _ real: V, blank: B) {
    func framed<T: View>(_ v: T) -> some View {
        v.padding(8).frame(width: width, height: height, alignment: .topLeading).background(Color.white)
    }
    let size = CGSize(width: width, height: height)
    let (a, hosting) = render(framed(real), size: size)
    let (b, _) = render(framed(blank), size: size)
    let found = bands(a, b)
    print("\(name): " + (found.isEmpty ? "no text pixels" : found.joined(separator: " | ")))
    if let tv = textView(in: hosting) {
        let attr = tv.textStorage.flatMap { $0.length > 0 ? $0.attribute(.foregroundColor, at: 0, effectiveRange: nil) : nil }
        func name(_ c: Any?) -> String {
            guard let c = c as? NSColor else { return "nil" }
            let s = c.usingColorSpace(.sRGB).map { String(format: "sRGB(%.3f %.3f %.3f a%.2f)", $0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } ?? "?"
            return "\(c.colorNameComponentIfCatalog) \(s)"
        }
        print("  NSTextView editable=\(tv.isEditable) selectable=\(tv.isSelectable) textColor=\(name(tv.textColor)) storage[0].foregroundColor=\(name(attr))")
        // Whether `.disabled` is in force at all: what a click at the editor's
        // centre would reach, and whether the text view takes the focus when asked.
        let centre = tv.convert(NSPoint(x: tv.bounds.midX, y: 10), to: hosting.superview)
        let hit = hosting.hitTest(centre).map { String(describing: type(of: $0)) } ?? "nil"
        let took = tv.window?.makeFirstResponder(tv) ?? false
        print("  hitTest(centre)=\(hit) makeFirstResponder(textView)=\(took)")
        tv.window?.makeFirstResponder(nil)
    }
}

extension NSColor {
    var colorNameComponentIfCatalog: String { type == .catalog ? "catalog \(colorNameComponent)" : "\(type)" }
}

@MainActor func textView(in v: NSView) -> NSTextView? {
    if let t = v as? NSTextView { return t }
    for s in v.subviews { if let t = textView(in: s) { return t } }
    return nil
}

@MainActor func swatch(_ name: String, _ style: some ShapeStyle) {
    let (a, _) = render(Rectangle().fill(style).frame(width: 20, height: 20).padding(10).background(Color.white),
        size: CGSize(width: 40, height: 40))
    print("swatch \(name) over white: \(hex(a.at(20 * scale, 20 * scale)))")
}

struct ToggleSample: View {
    enum Fg { case none, red, redBlue }
    let fg: Fg, isSwitch: Bool, inForm: Bool, blank: Bool
    var body: some View {
        let toggle = Toggle(isOn: .constant(false)) {
            Text("Title").opacity(blank ? 0 : 1)
            Text("Subtitle").opacity(blank ? 0 : 1)
        }
        let styled = Group {
            if isSwitch { toggle.toggleStyle(.switch) } else { toggle.toggleStyle(.checkbox) }
        }
        let coloured = Group {
            switch fg {
            case .none: styled
            case .red: styled.foregroundStyle(.red)
            case .redBlue: styled.foregroundStyle(.red, .blue)
            }
        }
        if inForm {
            Form { coloured }.formStyle(.grouped)
        } else {
            coloured
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), drawn at \(scale)x, Aqua")
            swatch(".red", Color.red)
            swatch(".blue", Color.blue)
            swatch(".primary", HierarchicalShapeStyle.primary)
            swatch(".secondary", HierarchicalShapeStyle.secondary)
            swatch(".tertiary", HierarchicalShapeStyle.tertiary)
            swatch(".red.secondary", Color.red.secondary)

            print("\n# 1. TextEditor, enabled vs disabled")
            let text = "Hello world"
            for disabled in [false, true] {
                let tag = disabled ? "disabled" : "enabled"
                sample("TextEditor default \(tag)", height: 80,
                    TextEditor(text: .constant(text)).frame(width: 200, height: 50).disabled(disabled),
                    blank: TextEditor(text: .constant("")).frame(width: 200, height: 50).disabled(disabled))
                sample("TextEditor .foregroundStyle(.red) \(tag)", height: 80,
                    TextEditor(text: .constant(text)).foregroundStyle(.red).frame(width: 200, height: 50).disabled(disabled),
                    blank: TextEditor(text: .constant("")).foregroundStyle(.red).frame(width: 200, height: 50).disabled(disabled))
            }
            if #available(macOS 26, *) {
                for disabled in [false, true] {
                    let tag = disabled ? "disabled" : "enabled"
                    var value = AttributedString("Hello")
                    value.foregroundColor = .red
                    value += AttributedString(" world")
                    let blank = AttributedString("")
                    sample("TextEditor(AttributedString) red run + plain run \(tag)", height: 80,
                        TextEditor(text: .constant(value), selection: .constant(AttributedTextSelection()))
                            .frame(width: 200, height: 50).disabled(disabled),
                        blank: TextEditor(text: .constant(blank), selection: .constant(AttributedTextSelection()))
                            .frame(width: 200, height: 50).disabled(disabled))
                }
            } else {
                print("TextEditor(text: Binding<AttributedString>, selection:): unavailable before macOS 26, not run")
            }
            print("\n# 1, for comparison: TextField and an attributed Text")
            for disabled in [false, true] {
                let tag = disabled ? "disabled" : "enabled"
                sample("TextField default \(tag)",
                    TextField("", text: .constant(text)).frame(width: 200).disabled(disabled),
                    blank: TextField("", text: .constant("")).frame(width: 200).disabled(disabled))
                sample("TextField .foregroundStyle(.red) \(tag)",
                    TextField("", text: .constant(text)).foregroundStyle(.red).frame(width: 200).disabled(disabled),
                    blank: TextField("", text: .constant("")).foregroundStyle(.red).frame(width: 200).disabled(disabled))
                var value = AttributedString("Hello")
                value.foregroundColor = .red
                sample("Text(AttributedString) red run \(tag)",
                    Text(value).disabled(disabled), blank: Text(value).opacity(0).disabled(disabled))
            }

            print("\n# 2, for comparison: a VStack: a Text; Text.foregroundStyle(.secondary); a Text under View.foregroundStyle(.secondary); a Rectangle filled .secondary")
            for fg in [ToggleSample.Fg.none, .red, .redBlue] {
                func stack(_ o: Double) -> some View {
                    VStack(alignment: .leading) {
                        Text("Title").opacity(o)
                        // `Text`'s own `foregroundStyle(_:) -> Text`, then `View`'s.
                        Text("Subtitle").foregroundStyle(.secondary).opacity(o)
                        Text("Subtitle").padding(0).foregroundStyle(.secondary).opacity(o)
                        Rectangle().fill(.secondary).frame(width: 40, height: 6).opacity(o)
                    }
                }
                let fgName = fg == .none ? "no style" : fg == .red ? ".foregroundStyle(.red)" : ".foregroundStyle(.red, .blue)"
                switch fg {
                case .none: sample("VStack \(fgName)", height: 100, stack(1), blank: stack(0))
                case .red: sample("VStack \(fgName)", height: 100, stack(1).foregroundStyle(.red), blank: stack(0).foregroundStyle(.red))
                case .redBlue: sample("VStack \(fgName)", height: 100, stack(1).foregroundStyle(.red, .blue), blank: stack(0).foregroundStyle(.red, .blue))
                }
            }

            print("\n# 2. Toggle { Text(\"Title\"); Text(\"Subtitle\") }, off; bands are title then subtitle")
            for inForm in [false, true] {
                for isSwitch in [false, true] {
                    for fg in [ToggleSample.Fg.none, .red, .redBlue] {
                        let where_ = inForm ? "Form.grouped" : "bare"
                        let style = isSwitch ? ".switch" : ".checkbox"
                        let fgName = fg == .none ? "no style" : fg == .red ? ".foregroundStyle(.red)" : ".foregroundStyle(.red, .blue)"
                        sample("\(where_) \(style) \(fgName)", height: inForm ? 90 : 70,
                            ToggleSample(fg: fg, isSwitch: isSwitch, inForm: inForm, blank: false),
                            blank: ToggleSample(fg: fg, isSwitch: isSwitch, inForm: inForm, blank: true))
                    }
                }
            }
        }
    }
}
