// Which rows a macOS SwiftUI Table tints: sample each row's background pixel
// at the right edge of the row rect (no text there).
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift phase.swift -o phase && ./phase
import SwiftUI
import AppKit

struct P: Identifiable { var id: Int; var n: String }
let rows = (0..<6).map { P(id: $0, n: "r\($0)") }

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
    for t in tables(h) {
        var line = "\(name): stripes=\(t.usesAlternatingRowBackgroundColors) colours=\(NSColor.alternatingContentBackgroundColors.map { $0.usingColorSpace(.sRGB).map { String(format: "%.3f", $0.redComponent) } ?? "?" })"
        for r in 0..<min(t.numberOfRows, 9) {
            let rect = t.convert(t.rect(ofRow: r), to: h)
            // A point near the row's right edge, mid-height; flipped as the rep is top-down.
            let x = Int(rect.maxX - 40) * Int(rep.pixelsWide) / Int(h.bounds.width)
            let yView = h.isFlipped ? rect.midY : h.bounds.height - rect.midY
            let y = Int(yView) * Int(rep.pixelsHigh) / Int(h.bounds.height)
            let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            line += String(format: " row%d=%.3f", r, c?.redComponent ?? -1)
        }
        print(line)
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            sample("automatic", Table(rows) { TableColumn("N", value: \.n) })
            sample("bordered", Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.bordered))
            sample("inset", Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.inset))
            sample("list+alt", List(rows) { Text($0.n) }.alternatingRowBackgrounds())
            sample("sections", List {
                Section("A") { ForEach(rows.prefix(3)) { Text($0.n) } }
                Section("B") { ForEach(rows.suffix(3)) { Text($0.n) } }
            }.alternatingRowBackgrounds())
        }
    }
}
