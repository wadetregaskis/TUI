//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlacementOverflowTests.swift
//
//  A view a placement puts past its region draws there, as SwiftUI's does
//  (decisions B-GUIDE-3): over the views before it and under the views after
//  it, clicked where it is drawn, and cut by the views that clip.
//
//  SwiftUI measured with SwiftUI 6.5.4 on macOS 15.8.1, `ImageRenderer` and an
//  offscreen `NSHostingView`, 2026-10-11/12 (`Tools/SwiftUIProbes/Alignment
//  guides/`; the stacking-order rows in decisions B-GUIDE-3). One point stands
//  for one cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Drawing past a placement's region")
struct PlacementOverflowTests {

    /// A value a tap closure can set.
    private final class Flag {
        var value = false
    }

    /// A screen: each frame rendered, then composited as the screen root
    /// composites it, with a dispatcher that clicks what it drew.
    @MainActor
    private final class Screen {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let width: Int
        let height: Int
        var last = FrameBuffer()

        init(width: Int = 20, height: Int = 6) {
            self.width = width
            self.height = height
        }

        @discardableResult
        func render<V: View>(_ view: V) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.horizontalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            last = buffer.compositingOverlays(maxWidth: width, maxHeight: height, palette: environment.palette)
            return lines
        }

        /// Each line as drawn, its trailing blanks dropped.
        var lines: [String] {
            last.lines.map { line in
                var text = line.stripped
                while text.last == " " { text.removeLast() }
                return text
            }
        }

        func click(x: Int, y: Int) {
            let dispatcher = tui.mouseEventDispatcher
            dispatcher.setActiveSupport(.standard)
            dispatcher.setRegions(last.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
    }

    // MARK: - Where it draws

    @Test("A badge hung off a corner by its guides sits beside its label, not on it")
    func badgeOnACorner() {
        // SwiftUI puts the badge's top guide (1) on the overlay's top (0) and
        // its trailing guide (0) on the overlay's trailing edge (5): one row
        // above the label and one column right of it (guide2.out, guide5.out).
        // Held inside the label, it drew "Inbo3".
        let screen = Screen()
        let lines = screen.render(
            Text("Inbox")
                .overlay(alignment: .topTrailing) {
                    Text("3").alignmentGuide(.top) { _ in 1 }.alignmentGuide(.trailing) { _ in 0 }
                }
                .padding(1))
        #expect(Array(lines.prefix(2)) == ["      3", " Inbox"], "\(lines)")
    }

    @Test("A frame its content's size keeps the content as it is unless the content's guide places it")
    func sameSizeFrameKeepsItsContent() {
        // `.frame(maxWidth: .fixed(40))` around two ragged lines is their size. A
        // guide on `.leading` does not apply to the frame's `.center`, and a
        // `Subview` may carry a guide but here carries none, so neither is
        // placed: re-placed, each short line was centred on its own (" bb").
        func render(_ view: some View) -> [String] {
            renderToBuffer(view, context: makeBareRenderContext(width: 20, height: 4)).lines.map {
                var text = $0.stripped
                while text.last == " " { text.removeLast() }
                return text
            }
        }
        let text = Text("aaaa\nbb")
        #expect(render(text.alignmentGuide(.leading) { _ in 0 }.frame(maxWidth: .fixed(40))) == ["aaaa", "bb"])
        #expect(render(ForEach(subviews: text) { $0.frame(maxWidth: .fixed(40)) }) == ["aaaa", "bb"])
        #expect(render(text.alignmentGuide(.leading) { _ in 0 }.frame(maxHeight: .fixed(9))) == ["aaaa", "bb"])
        // A guide that applies still places it, in a frame its own size too:
        // SwiftUI's 4-wide view whose leading guide is 3 sits 3 cells left.
        let screen = Screen()
        let lines = screen.render(
            HStack(spacing: 0) {
                Text("bbbb")
                Text("rrrr").alignmentGuide(.leading) { _ in 3 }.frame(maxWidth: .fixed(40), alignment: .leading)
            })
        #expect(lines.first == "brrrr", "\(lines)")
    }

    @Test("A view drawn past its frame is over the view before it")
    func overTheViewBefore() {
        // `HStack { blue; red in a frame it overflows to the left }`: SwiftUI
        // draws the red over the blue (g2c: (57, 20) is red).
        let screen = Screen()
        let lines = screen.render(
            HStack(spacing: 0) {
                Text("bbbb")
                Text("rrrr").alignmentGuide(.leading) { _ in 3 }.frame(width: 4, alignment: .leading)
            })
        #expect(lines.first == "brrrr", "\(lines)")
    }

    @Test("A view drawn past its frame is under the view after it")
    func underTheViewAfter() {
        // `HStack { red in a frame it overflows to the right; blue }`: SwiftUI
        // draws the blue over the red (g2c: (52, 20) is blue).
        let screen = Screen()
        let lines = screen.render(
            HStack(spacing: 0) {
                Text("rrrr").alignmentGuide(.leading) { _ in -3 }.frame(width: 4, alignment: .leading)
                Text("bbbb")
            })
        #expect(lines.first == "   rbbbb", "\(lines)")
    }

    @Test("Down a column: over the row above, under the row below")
    func downAColumn() {
        // `VStack { above; scaled red; below }` in g2c: the red covers the row
        // above it and the row below covers the red.
        func column(guide: Double) -> [String] {
            let screen = Screen()
            let lines = screen.render(
                VStack(alignment: .leading, spacing: 0) {
                    Text("aaaa")
                    Text("x").alignmentGuide(.top) { _ in guide }.frame(width: 4, height: 1, alignment: .topLeading)
                    Text("bbbb")
                })
            return Array(lines.prefix(3))
        }
        // A top guide of 1 puts the view a row above its frame, over "aaaa";
        // one of -1 a row below it, under "bbbb".
        #expect(column(guide: 1) == ["xaaa", "", "bbbb"])
        #expect(column(guide: -1) == ["aaaa", "", "bbbb"])
        #expect(column(guide: 0) == ["aaaa", "x", "bbbb"])
    }

    @Test("What a view floats is drawn over the part of it past its region, as over the part inside")
    func ownFloatingLayersOverItsOverflow() {
        // Each placed view carries an `.offset` mark over its second cell,
        // which the placement draws past the region. The mark is the view's
        // own, drawn over the view's cells wherever they land, as SwiftUI
        // draws a view's offset content over the view; drawn under its
        // overflow, the mark vanished.
        func marked(_ text: String) -> some View {
            Text(text).overlay(alignment: .leading) { Text("Z").offset(x: 1) }
        }
        let screen = Screen(width: 30, height: 4)
        // A frame: rrrr is three cells left of its frame, over bbbb.
        var lines = screen.render(
            HStack(spacing: 0) {
                Text("bbbb")
                marked("rrrr").alignmentGuide(.leading) { _ in 3 }.frame(width: 4, alignment: .leading)
            })
        #expect(lines.first == "brZrr", "\(lines)")
        // An overlay: the badge a row above the label and a column right.
        lines = screen.render(
            Text("Inbox")
                .overlay(alignment: .topTrailing) {
                    marked("3x").alignmentGuide(.top) { _ in 1 }.alignmentGuide(.trailing) { _ in 0 }
                }
                .padding(1))
        #expect(lines.first == "      3Z", "\(lines)")
        // A column's overhang (decisions B-GUIDE-1): GGG past the column.
        lines = screen.render(
            VStack(alignment: .trailing, spacing: 0) {
                marked("GGG").alignmentGuide(.trailing) { _ in 0 }
                Text("SSSSSS")
                Text("f").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 20)
            .padding(.trailing, 10))
        #expect(lines.first == String(repeating: " ", count: 20) + "GZG", "\(lines)")
    }

    @Test("Only the cells it paints are drawn past the region; its blanks erase nothing")
    func blanksEraseNothing() {
        let screen = Screen()
        let lines = screen.render(
            HStack(spacing: 0) {
                Text("bbbbbbbb")
                Text("  r ").alignmentGuide(.leading) { _ in 6 }.frame(width: 4, alignment: .leading)
            })
        // "  r " at 8 - 6 = 2: its two leading blanks fall on "bb" at 2...3,
        // and leave them; the "r" lands on 4.
        #expect(lines.first == "bbbbrbbb", "\(lines)")
    }

    // MARK: - Where it is clicked

    @Test("A view drawn past its frame is clicked where it is drawn")
    func clickedWhereDrawn() {
        let screen = Screen()
        let tapped = Flag()
        screen.render(
            VStack(alignment: .leading, spacing: 0) {
                Text("tap")
                    .onTapGesture { tapped.value = true }
                    .alignmentGuide(.leading) { _ in -6 }
                    .frame(width: 4, alignment: .leading)
            })
        #expect(screen.lines.first == "      tap", "\(screen.lines)")
        screen.click(x: 7, y: 0)
        #expect(tapped.value, "a click on the drawn cells reached it: \(screen.last.hitTestRegions)")
    }

    @Test("A later view keeps the clicks on the cells it draws over the overflow")
    func laterViewKeepsItsClicks() {
        let screen = Screen()
        let under = Flag()
        let over = Flag()
        screen.render(
            HStack(spacing: 0) {
                Text("rrrr")
                    .onTapGesture { under.value = true }
                    .alignmentGuide(.leading) { _ in -3 }
                    .frame(width: 4, alignment: .leading)
                Text("bbbb").onTapGesture { over.value = true }
            })
        screen.click(x: 5, y: 0)
        #expect(over.value && !under.value, "the cell is drawn by the later view, and clicked there")
    }

    // MARK: - What still clips

    @Test("A scroll view, and .clipped(), still cut what a placement puts past them")
    func clippingViewsStillClip() {
        let guided = Text("rrrr").alignmentGuide(.leading) { _ in -3 }.frame(width: 4, alignment: .leading)
        let screen = Screen()
        let scrolled = screen.render(
            HStack(spacing: 0) {
                ScrollView(.horizontal) { guided }.frame(width: 5, height: 1)
                Text("|")
            })
        #expect(scrolled.first == "   rr|", "cut at the viewport's edge: \(scrolled)")

        let clipped = screen.render(HStack(spacing: 0) { guided.clipped(); Text("|") })
        #expect(clipped.first == "   r|", "cut at the frame: \(clipped)")
    }

    private struct Item: Identifiable {
        let id: Int
    }

    /// Every drawn line of a bordered box keeps its content between its side
    /// borders: nothing drawn over or past them.
    private func staysInsideItsBorders(_ lines: [String]) -> Bool {
        lines.allSatisfy { line in
            guard let first = line.first, "│┃|".contains(first) else { return true }
            return line.last.map { "│┃|".contains($0) } ?? false
        }
    }

    @Test("A list keeps a row's overflow inside its border")
    func listKeepsItInside() {
        // The row's view hangs six columns right of its frame: over the list's
        // right border and past it, were it drawn there.
        let screen = Screen(width: 24, height: 6)
        let lines = screen.render(
            HStack(spacing: 0) {
                List {
                    ForEach([Item(id: 0)]) { _ in
                        Text("rrrr").alignmentGuide(.leading) { _ in -6 }.frame(width: 4, alignment: .leading)
                    }
                }
                .listStyle(.bordered)
                .frame(width: 12)
                Spacer()
            })
        #expect(lines.contains { $0.contains("r") }, "the part inside the list is drawn: \(lines)")
        #expect(staysInsideItsBorders(lines), "\(lines)")
        #expect(!lines.contains { $0.dropFirst(12).contains("r") }, "nothing past the list: \(lines)")
    }

    @Test("A table keeps a cell's overflow inside its box")
    func tableKeepsItInside() {
        // Each row's view is four cells in a 4-wide frame, hung `push` cells
        // right of it by its guide. Two cells is past the frame and inside
        // the cell, where it is drawn; twelve is past the cell and the table,
        // where it is cut. Held inside its frame, as before B-GUIDE-3, every
        // row drew "rrrr" at the frame's edge.
        func table(_ pushes: [Double]) -> [String] {
            let screen = Screen(width: 24, height: 6)
            return screen.render(
                HStack(spacing: 0) {
                    Table(pushes.indices.map { Item(id: $0) }) {
                        TableColumn("A") { item in
                            Text("rrrr").alignmentGuide(.leading) { _ in -pushes[item.id] }
                                .frame(width: 4, alignment: .leading)
                        }
                    }
                    .frame(width: 12)
                    Text("|")
                })
        }
        let reference = table([0])
        guard let row = reference.firstIndex(where: { $0.contains("rrrr") }),
            let frameEdge = reference[row].range(of: "rrrr")?.lowerBound
        else {
            Issue.record("the unpushed row draws its view: \(reference)")
            return
        }
        let column = reference[row].distance(from: reference[row].startIndex, to: frameEdge)
        let lines = table([2, 12])
        let pushed = lines[row].range(of: "rrrr").map { lines[row].distance(from: lines[row].startIndex, to: $0.lowerBound) }
        #expect(pushed == column + 2, "two cells right of the frame, inside the cell: \(lines)")
        #expect(lines.filter { $0.contains("r") } == [lines[row]], "the second row's view is past the cell, cut: \(lines)")
        #expect(!lines.contains { $0.dropFirst(12).contains("r") }, "nothing past the table: \(lines)")
    }

    @Test("A surface keeps its content's overflow inside its box")
    func surfaceKeepsItInside() {
        // A popover-like surface 6 wide at column 2 whose content carries a
        // view drawn past its region: four cells, from column 5 of the surface.
        var content = FrameBuffer(lines: ["······"])
        var past = OverlayLayer(
            offsetX: 5, offsetY: 0, content: FrameBuffer(lines: ["XXXX"]), zIndex: OverlayLayer.displacedDrawingZIndex,
            clampsToScreen: false, isOpaque: false)
        past.isOverflow = true
        content.overlays = [past]
        var page = FrameBuffer(lines: [String(repeating: "-", count: 16)])
        page.overlays = [OverlayLayer(offsetX: 2, offsetY: 0, content: content, clampsToScreen: false)]
        let drawn = page.compositingOverlays(maxWidth: 16, maxHeight: 1, palette: EnvironmentValues().palette)
        #expect(drawn.lines.first?.stripped == "--·····X--------", "\(drawn.lines.map(\.stripped))")
    }

    // MARK: - A run of guides wider than its region (B-GUIDE-1)

    @Test("A column that cannot grow keeps every guide on one line and draws the overhang past its edge")
    func columnOverhang() {
        // SwiftUI (GUIDE probe, 400-wide host): the 3-wide view whose trailing
        // guide is 0 sits at 400, past the window's edge, the 6-wide one at
        // 394, every guide on one line. Here the column is 20 wide (its frame)
        // with ten blank columns after it, where the overhang shows; held
        // inside, it sat 3 cells left of its guide, at 17.
        let screen = Screen(width: 30, height: 4)
        let lines = screen.render(
            VStack(alignment: .trailing, spacing: 0) {
                Text("GGG").alignmentGuide(.trailing) { _ in 0 }
                Text("SSSSSS")
                Text("f").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 20)
            .padding(.trailing, 10))
        #expect(
            Array(lines.prefix(3)) == [String(repeating: " ", count: 20) + "GGG", String(repeating: " ", count: 14) + "SSSSSS", "f"],
            "\(lines)")
    }

    @Test("A row whose guides need more height than it has draws the overhang below it")
    func rowOverhang() {
        let screen = Screen(width: 10, height: 6)
        let lines = screen.render(
            HStack(alignment: .top, spacing: 0) {
                Text("g").alignmentGuide(.top) { _ in -3 }
                Text("s")
            }
            .frame(height: 2)
            .padding(.bottom, 4))
        // The run is four rows (g three below s); the row is two, so g is
        // drawn a row below it, in the padding, rather than cut away.
        #expect(Array(lines.prefix(4)) == [" s", "", "", "g"], "\(lines)")
    }

    @Test("A ZStack whose guides need more room than it was given draws the overhang past it")
    func zStackOverhang() {
        let screen = Screen(width: 40, height: 2)
        let lines = screen.render(
            ZStack(alignment: .topLeading) {
                Text("a")
                Text("b").alignmentGuide(.leading) { _ in -25 }
            }
            .frame(width: 20)
            .padding(.trailing, 20))
        #expect(lines.first == "a" + String(repeating: " ", count: 24) + "b", "\(lines)")
    }

    @Test("A lazy column's window keeps every guide on one line; the scroll view cuts the overhang")
    func lazyColumnOverhang() {
        // The run is 23 wide in a 20-wide window (the filler fixes it): GGG's
        // guide puts it at 20, past the window, where the scroll view cuts it.
        // Held inside, it sat at 17, three cells left of its guide.
        let screen = Screen(width: 30, height: 4)
        let lines = screen.render(
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 0) {
                    Text("GGG").alignmentGuide(.trailing) { _ in 0 }
                    Text("SSSSSS")
                    Text("f").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 20, height: 3))
        #expect(!lines.contains { $0.contains("G") }, "\(lines)")
        #expect(lines.contains(String(repeating: " ", count: 14) + "SSSSSS"), "\(lines)")
    }

    @Test("A lazy column outside a scroll view pads its rows to its space, not its run, and draws the overhang past it")
    func lazyColumnPadsToItsSpace() {
        // As the eager column in `columnOverhang`: GGG's guide puts it at 20,
        // past the 20-wide column, where it is drawn. Padded to the run, each
        // row was a line as long as the push, cut by the frame around it.
        let screen = Screen(width: 30, height: 4)
        let lines = screen.render(
            LazyVStack(alignment: .trailing, spacing: 0) {
                Text("GGG").alignmentGuide(.trailing) { _ in 0 }
                Text("SSSSSS")
                Text("f").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 20)
            .padding(.trailing, 10))
        #expect(lines.first == String(repeating: " ", count: 20) + "GGG", "\(lines)")

        let pushed = LazyVStack(alignment: .leading, spacing: 0) {
            Text("g").alignmentGuide(.leading) { _ in -100_000 }
            Text("ssssss")
        }
        let buffer = renderToBuffer(pushed, context: makeBareRenderContext(width: 20, height: 4))
        #expect(buffer.width <= 20, "\(buffer.width)")
    }

    @Test("A lazy row pads its columns to its space, not its run, and draws the overhang below it")
    func lazyRowPadsToItsSpace() {
        let screen = Screen(width: 10, height: 6)
        let lines = screen.render(
            LazyHStack(alignment: .top, spacing: 0) {
                Text("g").alignmentGuide(.top) { _ in -3 }
                Text("s")
            }
            .frame(height: 2)
            .padding(.bottom, 4))
        #expect(Array(lines.prefix(4)) == [" s", "", "", "g"], "\(lines)")

        let pushed = LazyHStack(alignment: .top, spacing: 0) {
            Text("g").alignmentGuide(.top) { _ in -100_000 }
            Text("s")
        }
        let buffer = renderToBuffer(pushed, context: makeBareRenderContext(width: 10, height: 4))
        #expect(buffer.height <= 4, "\(buffer.height)")
    }

    @Test("A ZStack measured in less space than its run builds a canvas that space, not the run")
    func zStackMeasureCanvas() {
        let canvas = ZStack(alignment: .topLeading) {
            Text("a")
            Text("b").alignmentGuide(.leading) { _ in -100_000 }
        }
        var context = makeBareRenderContext(width: 20, height: 2)
        context.isMeasuring = true
        let buffer = renderToBuffer(canvas, context: context)
        #expect(buffer.width == 20, "\(buffer.width)")
        #expect(buffer.overlays.isEmpty, "a measure pass draws nothing past the space")
    }

    // MARK: - Measuring

    @Test("A measure pass draws nothing past the region and sizes as before")
    func measureUnchanged() {
        let view = Text("rrrr").alignmentGuide(.leading) { _ in -3 }.frame(width: 4, alignment: .leading)
        // Drawn, it hangs three cells right of its frame, into the padding.
        let screen = Screen()
        #expect(screen.render(view.padding(.trailing, 10)).first == "   rrrr", "\(screen.lines)")
        // Measured, it is its frame's size, and a measuring render keeps it
        // inside the frame, at the nearest place, with nothing past it.
        let size = measureChild(view, proposal: .unspecified, context: makeBareRenderContext(width: 20, height: 4))
        #expect(size.width == 4)
        #expect(size.height == 1)
        var context = makeBareRenderContext(width: 20, height: 4)
        context.isMeasuring = true
        let measured = renderToBuffer(view, context: context)
        #expect(measured.lines.map(\.stripped) == ["rrrr"])
        #expect(measured.overlays.isEmpty)
    }
}
