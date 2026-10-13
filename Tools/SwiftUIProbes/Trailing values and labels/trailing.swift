import SwiftUI
import AppKit

// BUGS13 fix round 1 (the review of e9c065a9e): where SwiftUI draws the lines
// of a multi-line value or label that the built-in LabeledContent and Form
// layouts put at a trailing edge: each line flush with the trailing edge (the
// lines aligned trailing, as `.multilineTextAlignment(.trailing)` aligns
// them), or the lines leading-aligned inside a block placed at the trailing
// edge (a frame's alignment alone, `../Ragged text in a larger frame`)?
// Offscreen NSHostingView, after that probe. The value is drawn black and the
// label red, so the two can share a row and still be told apart; each line's
// ink is reported in characters from the hosting view's leading edge.

let canvas = CGSize(width: 520, height: 300)
let fontSize: CGFloat = 20

@MainActor var keep: [NSWindow] = []
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
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func capture(_ h: NSView) -> NSBitmapImageRep? {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return nil }
    h.cacheDisplay(in: h.bounds, to: rep)
    return rep
}

enum Ink { case value, label }

func ink(_ c: NSColor?) -> Ink? {
    guard let c = c?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { return nil }
    let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
    if r < 0.45, g < 0.45, b < 0.45 { return .value }
    if r > 0.6, g < 0.45, b < 0.45 { return .label }
    return nil
}

/// One character's advance in the probe's font, in points.
let advance = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width

func cells(_ v: CGFloat) -> String {
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}

/// Each line of `kind`'s ink: where it starts and ends, in characters.
@MainActor func lines(_ rep: NSBitmapImageRep, _ kind: Ink) -> [String] {
    let scale = Double(rep.pixelsWide) / canvas.width
    var found: [(x0: Int, x1: Int)] = []
    var inLine = false
    for py in 0..<rep.pixelsHigh {
        var x0 = Int.max
        var x1 = -1
        for px in 0..<rep.pixelsWide where ink(rep.colorAt(x: px, y: py)) == kind {
            x0 = min(x0, px)
            x1 = max(x1, px)
        }
        if x1 >= 0 {
            if inLine {
                found[found.count - 1].x0 = min(found[found.count - 1].x0, x0)
                found[found.count - 1].x1 = max(found[found.count - 1].x1, x1)
            } else {
                found.append((x0, x1))
                inLine = true
            }
        } else {
            inLine = false
        }
    }
    return found.map { "\(cells(CGFloat($0.x0) / scale))..\(cells(CGFloat($0.x1 + 1) / scale))" }
}

@MainActor func show<V: View>(_ label: String, _ v: V) {
    let h = host(
        v.font(.system(size: fontSize, design: .monospaced))
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading).background(.white))
    spin()
    guard let rep = capture(h) else { print("\(label) || no capture"); return }
    print("\(label)\n    value lines: \(lines(rep, .value).joined(separator: " | "))"
        + "\n    label lines: \(lines(rep, .label).joined(separator: " | "))")
}

let value = "short\na much longer line"
let wrapping = "a value long enough that it has to wrap onto more lines"

@MainActor func valueText(_ s: String) -> some View { Text(s).foregroundStyle(.black) }
@MainActor func labelText(_ s: String) -> some View { Text(s).foregroundStyle(.red) }

@MainActor func run() {
    print("advance=\(advance) points; ink in characters from the hosting view's leading edge")
    print("canvas \(cells(canvas.width)) characters wide")
    show("LabeledContent, no Form",
         LabeledContent { valueText(value) } label: { labelText("Notes") })
    show("LabeledContent, no Form, .frame(width: 30)",
         LabeledContent { valueText(value) } label: { labelText("Notes") }.frame(width: 30 * advance))
    show("Form(.grouped) { LabeledContent }",
         Form { LabeledContent { valueText(value) } label: { labelText("Notes") } }.formStyle(.grouped))
    show("Form(.columns) { LabeledContent }",
         Form { LabeledContent { valueText(value) } label: { labelText("Notes") } }.formStyle(.columns))
    show("Form(.columns) { LabeledContent, two-line label }",
         Form {
             LabeledContent { valueText("v") } label: { labelText("a\nlonger label") }
         }.formStyle(.columns))
    show("Form(.columns) { two LabeledContents, the first label two lines }",
         Form {
             LabeledContent { valueText("v") } label: { labelText("a\nlonger label") }
             LabeledContent { valueText("w") } label: { labelText("a much longer label") }
         }.formStyle(.columns))
    show("Form(.grouped) { LabeledContent, wrapping value }",
         Form { LabeledContent { valueText(wrapping) } label: { labelText("Notes") } }.formStyle(.grouped)
            .frame(width: 30 * advance))
    show("Form(.columns) { LabeledContent, wrapping value }",
         Form { LabeledContent { valueText(wrapping) } label: { labelText("Notes") } }.formStyle(.columns)
            .frame(width: 30 * advance))
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
