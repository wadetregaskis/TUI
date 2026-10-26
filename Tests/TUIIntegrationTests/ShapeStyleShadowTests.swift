//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeStyleShadowTests.swift
//
//  `ShapeStyle.shadow(_:)`: a style's shadows, cast by whatever draws with the
//  style from the cells it drew — a shape, a background, the letters of a text
//  under a foreground style — as SwiftUI casts them (measured on macOS 15.8).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Shadowed shape styles")
struct ShapeStyleShadowTests {
    nonisolated private static let page = ShadowScreen.page

    /// Black at a half: the shadow every test casts, so its cells read as
    /// ``half``.
    private static let ink = Color.black.opacity(0.5)

    /// The page under a half-black shadow.
    private var half: Int { ShadowScreen.darkened(128.0 / 255) }

    private static let blue = Color.rgb(0, 0, 255)

    private func screen(_ view: some View, width: Int = 12, height: Int = 8) -> ShadowScreen {
        ShadowScreen(view, width: width, height: height)
    }

    // MARK: - What casts

    @Test("A shape filled with a shadowed style casts the shadow from its fill")
    func shapeFillCasts() {
        let style = Self.blue.shadow(.drop(color: Self.ink, radius: 0, x: 1, y: 1))
        // A rectangle fills as a background over a blank block; a rounded
        // rectangle through the shapes' own cells. Both cast alike.
        for shape in [AnyShape(Rectangle()), AnyShape(RoundedRectangle(cornerRadius: 0))] {
            let screen = screen(shape.fill(style).frame(width: 2, height: 1).padding(2))
            #expect(screen.fields(row: 2, 1..<6) == [Self.page, 255, 255, Self.page, Self.page])
            #expect(screen.fields(row: 3, 1..<6) == [Self.page, Self.page, half, half, Self.page])
        }
    }

    @Test("A stroke in a shadowed style casts the shadow from its lines")
    func strokeCasts() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, y: 1))
        let screen = screen(Rectangle().stroke(style).frame(width: 3, height: 3).padding(2))
        // The box's bottom line, at row 4, casts onto row 5; its hollow middle,
        // row 3's middle cell, is under the top line's shadow.
        #expect(screen.glyph(2, 4) == "└")
        #expect(screen.fields(row: 5, 2..<5) == [half, half, half])
        #expect(screen.field(3, 3) == half)
    }

    @Test("A background in a shadowed style casts a drop shadow beneath its fill")
    func backgroundDropShadow() {
        let screen = screen(
            Text("ab").background(Self.blue.shadow(.drop(color: Self.ink, radius: 0, x: 1, y: 1))).padding(2))
        #expect(screen.fields(row: 3, 1..<6) == [Self.page, Self.page, half, half, Self.page])
        #expect(screen.glyph(2, 2) == "a")
    }

    @Test("A background's inner shadow is over its fill and under the content in front of it")
    func backgroundInnerShadowUnderContent() {
        let white = Color.rgb(255, 255, 255)
        let style = Self.blue.shadow(.inner(color: Self.ink, radius: 0, x: 1, y: 1))
        let screen = screen(Text("ab\ncd").foregroundStyle(white).background(style).padding(1))
        let veiled = ShadowScreen.darkened(128.0 / 255, from: 255)
        // The edges the offset points away from — the top and the leading — are
        // veiled, the rest is the fill.
        #expect(screen.fields(row: 1, 1..<3) == [veiled, veiled])
        #expect(screen.fields(row: 2, 1..<3) == [veiled, 255])
        // The letters in front of the fill keep their ink, as SwiftUI draws them.
        #expect(screen.glyph(1, 1) == "a")
        #expect(screen.ink(1, 1) == 255)
    }

    @Test("A text under a shadowed foreground style casts the shape of its letters")
    func foregroundStyleCastsFromLetters() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, x: 1))
        let screen = screen(Text("a b").foregroundStyle(style).padding(2))
        #expect(screen.fields(row: 2, 2..<6) == [Self.page, half, Self.page, half])
    }

    @Test("A text with a colour of its own casts no shadow from the foreground style above it")
    func statedColourCastsNothing() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, x: 1))
        let screen = screen(VStack { Text("a b").foregroundStyle(Color.red) }.foregroundStyle(style).padding(2))
        #expect(screen.fields(row: 2, 2..<6).allSatisfy { $0 == Self.page })
    }

    @Test("A divider in a shadowed foreground style casts from its rule")
    func dividerCasts() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, y: 1))
        let screen = screen(VStack { Divider() }.frame(width: 3).foregroundStyle(style).padding(2))
        #expect(screen.fields(row: 3, 2..<5) == [half, half, half])
    }

    private struct Row: Identifiable {
        let id: Int
        var name: String { "x\(id)" }
    }

    @Test("A table casts its rows' shadows once a glyph, its view cells' among them")
    func tableCastsOnceAGlyph() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, x: 1))
        let table = Table([Row(id: 1)], selection: .constant(Int?.none)) {
            TableColumn("A", value: \Row.name)
            TableColumn("B") { (row: Row) in HStack { Text("y\(row.id)") } }
        }
        let screen = screen(table.foregroundStyle(style), width: 20, height: 8)
        let rows = screen.buffer.lines.map(\.stripped)
        guard let row = rows.firstIndex(where: { $0.contains("x1") }),
            let text = rows[row].firstIndex(of: "x"), let view = rows[row].firstIndex(of: "y")
        else {
            Issue.record("no row drawn: \(rows)")
            return
        }
        // Past each cell's two letters, the shadow of the second at half: a view
        // cell's letters cast once, from the rows, not again from their own
        // text.
        let textColumn = rows[row].distance(from: rows[row].startIndex, to: text)
        let viewColumn = rows[row].distance(from: rows[row].startIndex, to: view)
        #expect(screen.field(textColumn + 2, row) == half)
        #expect(screen.field(viewColumn + 2, row) == half)
    }

    @Test("A control drawing its label in a colour of its own keeps the style's shadow on it")
    func recolouredLabelKeepsTheShadow() {
        let style = Color.rgb(255, 255, 255).shadow(.drop(color: Self.ink, radius: 0, x: 1))
        let screen = screen(
            Toggle("a b", isOn: .constant(false)).disabled(true).foregroundStyle(style), width: 20, height: 4)
        let rows = screen.buffer.lines.map(\.stripped)
        guard let row = rows.firstIndex(where: { $0.contains("a b") }), let label = rows[row].range(of: "a b")
        else {
            Issue.record("no label drawn: \(rows)")
            return
        }
        // The disabled label is drawn in a dimmed colour of the toggle's own,
        // and still casts: the "a" onto the space after it. (The toggle spends
        // its label's translucency against a page it does not know, so the
        // half snaps to the heavier side: it is the shadow's being there that
        // is asked here.)
        let column = rows[row].distance(from: rows[row].startIndex, to: label.lowerBound)
        #expect(screen.field(column + 1, row) != nil)
        #expect(screen.field(column, row) == nil)
    }

    // MARK: - Several shadows, and strength

    @Test("Each of several shadows is cast from the style's drawing, not from the others")
    func severalShadowsEachFromTheBase() {
        let style = Self.blue
            .shadow(.drop(color: Self.ink, radius: 0, x: 1))
            .shadow(.drop(color: Self.ink, radius: 0, y: 1))
        let screen = screen(Rectangle().fill(style).frame(width: 1, height: 1).padding(2))
        #expect(screen.field(3, 2) == half)
        #expect(screen.field(2, 3) == half)
        #expect(screen.field(3, 3) == nil, "the second shadow casts nothing of the first")
    }

    @Test("A style at half strength casts at half, whichever side of the shadow the fade is written")
    func fadedStyleCastsAtItsStrength() {
        let drop = ShadowStyle.drop(color: .black, radius: 0, x: 1, y: 1)
        let before = screen(Rectangle().fill(Self.blue.opacity(0.5).shadow(drop)).frame(width: 1, height: 1).padding(2))
        let after = screen(Rectangle().fill(Self.blue.shadow(drop).opacity(0.5)).frame(width: 1, height: 1).padding(2))
        #expect(before.field(3, 3) == half)
        #expect(after.field(3, 3) == half)
    }

    @Test("A secondary level of a shadowed foreground style keeps the shadow, at its own strength")
    func hierarchicalLevelKeepsTheShadow() {
        let style = Self.blue.shadow(.drop(color: .black, radius: 0, x: 1, y: 1))
        let screen = screen(Rectangle().fill(.secondary).frame(width: 1, height: 1).foregroundStyle(style).padding(2))
        #expect(screen.field(3, 3) == half)
    }

    // MARK: - The current style

    @Test("The static shadow's style is the foreground where a shape is filled")
    func implicitStyleIsTheForeground() {
        let screen = screen(
            Rectangle().fill(.shadow(.drop(color: Self.ink, radius: 0, x: 1, y: 1))).frame(width: 1, height: 1)
                .foregroundStyle(Self.blue).padding(2))
        #expect(screen.cell(2, 2)?.state.backgroundColour == .rgb(0, 0, 255))
        #expect(screen.field(3, 3) == half)
    }

    @Test("The static shadow's style is the background style where a background style is set")
    func implicitStyleIsTheBackgroundStyle() {
        let green = Color.rgb(0, 255, 0)
        let screen = screen(
            Text("ab\ncd").background()
                .backgroundStyle(.shadow(.inner(color: Self.ink, radius: 0, x: 1, y: 1)))
                .backgroundStyle(green).foregroundStyle(Self.blue).padding(1))
        #expect(screen.cell(2, 2)?.state.backgroundColour == .rgb(0, 255, 0), "the fill is the style above")
        #expect(screen.field(1, 1) == ShadowScreen.darkened(128.0 / 255, from: 255))
    }

    // MARK: - What it leaves alone

    @Test("A shadowed style changes no size and moves nothing")
    func layoutUnchanged() {
        func text(_ shadowed: Bool) -> [String] {
            let style = Self.blue.shadow(.drop(radius: 2, x: 3, y: 1))
            let view = VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("<")
                    if shadowed { Text("ab").background(style) } else { Text("ab").background(Self.blue) }
                    Text(">")
                }
                Text("below")
            }
            // The text alone: the root composite draws the shadow past the
            // view's frame, which grows the screen's lines to reach it.
            let lines = screen(view).buffer.lines.map { line in
                var text = line.stripped
                while text.last == " " { text.removeLast() }
                return text
            }
            return Array(lines.reversed().drop { $0.isEmpty }.reversed())
        }
        #expect(text(true) == text(false))
    }

    @Test("A paint's shadows come off as they went on, and a derived colour reads through them")
    func paintSplitsItsShadows() {
        let first = ShadowStyle.drop(radius: 1)
        let second = ShadowStyle.inner(radius: 2)
        let paint = Paint.shadowed(.shadowed(.color(.red), first), second)
        #expect(paint.unshadowed == .color(.red))
        #expect(paint.shadows == [first, second])
        #expect(paint.solid == .red)
        #expect(paint.representative == .red)
        #expect(Paint.shadowed(.color(.red), first).keepingShadows(on: .color(.blue)) == .shadowed(.color(.blue), first))
        #expect(Paint.color(.red).shadows.isEmpty)
    }

    @Test("A view holding a shadowed style keeps a value hash, so the render memo can keep it")
    func memoReadsTheShadowedStyle() {
        let plans = ValueHashPlans()
        let type = type(of: Rectangle().fill(Color.red.shadow(.drop(radius: 1, x: 1, y: 1))))
        let plan = plans.plan(for: type).pointee
        #expect(plan.shape != .bypass, "\(plan.bypassReason ?? "")")
    }
}
