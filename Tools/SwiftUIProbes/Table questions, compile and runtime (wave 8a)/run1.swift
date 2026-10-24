// Runtime questions about SwiftUI's Table on macOS: build with
//   swiftc -parse-as-library -target arm64-apple-macos15 common.swift run1.swift -o run1 && ./run1
import SwiftUI
import AppKit

struct P: Identifiable { var id: Int; var name: String; var age: Int; var kids: [P]? }
let people = (0..<6).map { P(id: $0, name: "Person \($0)", age: 20 + $0, kids: $0 == 0 ? [P(id: 100, name: "Kid", age: 3, kids: nil)] : nil) }

@MainActor func tables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for c in v.subviews { out += tables(c) }
    return out
}

@MainActor func describe(_ tag: String, _ h: NSView) {
    for t in tables(h) {
        let cols = t.tableColumns.map { c in "\(c.title)[w=\(Int(c.width)) min=\(Int(c.minWidth)) max=\(c.maxWidth > 1e6 ? -1 : Int(c.maxWidth)) hidden=\(c.isHidden) resize=\(c.resizingMask.rawValue)]" }
        let heights = (0..<min(t.numberOfRows, 6)).map { Int(t.rect(ofRow: $0).height) }
        print(tag, "rows=\(t.numberOfRows) alt=\(t.usesAlternatingRowBackgroundColors) header=\(t.headerView != nil) style=\(t.style.rawValue) heights=\(heights) autoH=\(t.usesAutomaticRowHeights) rowH=\(t.rowHeight) cols=\(cols) allowsReorder=\(t.allowsColumnReordering) allowsResize=\(t.allowsColumnResizing) gridMask=\(t.gridStyleMask.rawValue)")
        if t.numberOfRows > 0, t.numberOfColumns > 0 {
            for col in 0..<t.numberOfColumns {
                if let cell = t.view(atColumn: col, row: 0, makeIfNecessary: true) {
                    print("   cell col \(col) frame=\(cell.frame)")
                }
            }
        }
    }
}

struct Plain: View {
    var body: some View {
        Table(people) {
            TableColumn("Name", value: \.name)
            TableColumn("Age") { Text("\($0.age)") }
        }
    }
}
struct TwoLine: View {
    var body: some View {
        Table(people) {
            TableColumn("Name") { p in VStack(alignment: .leading) { Text(p.name); Text("second line") } }
            TableColumn("Age") { Text("\($0.age)") }
        }
    }
}
struct LongText: View {
    var body: some View {
        Table(people) {
            TableColumn("Name") { p in Text("A very long text that should not fit in a narrow column at all, it goes on and on and on") }
                .width(80)
            TableColumn("Age") { Text("\($0.age)") }
        }
    }
}
struct Hidden: View {
    var body: some View {
        Table(people) {
            TableColumn("Name", value: \.name)
            TableColumn("Age") { Text("\($0.age)") }.defaultVisibility(.hidden)
        }
    }
}
struct HiddenCust: View {
    @State var cust = TableColumnCustomization<P>()
    var body: some View {
        Table(people, columnCustomization: $cust) {
            TableColumn("Name", value: \.name).customizationID("name")
            TableColumn("Age") { Text("\($0.age)") }.customizationID("age").defaultVisibility(.hidden)
            TableColumn("NoID") { Text("\($0.age)") }.defaultVisibility(.hidden)
        }
        .onAppear {
            print("cust visibility name=\(cust[visibility: "name"]) age=\(cust[visibility: "age"]) missing=\(cust[visibility: "zzz"])")
        }
    }
}
struct Widths: View {
    var body: some View {
        Table(people) {
            TableColumn("Fixed", value: \.name).width(60)
            TableColumn("MinIdealMax", value: \.name).width(min: 40, ideal: 90, max: 200)
            TableColumn("Ideal", value: \.name).width(ideal: 120)
            TableColumn("Default", value: \.name)
        }
    }
}
struct NoHeaders: View {
    var body: some View {
        Table(people) { TableColumn("Name", value: \.name) }.tableColumnHeaders(.hidden)
    }
}
struct Alt: View {
    let b: AlternatingRowBackgroundBehavior
    var body: some View {
        Table(people) { TableColumn("Name", value: \.name) }.alternatingRowBackgrounds(b)
    }
}
struct Styles: View {
    var body: some View {
        VStack {
            Table(people) { TableColumn("Name", value: \.name) }.tableStyle(.bordered)
        }
    }
}
struct Tree: View {
    var body: some View {
        Table(people, children: \.kids) { TableColumn("Name", value: \.name); TableColumn("Age") { Text("\($0.age)") } }
    }
}
struct Sections: View {
    var body: some View {
        Table(of: P.self) { TableColumn("Name", value: \.name) } rows: {
            Section("First") { ForEach(people.prefix(2)) { TableRow($0) } }
            Section { ForEach(people.suffix(2)) { TableRow($0) } } header: { Text("Second") }
        }
    }
}
struct Align: View {
    var body: some View {
        Table(people) {
            TableColumn("Lead") { Text("\($0.age)") }.alignment(.leading)
            TableColumn("Num") { Text("\($0.age)") }.alignment(.numeric)
            TableColumn("Center") { Text("\($0.age)") }.alignment(.center)
            TableColumn("Trail") { Text("\($0.age)") }.alignment(.trailing)
            TableColumn("Auto") { Text("\($0.age)") }
        }
    }
}

@main struct Main {
    static func main() {
        MainActor.assumeIsolated {
            let c = TableColumn("Name", value: \P.name)
            print("standalone column type:", type(of: c))
            let sz = CGSize(width: 600, height: 400)
            describe("plain", host(Plain(), size: sz)); spin(0.3)
            describe("twoLine", host(TwoLine(), size: sz)); spin(0.3)
            describe("longText", host(LongText(), size: sz)); spin(0.3)
            describe("hidden", host(Hidden(), size: sz)); spin(0.3)
            describe("hiddenCust", host(HiddenCust(), size: sz)); spin(0.3)
            describe("widths", host(Widths(), size: sz)); spin(0.3)
            describe("noHeaders", host(NoHeaders(), size: sz)); spin(0.3)
            describe("alt.automatic", host(Alt(b: .automatic), size: sz)); spin(0.3)
            describe("alt.enabled", host(Alt(b: .enabled), size: sz)); spin(0.3)
            describe("alt.disabled", host(Alt(b: .disabled), size: sz)); spin(0.3)
            describe("bordered", host(Styles(), size: sz)); spin(0.3)
            describe("tree", host(Tree(), size: sz)); spin(0.3)
            describe("sections", host(Sections(), size: sz)); spin(0.3)
            describe("align", host(Align(), size: sz)); spin(0.3)
            var cust = TableColumnCustomization<P>()
            print("empty cust visibility:", cust[visibility: "x"])
            cust[visibility: "x"] = .hidden
            print("after set:", cust[visibility: "x"])
            let data = try! JSONEncoder().encode(cust)
            print("encoded:", String(data: data, encoding: .utf8)!)
            cust.resetOrder()
            print("eq empty:", cust == TableColumnCustomization<P>())
            print("behavior all:", TableColumnCustomizationBehavior.all, "reorder", TableColumnCustomizationBehavior.reorder, "resize", TableColumnCustomizationBehavior.resize, "vis", TableColumnCustomizationBehavior.visibility)
        }
    }
}
