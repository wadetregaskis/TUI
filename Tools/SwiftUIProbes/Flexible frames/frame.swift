import SwiftUI
import AppKit

// 2026-10-15: how SwiftUI's flexible frame, `.frame(minWidth:idealWidth:maxWidth:…)`,
// sizes itself and what it offers its content, for a finite maximum and for an
// ideal, under a specified and an unspecified proposal. Offscreen NSHostingView
// (after ../Layout priority/priority.swift); each size is read with a
// GeometryReader in a background. Monospaced text, so one character's advance
// stands in for a terminal cell.
//
// A row is offered `[n]` cells by a fixed outer frame, or nothing — `[ideal]` —
// by `.fixedSize()`, which proposes nil on the axis. `in` is what the content
// was given, `frame` the frame's own size.

let fontSize: CGFloat = 20
let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
let advance = nsFont.maximumAdvancement.width
/// One line of `Text` in this font, measured at start-up (set in `main`).
@MainActor var lineHeight: CGFloat = 1
let font = Font.system(size: fontSize, design: .monospaced)

func w(_ cells: Int) -> CGFloat { CGFloat(cells) * advance }
@MainActor func h(_ lines: Int) -> CGFloat { CGFloat(lines) * lineHeight }

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

@MainActor final class Sizes { static var sizes: [String: CGSize] = [:] }

struct Measured: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { p in
            let s = p.size
            let _ = MainActor.assumeIsolated { Sizes.sizes[name] = s }
            Color.clear
        })
    }
}
extension View { func measured(_ name: String) -> some View { modifier(Measured(name: name)) } }

func cells(_ v: CGFloat) -> String {
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}
@MainActor func rows(_ v: CGFloat) -> String {
    let c = v / lineHeight
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}

/// Across: `offer` cells, or nil for an unspecified width.
@MainActor func across<V: View>(_ name: String, offer: Int?, @ViewBuilder _ v: () -> V) {
    Sizes.sizes = [:]
    let content = v().font(font)
    let size = CGSize(width: 120 * advance, height: 400)
    if let offer {
        host(content.frame(width: CGFloat(offer) * advance, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true), size: size)
    } else {
        host(content.fixedSize().frame(maxWidth: .infinity, alignment: .leading), size: size)
    }
    spin()
    let given = Sizes.sizes["in"].map { cells($0.width) } ?? "?"
    let frame = Sizes.sizes["frame"].map { cells($0.width) } ?? "?"
    print("\(name)\t[\(offer.map(String.init) ?? "ideal")]\tin=\(given) frame=\(frame)")
}

/// Down: `offer` lines, or nil for an unspecified height.
@MainActor func down<V: View>(_ name: String, offer: Int?, @ViewBuilder _ v: () -> V) {
    Sizes.sizes = [:]
    let content = v().font(font)
    let size = CGSize(width: 60 * advance, height: 40 * lineHeight)
    if let offer {
        host(content.frame(height: CGFloat(offer) * lineHeight, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top), size: size)
    } else {
        host(content.fixedSize(horizontal: false, vertical: true).frame(maxHeight: .infinity, alignment: .top), size: size)
    }
    spin()
    let given = Sizes.sizes["in"].map { rows($0.height) } ?? "?"
    let frame = Sizes.sizes["frame"].map { rows($0.height) } ?? "?"
    print("\(name)\t[\(offer.map(String.init) ?? "ideal")]\tin=\(given) frame=\(frame)")
}

let short = "Short"  // 5
let long = "A noticeably longer line of text here"  // 37

MainActor.assumeIsolated {
    Sizes.sizes = [:]
    host(Text("x").font(font).measured("line").fixedSize(), size: CGSize(width: 200, height: 200))
    spin()
    lineHeight = Sizes.sizes["line"]!.height
    for offer in [80, 20, nil] as [Int?] {
        across("short ideal 10", offer: offer) { Text(short).measured("in").frame(idealWidth: w(10)).measured("frame") }
        across("long ideal 10", offer: offer) { Text(long).measured("in").frame(idealWidth: w(10)).measured("frame") }
        across("short ideal 50", offer: offer) { Text(short).measured("in").frame(idealWidth: w(50)).measured("frame") }
        across("clear ideal 10", offer: offer) { Color.clear.measured("in").frame(idealWidth: w(10)).measured("frame") }
        across("short max 30", offer: offer) { Text(short).measured("in").frame(maxWidth: w(30)).measured("frame") }
        across("long max 30", offer: offer) { Text(long).measured("in").frame(maxWidth: w(30)).measured("frame") }
        across("short min 10 max 30", offer: offer) {
            Text(short).measured("in").frame(minWidth: w(10), maxWidth: w(30)).measured("frame")
        }
        across("short min 10", offer: offer) { Text(short).measured("in").frame(minWidth: w(10)).measured("frame") }
        across("long min 10", offer: offer) { Text(long).measured("in").frame(minWidth: w(10)).measured("frame") }
        across("long min 30", offer: offer) { Text(long).measured("in").frame(minWidth: w(30)).measured("frame") }
        across("short ideal 20 max 30", offer: offer) {
            Text(short).measured("in").frame(idealWidth: w(20), maxWidth: w(30)).measured("frame")
        }
        across("short ideal 20 max inf", offer: offer) {
            Text(short).measured("in").frame(idealWidth: w(20), maxWidth: .infinity).measured("frame")
        }
        across("short ideal 40 max 30", offer: offer) {
            Text(short).measured("in").frame(idealWidth: w(40), maxWidth: w(30)).measured("frame")
        }
        across("short min 10 ideal 20", offer: offer) {
            Text(short).measured("in").frame(minWidth: w(10), idealWidth: w(20)).measured("frame")
        }
        across("short min 0 max inf", offer: offer) {
            Text(short).measured("in").frame(minWidth: w(0), maxWidth: .infinity).measured("frame")
        }
        across("short max inf", offer: offer) { Text(short).measured("in").frame(maxWidth: .infinity).measured("frame") }
        across("long max inf", offer: offer) { Text(long).measured("in").frame(maxWidth: .infinity).measured("frame") }
        across("clear max 30", offer: offer) { Color.clear.measured("in").frame(maxWidth: w(30)).measured("frame") }
        across("clear min 10", offer: offer) { Color.clear.measured("in").frame(minWidth: w(10)).measured("frame") }
        across("short max 3", offer: offer) { Text(short).measured("in").frame(maxWidth: w(3)).measured("frame") }
        across("rigid8 max 3", offer: offer) {
            Text("rigidrig").fixedSize().measured("in").frame(maxWidth: w(3)).measured("frame")
        }
        across("rigid8 min 10 max 30", offer: offer) {
            Text("rigidrig").fixedSize().measured("in").frame(minWidth: w(10), maxWidth: w(30)).measured("frame")
        }
    }
    for offer in [10, 2, nil] as [Int?] {
        down("one ideal 3", offer: offer) { Text(short).measured("in").frame(idealHeight: h(3)).measured("frame") }
        down("one max 5", offer: offer) { Text(short).measured("in").frame(maxHeight: h(5)).measured("frame") }
        down("one min 2 max 5", offer: offer) {
            Text(short).measured("in").frame(minHeight: h(2), maxHeight: h(5)).measured("frame")
        }
        down("clear ideal 3", offer: offer) { Color.clear.measured("in").frame(idealHeight: h(3)).measured("frame") }
    }
}
