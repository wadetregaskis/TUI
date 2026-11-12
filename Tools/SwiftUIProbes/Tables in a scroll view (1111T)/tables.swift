import AppKit
import SwiftUI

// TABLE-IN-SCROLL-HEIGHT and TABLE-IN-SCROLL-BLANK (bug reports, 2026-11-11):
// several Tables of different sizes, each under a title, inside a vertical
// ScrollView with no frame and no modifiers:
//
//     ScrollView { VStack { ForEach(tables) { t in VStack { Text(t.title); Table(t.rows) { … } } } } }
//
// What height does SwiftUI give each Table, and does it draw rows (or row
// stripes) past the last one? Tables of 2, 5 and 30 rows, in windows 300, 600
// and 1200 points tall (400 wide). For each Table it prints:
//
// - `frame`: the height SwiftUI laid the Table out at (a GeometryReader in its
//   background);
// - `rows`: the NSTableView's row count, row height and the height its rows
//   and header need (`need`);
// - `scroll`: the height of the NSScrollView SwiftUI made for it, its visible
//   document height, the document's height, and whether it can scroll
//   (`scrolls` = document taller than the visible area);
// - `alt`: whether the NSTableView draws alternating row backgrounds;
// - `below`: the colours SwiftUI drew down the middle of the Table's first
//   column, one sample per row height, starting one row past the last row and
//   running to the Table's bottom edge (`-` when no space is left there).
//
// Then the same layout with each modifier a reader might reach for, in the
// 600-point window, to say what each does in SwiftUI: `.scrollDisabled(true)`,
// `.fixedSize(horizontal: false, vertical: true)`, `.frame(height: 150)`,
// `.frame(minHeight: 150)`, `.alternatingRowBackgrounds(.disabled)`, and the
// last two together.
// Finally a Table's sizes under a Layout's proposals: `.unspecified` (its
// ideal), zero and infinity.
//
//   swiftc -parse-as-library tables.swift -o /tmp/tables && /tmp/tables

struct Row: Identifiable { let id: Int; var name: String { "Row \(id)" }; var value: String { "v\(id * 7)" } }
struct Group: Identifiable { let id: Int; let rows: [Row]; var title: String { "Table of \(rows.count)" } }
let groups = [2, 5, 30].enumerated().map { Group(id: $0.offset, rows: (1...$0.element).map(Row.init)) }

enum Variant: String, CaseIterable {
    case plain, scrollDisabled, fixedSizeVertical, frameHeight150, frameMinHeight150, alternatingDisabled
    case frameHeight150AlternatingDisabled
}

@MainActor final class Frames { static var heights: [Int: CGFloat] = [:] }

struct OneTable: View {
    let group: Group
    let variant: Variant
    var body: some View {
        let table = Table(group.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Value", value: \Row.value)
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { Frames.heights[group.id] = proxy.size.height }
                .onChange(of: proxy.size.height) { _, new in Frames.heights[group.id] = new }
        })
        switch variant {
        case .plain: table
        case .scrollDisabled: table.scrollDisabled(true)
        case .fixedSizeVertical: table.fixedSize(horizontal: false, vertical: true)
        case .frameHeight150: table.frame(height: 150)
        case .frameMinHeight150: table.frame(minHeight: 150)
        case .alternatingDisabled: table.alternatingRowBackgrounds(.disabled)
        case .frameHeight150AlternatingDisabled: table.frame(height: 150).alternatingRowBackgrounds(.disabled)
        }
    }
}

struct Reported: View {
    let variant: Variant
    var body: some View {
        ScrollView {
            VStack {
                ForEach(groups) { group in
                    VStack {
                        Text(group.title)
                        OneTable(group: group, variant: variant)
                    }
                }
            }
        }
    }
}

/// Records a Table's size under each proposal, the first time it is asked.
@MainActor final class Asked { static var done = false }
struct Proposals: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if MainActor.assumeIsolated({ Asked.done }) { return proposal.replacingUnspecifiedDimensions() }
        MainActor.assumeIsolated { Asked.done = true }
        for (name, p) in [("unspecified", ProposedViewSize.unspecified), ("zero", .zero), ("infinity", .infinity),
                          ("400 x nil", ProposedViewSize(width: 400, height: nil))] {
            let size = subviews[0].sizeThatFits(p)
            print("  proposal \(name): \(size.width) x \(size.height)")
        }
        return proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

@MainActor var keep: [NSWindow] = []
@MainActor func spin(_ s: Double = 0.5) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func host<V: View>(_ v: V, height: CGFloat) -> NSHostingView<AnyView> {
    let size = CGSize(width: 400, height: height)
    let h = NSHostingView(rootView: AnyView(v))
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
    spin()
    return h
}

@MainActor func tables(_ v: NSView) -> [NSTableView] {
    var out: [NSTableView] = []
    if let t = v as? NSTableView { out.append(t) }
    for c in v.subviews { out += tables(c) }
    return out
}

func hex(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "?" }
    return String(format: "%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                  Int(c.blueComponent * 255))
}

@MainActor func report(_ h: NSHostingView<AnyView>) {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return }
    h.cacheDisplay(in: h.bounds, to: rep)
    let scale = CGFloat(rep.pixelsHigh) / h.bounds.height
    // Tables in document order, top to bottom.
    let found = tables(h).sorted { a, b in
        let ya = a.convert(a.bounds, to: nil).maxY, yb = b.convert(b.bounds, to: nil).maxY
        return ya > yb
    }
    for (index, t) in found.enumerated() {
        guard let sv = t.enclosingScrollView else { continue }
        let rowHeight = t.numberOfRows > 0 ? t.rect(ofRow: 0).height : t.rowHeight
        let header = t.headerView?.frame.height ?? 0
        let need = CGFloat(t.numberOfRows) * rowHeight + header
        let visible = sv.contentView.documentVisibleRect.height
        let document = sv.documentView?.frame.height ?? 0
        let scrolls = document > visible + 0.5
        print("  table \(index): frame=\(Frames.heights[index].map { "\($0)" } ?? "?")",
              "rows=\(t.numberOfRows)x\(rowHeight)+header \(header) need=\(need)",
              "scroll=\(sv.frame.height) visible=\(visible) document=\(document) scrolls=\(scrolls)",
              "alt=\(t.usesAlternatingRowBackgroundColors) style=\(t.style.rawValue)")
        // Colours below the last row, in the table's own (flipped) space.
        guard t.numberOfRows > 0 else { continue }
        let lastRowBottom = t.rect(ofRow: t.numberOfRows - 1).maxY
        let x = t.rect(ofColumn: 0).midX
        var samples: [String] = []
        let clipBottom = sv.contentView.documentVisibleRect.maxY
        var y = lastRowBottom + rowHeight / 2
        while y < clipBottom {
            let inHost = t.convert(NSPoint(x: x, y: y), to: h)
            let top = h.isFlipped ? inHost.y : h.bounds.height - inHost.y
            if top >= 0, top < h.bounds.height {
                samples.append(hex(rep.colorAt(x: Int(inHost.x * scale), y: Int(top * scale))))
            }
            y += rowHeight
        }
        // And the last row itself and the one before, for reference.
        func at(_ row: Int) -> String {
            let p = t.convert(NSPoint(x: x, y: t.rect(ofRow: row).midY), to: h)
            let top = h.isFlipped ? p.y : h.bounds.height - p.y
            guard top >= 0, top < h.bounds.height else { return "off" }
            return hex(rep.colorAt(x: Int(p.x * scale), y: Int(top * scale)))
        }
        let lastTwo = t.numberOfRows >= 2 ? "\(at(t.numberOfRows - 2)) \(at(t.numberOfRows - 1))" : at(0)
        print("    last rows: \(lastTwo); below: \(samples.isEmpty ? "-" : samples.joined(separator: " "))")
    }
}

@main struct Probe {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        for height in [300.0, 600, 1200] {
            Frames.heights = [:]
            print("plain, window 400 x \(Int(height))")
            report(host(Reported(variant: .plain), height: height))
        }
        for variant in Variant.allCases where variant != .plain {
            Frames.heights = [:]
            print("\(variant.rawValue), window 400 x 600")
            report(host(Reported(variant: variant), height: 600))
        }
        for count in [2, 30] {
            Asked.done = false
            print("Table of \(count) under a Layout's proposals")
            _ = host(Proposals {
                Table(groups.first { $0.rows.count == count }!.rows) {
                    TableColumn("Name", value: \Row.name)
                    TableColumn("Value", value: \Row.value)
                }
            }, height: 600)
        }
    }
}
