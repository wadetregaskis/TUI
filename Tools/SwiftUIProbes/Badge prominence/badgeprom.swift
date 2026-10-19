// Where a .badgeProminence(_:) written inside a List row reaches that row's
// badge: around the .badge(_:) (outside it), within it (inside), or neither.
// Prints, per row, the count of non-background pixels and the darkest/lightest
// grey in the badge's region (the row's right 70 points), so a capsule
// (.standard: many light-grey pixels) tells apart from bare text (.decreased).
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift badgeprom.swift -o bp && ./bp
import SwiftUI
import AppKit

@MainActor func tables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for c in v.subviews { out += tables(c) }
    return out
}

@MainActor func sample<V: View>(_ name: String, _ view: V) {
    let h = host(view, size: CGSize(width: 300, height: 260))
    spin(0.6)
    h.layoutSubtreeIfNeeded()
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { print("no rep"); return }
    h.cacheDisplay(in: h.bounds, to: rep)
    let sx = Double(rep.pixelsWide) / Double(h.bounds.width)
    let sy = Double(rep.pixelsHigh) / Double(h.bounds.height)
    for t in tables(h) {
        for r in 0..<t.numberOfRows {
            let rect = t.convert(t.rect(ofRow: r), to: h)
            var count = 0, light = 0, dark = 0
            var minG = 1.0
            var maxNonWhite = 0.0
            let x0 = Int((rect.maxX - 70) * sx), x1 = Int((rect.maxX - 2) * sx)
            let yTop = h.isFlipped ? rect.minY : h.bounds.height - rect.maxY
            let y0 = Int((yTop + 1) * sy), y1 = Int((yTop + rect.height - 1) * sy)
            for y in y0..<y1 {
                for x in x0..<x1 {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let g = (c.redComponent + c.greenComponent + c.blueComponent) / 3
                    if g < 0.985 {
                        count += 1
                        if g > 0.75 { light += 1 } else { dark += 1 }
                        minG = min(minG, g)
                        maxNonWhite = max(maxNonWhite, g)
                    }
                }
            }
            print(String(format: "%@ row%d: inked=%d light=%d dark=%d darkest=%.3f", name, r, count, light, dark, minG))
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            sample("rows", List {
                Text("standard").badge(5)
                Text("around").badge(5).badgeProminence(.decreased)
                Text("within").badgeProminence(.decreased).badge(5)
                Text("aroundPadded").badge(5).padding(.leading, 0).badgeProminence(.decreased)
                Text("paddedBadge").badge(5).padding(.leading, 0)
                Text("increasedInList").badge(5).badgeProminence(.increased)
            })
            sample("listDecreased", List {
                Text("standard").badge(5)
                Text("inner-standard").badge(5).badgeProminence(.standard)
            }.badgeProminence(.decreased))
        }
    }
}
