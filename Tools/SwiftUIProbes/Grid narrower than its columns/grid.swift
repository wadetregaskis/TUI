import SwiftUI
import AppKit

// 2026-11-10: what SwiftUI's `Grid` does offered less width than its columns
// ask for. Grids of three and four columns of monospaced text — one column of
// short words, one of a sentence that can wrap, one made rigid by
// `.fixedSize()`, one flexible (`.frame(maxWidth: .infinity)`) — offered their
// ideal width (`[ideal]`, by `.fixedSize()`), then one wider width and
// narrower ones by a fixed outer frame. Offscreen NSHostingView, after ../Flexible frames.
//
// For each offer: the grid's own size, then per column the widest of its cells,
// the column's x and the most lines any of its cells took (`width@x×lines`).
// Widths in characters of the font, heights in lines; the grid is leading-
// aligned with one character between columns, as TUI's default. Each cell sits
// in a pass-through `Layout` (`Spy`) that records the widths it is asked about;
// for the four-column grid an `asked` line lists them per cell, in order.

let fontSize: CGFloat = 20
let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
let advance = nsFont.maximumAdvancement.width
@MainActor var lineHeight: CGFloat = 1
let font = Font.system(size: fontSize, design: .monospaced)

@MainActor var keep: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize) {
    let h = NSHostingView(rootView: v)
    h.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: size), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    keep.append(w)
    h.layoutSubtreeIfNeeded()
}
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Record {
    static var frames: [String: CGRect] = [:]
    static var asked: [String: [String]] = [:]
}

struct Measured: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { p in
            let f = p.frame(in: .named("grid"))
            let _ = MainActor.assumeIsolated { Record.frames[name] = f }
            Color.clear
        })
    }
}

/// Passes its one child through, noting every width it is asked about.
struct Spy: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal)
        MainActor.assumeIsolated {
            let entry = proposal.width.map(cells) ?? "nil"
            if Record.asked[name]?.last != entry { Record.asked[name, default: []].append(entry) }
        }
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

extension View {
    func cell(_ name: String) -> some View { Spy(name: name) { self.modifier(Measured(name: name)) } }
}

func cells(_ v: CGFloat) -> String {
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}
@MainActor func lines(_ v: CGFloat) -> String {
    let c = v / lineHeight
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}

/// One grid under one offer: `offer` characters, or nil for its ideal width.
@MainActor func measure<V: View>(_ name: String, columns: Int, rows: Int, offer: Int?, @ViewBuilder _ grid: () -> V) {
    Record.frames = [:]
    Record.asked = [:]
    let content = grid().coordinateSpace(name: "grid").modifier(Measured(name: "grid")).font(font)
    let size = CGSize(width: 120 * advance, height: 40 * lineHeight)
    if let offer {
        host(content.frame(width: CGFloat(offer) * advance, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading), size: size)
    } else {
        host(content.fixedSize().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading), size: size)
    }
    spin()
    let g = Record.frames["grid"] ?? .zero
    var out = "\(name)\t[\(offer.map(String.init) ?? "ideal")]\tgrid=\(cells(g.width))x\(lines(g.height))"
    for c in 0..<columns {
        let frames = (0..<rows).compactMap { Record.frames["r\($0)c\(c)"] }
        let width = frames.map(\.width).max() ?? 0
        let x = frames.map(\.minX).min() ?? 0
        let tallest = frames.map(\.height).max() ?? 0
        out += "\tc\(c)=\(cells(width))@\(cells(x))×\(lines(tallest))"
    }
    print(out)
}

@MainActor func asked(_ name: String, columns: Int) {
    var out = "  asked\t\(name)"
    for c in 0..<columns {
        for r in 0..<2 { out += "\tr\(r)c\(c)=\((Record.asked["r\(r)c\(c)"] ?? []).joined(separator: ","))" }
    }
    print(out)
}

// The texts: 4 and 6 characters; 11 and a 22-character sentence of four words;
// 7 characters made rigid.
MainActor.assumeIsolated {
    Record.frames = [:]
    host(Text("x").font(font).modifier(Measured(name: "line")).fixedSize(), size: CGSize(width: 200, height: 200))
    spin()
    lineHeight = Record.frames["line"]!.height

    let offers: [Int?] = [nil, 60, 40, 34, 30, 26, 20, 15, 10, 5]
    for offer in offers {
        measure("three text", columns: 3, rows: 2, offer: offer) {
            Grid(alignment: .leading, horizontalSpacing: advance, verticalSpacing: 0) {
                GridRow { Text("Name").cell("r0c0"); Text("Description").cell("r0c1"); Text("Size").cell("r0c2") }
                GridRow {
                    Text("README").cell("r1c0"); Text("A longer line of text").cell("r1c1")
                    Text("2048 KB").cell("r1c2")
                }
            }
        }
    }
    for offer in offers {
        measure("four, rigid and flexible", columns: 4, rows: 2, offer: offer) {
            Grid(alignment: .leading, horizontalSpacing: advance, verticalSpacing: 0) {
                GridRow {
                    Text("Name").cell("r0c0"); Text("Description").cell("r0c1")
                    Text("Size").fixedSize().cell("r0c2"); Color.clear.frame(height: 1).cell("r0c3")
                }
                GridRow {
                    Text("README").cell("r1c0"); Text("A longer line of text").cell("r1c1")
                    Text("2048 KB").fixedSize().cell("r1c2")
                    Text("Flex").frame(maxWidth: .infinity).cell("r1c3")
                }
            }
        }
        asked("four, rigid and flexible", columns: 4)
    }
    for offer in offers {
        measure("three, one line each", columns: 3, rows: 2, offer: offer) {
            Grid(alignment: .leading, horizontalSpacing: advance, verticalSpacing: 0) {
                GridRow { Text("Name").cell("r0c0"); Text("Description").cell("r0c1"); Text("Size").cell("r0c2") }
                GridRow {
                    Text("README").cell("r1c0"); Text("A longer line of text").cell("r1c1")
                    Text("2048 KB").cell("r1c2")
                }
            }
            .lineLimit(1)
        }
    }
    for offer in offers {
        measure("three, unbreakable words", columns: 3, rows: 2, offer: offer) {
            Grid(alignment: .leading, horizontalSpacing: advance, verticalSpacing: 0) {
                GridRow { Text("Name").cell("r0c0"); Text("Description").cell("r0c1"); Text("Size").cell("r0c2") }
                GridRow {
                    Text("README").cell("r1c0"); Text("Unbreakable").cell("r1c1")
                    Text("2048KB").cell("r1c2")
                }
            }
        }
    }
}
