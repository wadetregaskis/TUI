import SwiftUI
import AppKit

// BUGS13 item 5: where SwiftUI draws the lines of a multi-line Text whose
// lines differ in width ("aaaa" over "bb") in a frame larger than the Text:
// each line placed by the frame's alignment on its own width, or the Text
// placed as one block, its lines aligned inside it by its own
// multilineTextAlignment? Offscreen NSHostingView (after
// ../Alignment guides/guide2.swift); the ink of each line is found in the
// pixels drawn (after ../Pinned section headers and footers/scan.swift).
// Monospaced, so one character's advance stands in for a terminal cell.

let canvas = CGSize(width: 400, height: 240)
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
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func capture(_ h: NSView) -> NSBitmapImageRep? {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return nil }
    h.cacheDisplay(in: h.bounds, to: rep)
    return rep
}

func isInk(_ c: NSColor?) -> Bool {
    guard let c = c?.usingColorSpace(.sRGB) else { return false }
    return c.alphaComponent > 0.5 && c.redComponent + c.greenComponent + c.blueComponent < 1.5
}

@MainActor final class Box { static var frame: CGRect = .null }

/// Records the frame of the view it is the background of, in the window.
struct Reader: View {
    var body: some View {
        GeometryReader { p in
            let r = p.frame(in: .global)
            let _ = MainActor.assumeIsolated { Box.frame = r }
            Color.clear
        }
    }
}

/// One character's advance in the probe's font, in points.
let advance = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).maximumAdvancement.width

/// `v` points as characters, to two places unless it is within a sixth of a
/// whole number (a glyph's ink sits a little inside its advance).
func cells(_ v: CGFloat) -> String {
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}

/// Prints, for each line of ink, where it starts and ends, in characters from
/// the frame's leading edge.
@MainActor func show<V: View>(_ label: String, _ v: V) {
    Box.frame = .null
    let h = host(
        v.background(Reader()).font(.system(size: fontSize, design: .monospaced)).foregroundStyle(.black)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading).background(.white))
    spin()
    guard let rep = capture(h) else { print("\(label) || no capture"); return }
    let scale = Double(rep.pixelsWide) / canvas.width
    var lines: [(x0: Int, x1: Int)] = []
    var inLine = false
    for py in 0..<rep.pixelsHigh {
        var x0 = Int.max
        var x1 = -1
        for px in 0..<rep.pixelsWide where isInk(rep.colorAt(x: px, y: py)) {
            x0 = min(x0, px)
            x1 = max(x1, px)
        }
        if x1 >= 0 {
            if inLine {
                lines[lines.count - 1].x0 = min(lines[lines.count - 1].x0, x0)
                lines[lines.count - 1].x1 = max(lines[lines.count - 1].x1, x1)
            } else {
                lines.append((x0, x1))
                inLine = true
            }
        } else {
            inLine = false
        }
    }
    let frame = Box.frame
    let parts = lines.enumerated().map { index, line in
        let start = CGFloat(line.x0) / scale - frame.minX
        let end = CGFloat(line.x1 + 1) / scale - frame.minX
        return "line\(index + 1) ink \(cells(start))..\(cells(end))"
    }
    print("\(label) || frame w=\(cells(frame.width)) | \(parts.joined(separator: " | "))")
}

@MainActor func run() {
    print("advance=\(advance) points; ink in characters from the frame's leading edge")
    let text = Text("aaaa\nbb")
    let tall = 5 * fontSize * 1.3
    let wide = 10 * advance
    show("Text(\"aaaa\\nbb\") alone", text)
    show(".frame(height: 5 lines)", text.frame(height: tall))
    show(".frame(width: 10)", text.frame(width: wide))
    show(".frame(width: 10, alignment: .leading)", text.frame(width: wide, alignment: .leading))
    show(".frame(width: 10, alignment: .trailing)", text.frame(width: wide, alignment: .trailing))
    show(".frame(width: 10, height: 5 lines)", text.frame(width: wide, height: tall))
    show(".frame(minWidth: 10)", text.frame(minWidth: wide))
    show(".frame(minHeight: 5 lines)", text.frame(minHeight: tall))
    show(".frame(maxWidth: .infinity)", text.frame(maxWidth: .infinity))
    show(".multilineTextAlignment(.center).frame(width: 10)", text.multilineTextAlignment(.center).frame(width: wide))
    show(".multilineTextAlignment(.trailing).frame(width: 10, alignment: .leading)",
         text.multilineTextAlignment(.trailing).frame(width: wide, alignment: .leading))
    show("VStack(alignment: .leading) { aaaa; bb }.frame(width: 10)",
         VStack(alignment: .leading, spacing: 0) { Text("aaaa"); Text("bb") }.frame(width: wide))
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    run()
}
