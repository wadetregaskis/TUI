// What each TableStyle draws on macOS: the NSTableView style, grid lines,
// stripes, and whether the enclosing scroll view has a border.
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift run3.swift -o run3 && ./run3
import SwiftUI
import AppKit

struct P: Identifiable { var id: Int; var n: String }
let rows = [P(id: 1, n: "a"), P(id: 2, n: "b")]

@MainActor func tables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for c in v.subviews { out += tables(c) }
    return out
}

@MainActor func report<V: View>(_ name: String, _ view: V) {
    let h = host(view, size: CGSize(width: 300, height: 200))
    spin()
    for t in tables(h) {
        let scroll = t.enclosingScrollView
        print(
            "\(name): style=\(t.style.rawValue) effective=\(t.effectiveStyle.rawValue)"
                + " grid=\(t.gridStyleMask.rawValue) stripes=\(t.usesAlternatingRowBackgroundColors)"
                + " scrollBorder=\(scroll.map { String($0.borderType.rawValue) } ?? "none")"
                + " intercell=\(t.intercellSpacing)")
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            report("plain", Table(rows) { TableColumn("N", value: \.n) })
            report("automatic", Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.automatic))
            report("inset", Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.inset))
            report("bordered", Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.bordered))
            report(
                "bordered+stripes",
                Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.bordered)
                    .alternatingRowBackgrounds())
            report(
                "inset-nostripes",
                Table(rows) { TableColumn("N", value: \.n) }.tableStyle(.inset)
                    .alternatingRowBackgrounds(.disabled))
        }
    }
}
