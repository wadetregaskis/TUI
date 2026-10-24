// Where a column's alignment puts a short cell, per TableColumnAlignment.
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift run2.swift -o run2 && ./run2
import SwiftUI
import AppKit

struct P: Identifiable { var id: Int; var n: Int }
let rows = [P(id: 1, n: 7)]

@MainActor func tables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for c in v.subviews { out += tables(c) }
    return out
}
@MainActor func leaves(_ v: NSView, in root: NSView) -> [String] {
    if v.subviews.isEmpty {
        let f = v.convert(v.bounds, to: root)
        return ["\(type(of: v)) x=\(Int(f.minX)) w=\(Int(f.width))"]
    }
    return v.subviews.flatMap { leaves($0, in: root) }
}

struct Aligned: View {
    let alignment: TableColumnAlignment
    var body: some View {
        Table(rows) {
            TableColumn("Value") { Text("\($0.n)") }.alignment(alignment)
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let sz = CGSize(width: 300, height: 200)
            let cases: [(String, TableColumnAlignment)] = [
                ("automatic", .automatic), ("leading", .leading), ("center", .center),
                ("trailing", .trailing), ("numeric", .numeric),
                ("numeric(latn)", .numeric(Locale.NumberingSystem("latn"))),
                ("numeric(arab)", .numeric(Locale.NumberingSystem("arab"))),
                ("numeric(arabext)", .numeric(Locale.NumberingSystem("arabext"))),
                ("numeric(hebr)", .numeric(Locale.NumberingSystem("hebr"))),
            ]
            for (name, a) in cases {
                let h = host(Aligned(alignment: a), size: sz); spin(0.3)
                for t in tables(h) {
                    if let cell = t.view(atColumn: 0, row: 0, makeIfNecessary: true) {
                        let cf = cell.convert(cell.bounds, to: h)
                        print(name, "cell x=\(Int(cf.minX)) w=\(Int(cf.width))", leaves(cell, in: h))
                    }
                    if let header = t.headerView {
                        print("   header", leaves(header, in: h))
                    }
                }
            }
        }
    }
}
