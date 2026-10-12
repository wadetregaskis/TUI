import SwiftUI
import AppKit

// Paint-is-truth helpers: classify each pixel down one column (or along one row)
// into a named colour and print the runs, in points.

let palette: [(String, (Double, Double, Double))] = [
    ("H0", (1, 0, 0)), ("H1", (0, 1, 0)), ("H2", (0, 0, 1)),
    ("r0", (1, 1, 0)), ("r1", (0, 1, 1)), ("r2", (1, 0, 1)),
    ("F0", (1, 0.5, 0)), ("F1", (0.5, 0, 1)), ("F2", (0, 0.5, 0.5)),
    ("bg", (1, 1, 1)), ("blk", (0, 0, 0)), ("grey", (0.5, 0.5, 0.5)),
]

func classify(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "?" }
    if c.alphaComponent < 0.1 { return "clear" }
    var best = "?"
    var bestD = 1e9
    for (name, (r, g, b)) in palette {
        let d = pow(c.redComponent - r, 2) + pow(c.greenComponent - g, 2) + pow(c.blueComponent - b, 2)
        if d < bestD { bestD = d; best = name }
    }
    return bestD < 0.08 ? best : String(format: "~(%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent)
}

@MainActor func capture(_ h: NSView) -> NSBitmapImageRep? {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return nil }
    h.cacheDisplay(in: h.bounds, to: rep)
    return rep
}

/// Runs down the column at point x, as "name@y+len" in points.
@MainActor func columnRuns(_ rep: NSBitmapImageRep, x: Double, pointsHigh: Double) -> String {
    let scale = Double(rep.pixelsHigh) / pointsHigh
    let px = Int(x * scale)
    var runs: [(String, Int, Int)] = []
    for py in 0..<rep.pixelsHigh {
        let name = classify(rep.colorAt(x: px, y: py))
        if let last = runs.last, last.0 == name {
            runs[runs.count - 1].2 += 1
        } else {
            runs.append((name, py, 1))
        }
    }
    return runs.map { "\($0.0)@\(Int(Double($0.1) / scale))+\(Int(Double($0.2) / scale))" }.joined(separator: " ")
}

@MainActor func rowRuns(_ rep: NSBitmapImageRep, y: Double, pointsWide: Double) -> String {
    let scale = Double(rep.pixelsWide) / pointsWide
    let py = Int(y * scale)
    var runs: [(String, Int, Int)] = []
    for px in 0..<rep.pixelsWide {
        let name = classify(rep.colorAt(x: px, y: py))
        if let last = runs.last, last.0 == name {
            runs[runs.count - 1].2 += 1
        } else {
            runs.append((name, px, 1))
        }
    }
    return runs.map { "\($0.0)@\(Int(Double($0.1) / scale))+\(Int(Double($0.2) / scale))" }.joined(separator: " ")
}

@MainActor func scroll(_ h: NSView, to p: NSPoint) {
    guard let sv = findScrollViews(h).first else { print("  (no NSScrollView)"); return }
    sv.contentView.scroll(to: p)
    sv.reflectScrolledClipView(sv.contentView)
    spin(0.25)
}

@MainActor func clipOrigin(_ h: NSView) -> NSPoint {
    findScrollViews(h).first?.contentView.bounds.origin ?? .zero
}
