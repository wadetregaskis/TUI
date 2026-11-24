import SwiftUI
import AppKit

// 2026-11-23, hunt items H-62 and H-64: four layout questions, with monospaced
// text so that one character's advance stands in for a terminal cell and one
// line of text for a row. Offscreen NSHostingView, after ../Grid narrower than
// its columns. Widths are printed in characters, heights in lines.
//
// 1. `ViewThatFits(in: .vertical)` with a long paragraph and a short text, in a
//    frame 30 characters wide and 5 lines tall: which one draws, and what each
//    candidate is asked (`asked`: the proposals it saw, width×height, nil for
//    unspecified). Then the same under `in: .horizontal` and both axes, and a
//    paragraph that fits.
// 2. A row of nothing but a `Spacer` between two texts in a column: its height,
//    the texts' places, and the column's width.
// 3. `ZStack { Text("x"); Spacer() }`: its size offered zero, nothing and a lot,
//    and in a row of 20 characters beside `Text("y")`.
// 4. A `Spacer(minLength:)` longer than its stack is thick, in `HStack`,
//    `HStackLayout`, `AnyLayout(HStackLayout())`, `VStack` and `VStackLayout`:
//    is the minimum counted across the stack's axis?
//
// Build and run (from this folder):
//   xcrun swiftc -target arm64-apple-macos15.0 fits.swift -o "$TMPDIR/fits"
//   "$TMPDIR/fits" | diff fits.out -

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
@MainActor func spin(_ s: Double = 0.25) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor final class Record {
    static var frames: [String: CGRect] = [:]
    static var asked: [String: [String]] = [:]
    static var sizes: [String: String] = [:]
}

func cells(_ v: CGFloat) -> String {
    if v.isInfinite { return "inf" }
    let c = v / advance
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}
@MainActor func lines(_ v: CGFloat) -> String {
    if v.isInfinite { return "inf" }
    let c = v / lineHeight
    return abs(c - c.rounded()) < 0.17 ? String(Int(c.rounded())) : String(format: "%.2f", c)
}
@MainActor func size(_ s: CGSize) -> String { "\(cells(s.width))x\(lines(s.height))" }

struct Measured: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { p in
            let f = p.frame(in: .named("root"))
            let _ = MainActor.assumeIsolated { Record.frames[name] = f }
            Color.clear
        })
    }
}

/// Passes its one child through, noting every proposal it is asked about.
struct Spy: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal)
        MainActor.assumeIsolated {
            let entry = "\(proposal.width.map(cells) ?? "nil")×\(proposal.height.map(lines) ?? "nil")"
            if Record.asked[name]?.contains(entry) != true { Record.asked[name, default: []].append(entry) }
        }
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

/// Records its one subview's size offered zero, nothing (its ideal) and 1000 cells by 1000 lines.
struct Sizes: Layout {
    let title: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        MainActor.assumeIsolated {
            if Record.sizes[title] == nil {
                let s = subviews[0]
                let big = ProposedViewSize(width: 1000 * advance, height: 1000 * lineHeight)
                Record.sizes[title] =
                    "zero \(size(s.sizeThatFits(.zero))) ideal \(size(s.sizeThatFits(.unspecified))) big \(size(s.sizeThatFits(big)))"
            }
        }
        return CGSize(width: 100, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: .unspecified) }
    }
}

extension View {
    func named(_ name: String) -> some View { modifier(Measured(name: name)) }
    func spied(_ name: String) -> some View { Spy(name: name) { self } }
}

/// Lays `content` out in a frame of `width` characters by `height` lines, top-leading, and prints the frames
/// recorded under `names` (x, y, width and height) and what the spied views were asked.
@MainActor func place<V: View>(
    _ title: String, width: Int, height: Int, names: [String], spies: [String] = [], @ViewBuilder _ content: () -> V
) {
    Record.frames = [:]
    Record.asked = [:]
    let root = content()
        .frame(width: CGFloat(width) * advance, height: CGFloat(height) * lineHeight, alignment: .topLeading)
        .coordinateSpace(name: "root")
        .font(font)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    host(root, size: CGSize(width: 120 * advance, height: 40 * lineHeight))
    spin()
    var out = "\(title) [\(width)x\(height)]"
    for name in names {
        if let f = Record.frames[name] {
            out += "\t\(name)=\(cells(f.width))x\(lines(f.height))@\(cells(f.minX)),\(lines(f.minY))"
        } else {
            out += "\t\(name)=not drawn"
        }
    }
    print(out)
    for name in spies {
        print("  asked\t\(name)\t\((Record.asked[name] ?? []).joined(separator: " "))")
    }
}

/// Prints `content`'s size offered zero, nothing and 1000 by 1000.
@MainActor func sizes<V: View>(_ title: String, @ViewBuilder _ content: () -> V) {
    Record.sizes = [:]
    host(Sizes(title: title) { content() }.font(font), size: CGSize(width: 400, height: 200))
    spin()
    print("\(title)\t\(Record.sizes[title] ?? "?")")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    Record.frames = [:]
    host(Text("x").font(font).named("line").fixedSize().coordinateSpace(name: "root"), size: CGSize(width: 200, height: 200))
    spin()
    lineHeight = Record.frames["line"]!.height

    let paragraph = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)  // 299 characters
    let ten = String(repeating: "word ", count: 10).trimmingCharacters(in: .whitespaces)  // 49 characters

    print("== 1. ViewThatFits")
    place("vertical, 60 words", width: 30, height: 5, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits(in: .vertical) {
            Text(paragraph).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }
    place("vertical, 10 words", width: 30, height: 5, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits(in: .vertical) {
            Text(ten).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }
    place("vertical, 60 words, wide", width: 100, height: 5, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits(in: .vertical) {
            Text(paragraph).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }
    place("horizontal, 60 words", width: 30, height: 5, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits(in: .horizontal) {
            Text(paragraph).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }
    place("horizontal, 10 words", width: 60, height: 1, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits(in: .horizontal) {
            Text(ten).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }
    place("both, 60 words", width: 30, height: 5, names: ["long", "short"], spies: ["long", "short"]) {
        ViewThatFits {
            Text(paragraph).named("long").spied("long")
            Text("short").named("short").spied("short")
        }
    }

    print("== 2. A row of only a spacer, in a column")
    place("VStack(spacing: 0) a|HStack{Spacer}|b", width: 30, height: 10, names: ["column", "a", "row", "b"]) {
        VStack(spacing: 0) {
            Text("a").named("a")
            HStack { Spacer() }.named("row")
            Text("b").named("b")
        }
        .named("column")
    }
    place("VStack a|HStack{Spacer}|b", width: 30, height: 10, names: ["column", "a", "row", "b"]) {
        VStack {
            Text("a").named("a")
            HStack { Spacer() }.named("row")
            Text("b").named("b")
        }
        .named("column")
    }
    place("VStack(spacing: 0) a|b", width: 30, height: 10, names: ["column", "a", "b"]) {
        VStack(spacing: 0) {
            Text("a").named("a")
            Text("b").named("b")
        }
        .named("column")
    }
    sizes("HStack{Spacer}") { HStack { Spacer() } }
    sizes("HStack{Spacer(minLength: 0)}") { HStack { Spacer(minLength: 0) } }
    sizes("HStackLayout{Spacer}") { HStackLayout { Spacer() } }

    print("== 3. A spacer in a ZStack")
    sizes("ZStack{x|Spacer}") { ZStack { Text("x"); Spacer() } }
    sizes("ZStack{x|Spacer(minLength: 6 cells)}") { ZStack { Text("x"); Spacer(minLength: 6 * advance) } }
    sizes("ZStack{x}") { ZStack { Text("x") } }
    sizes("ZStack{Spacer}") { ZStack { Spacer() } }
    sizes("ZStack{Spacer(minLength: 6 cells)}") { ZStack { Spacer(minLength: 6 * advance) } }
    sizes("ZStack{Spacer|Spacer(minLength: 6 cells)}") { ZStack { Spacer(); Spacer(minLength: 6 * advance) } }
    sizes("ZStack{Color.clear 0x0|Spacer}") { ZStack { Color.clear.frame(width: 0, height: 0); Spacer() } }
    sizes("ZStack{Color.red|Spacer(minLength: 6 cells)}") { ZStack { Color.red.frame(width: 2 * advance, height: lineHeight); Spacer(minLength: 6 * advance) } }
    place("HStack{ZStack{x|Spacer}|y}", width: 20, height: 3, names: ["row", "zstack", "x", "y"]) {
        HStack {
            ZStack { Text("x").named("x"); Spacer() }.named("zstack")
            Text("y").named("y")
        }
        .named("row")
    }
    place("VStack{ZStack{x|Spacer}|y}", width: 20, height: 6, names: ["column", "zstack", "x", "y"]) {
        VStack {
            ZStack { Text("x").named("x"); Spacer() }.named("zstack")
            Text("y").named("y")
        }
        .named("column")
    }

    print("== 4. Spacer(minLength:) across its stack's axis")
    let tall = 3 * lineHeight
    let wide = 10 * advance
    sizes("HStack{a|Spacer(minLength: 3 lines)|b}") { HStack { Text("a"); Spacer(minLength: tall); Text("b") } }
    sizes("HStackLayout{a|Spacer(minLength: 3 lines)|b}") {
        HStackLayout { Text("a"); Spacer(minLength: tall); Text("b") }
    }
    sizes("AnyLayout(HStackLayout){a|Spacer(minLength: 3 lines)|b}") {
        AnyLayout(HStackLayout()) { Text("a"); Spacer(minLength: tall); Text("b") }
    }
    sizes("VStack{ab|Spacer(minLength: 10 cells)}") { VStack { Text("ab"); Spacer(minLength: wide) } }
    sizes("VStackLayout{ab|Spacer(minLength: 10 cells)}") { VStackLayout { Text("ab"); Spacer(minLength: wide) } }
    sizes("Spacer(minLength: 3 lines) alone") { Spacer(minLength: tall) }
    place("HStack{VStack{ab|Spacer(min 10 cells)}|Spacer|R}", width: 40, height: 3, names: ["column", "R"]) {
        HStack {
            VStack { Text("ab"); Spacer(minLength: wide) }.named("column")
            Spacer()
            Text("R").named("R")
        }
    }
    print("== done")
}
