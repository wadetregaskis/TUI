//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollClipDisabledTests.swift
//
//  `scrollClipDisabled(_:)` (decisions A10): the content past a scroll view's
//  viewport draws around it, at the scroll view's own place in the stacking
//  order — over the views before it, under the views after it, as SwiftUI's
//  does (measured on macOS 15) — and can be clicked where it is drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitView

@MainActor
@Suite("scrollClipDisabled")
struct ScrollClipDisabledTests {

    @MainActor
    private final class Frames {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let width: Int
        let height: Int
        var last = FrameBuffer()

        init(width: Int = 20, height: Int = 12) {
            self.width = width
            self.height = height
        }

        /// The frame, its layers composited as the screen root composites them.
        @discardableResult
        func render<V: View>(_ view: V) -> FrameBuffer {
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
            return last
        }

        var lines: [String] { last.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } }

        var scrollView: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    private func page(clipDisabled: Bool, lazy: Bool = false, rows: Int = 20) -> some View {
        let content = ForEach(0..<rows, id: \.self) { Text("row \($0)") }
        let stack: AnyView =
            lazy
            ? AnyView(LazyVStack(alignment: .leading, spacing: 0) { content })
            : AnyView(VStack(alignment: .leading, spacing: 0) { content })
        return VStack(alignment: .leading, spacing: 0) {
            Text("above")
            ScrollView { stack }
                .frame(height: 4)
                .scrollClipDisabled(clipDisabled)
            Text("below")
        }
    }

    @Test("Clipped, the default: nothing is drawn past the viewport")
    func clippedByDefault() {
        let frames = Frames()
        frames.render(page(clipDisabled: false))
        #expect(frames.lines == ["above", "row 0", "row 1", "row 2", "row 3", "below"], "\(frames.lines)")
    }

    @Test("Unclipped: the content runs on below, under the view after the scroll view")
    func runsOnBelow() {
        let frames = Frames()
        frames.render(page(clipDisabled: true))
        // Row 4 runs into "below"'s line, which is drawn after the scroll view
        // and over it; rows 5… run on past it.
        #expect(Array(frames.lines.prefix(9)) == [
            "above", "row 0", "row 1", "row 2", "row 3", "below", "row 5", "row 6", "row 7",
        ], "\(frames.lines)")
    }

    @Test("Unclipped and scrolled: the content above draws over the view before the scroll view")
    func runsOnAbove() {
        let frames = Frames()
        let view = page(clipDisabled: true)
        frames.render(view)
        frames.scrollView?.scrollToOffset(3)
        frames.render(view)
        // Rows 0…2 are above the viewport: row 2 lands on "above"'s line, drawn
        // before the scroll view, and covers it.
        #expect(Array(frames.lines.prefix(6)) == ["row 2", "row 3", "row 4", "row 5", "row 6", "below"],
            "\(frames.lines)")
    }

    /// A uniform lazy stack's band is the rows the viewport shows, so it draws
    /// nothing past them — as SwiftUI's lazy stack drew nothing past its
    /// viewport in the same probe.
    @Test("A lazy stack draws its band, not every row")
    func lazyDrawsItsBand() {
        let frames = Frames()
        frames.render(page(clipDisabled: true, lazy: true, rows: 300))
        let drawn = frames.lines.compactMap { line -> Int? in
            guard let marker = line.range(of: "row ") else { return nil }
            return Int(line[marker.upperBound...].prefix { $0.isNumber })
        }
        #expect(drawn.first == 0)
        #expect((drawn.max() ?? 0) < 10, "only the band around the viewport: \(drawn)")
    }

    @Test("A control drawn past the viewport is clicked where it is drawn")
    func overflowIsClickable() {
        let frames = Frames()
        let pressed = Box(false)
        let view = VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<6, id: \.self) { Text("row \($0)") }
                    // Not a focusable control: the reveal would scroll a
                    // focused one into the viewport.
                    Text("press").onTapGesture { pressed.value = true }
                }
            }
            .frame(height: 3)
            .scrollClipDisabled()
        }
        frames.render(view)
        let line = frames.lines.firstIndex { $0.contains("press") }
        #expect(line == 6, "drawn past the three-line viewport: \(frames.lines)")
        let dispatcher = frames.tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(frames.last.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 6))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 6))
        #expect(pressed.value, "a click where it is drawn reached it: \(frames.last.hitTestRegions)")
    }

    @Test("Across: a horizontal scroll view's content runs on beside it")
    func runsOnAcross() {
        let frames = Frames(width: 30, height: 3)
        let view = HStack(spacing: 0) {
            ScrollView(.horizontal) { Text("abcdefghijklmnopqrst") }
                .frame(width: 10)
                .scrollClipDisabled()
        }
        frames.render(view)
        #expect(frames.lines.first == "abcdefghijklmnopqrst", "\(frames.lines)")
        let clipped = Frames(width: 30, height: 3)
        clipped.render(
            HStack(spacing: 0) { ScrollView(.horizontal) { Text("abcdefghijklmnopqrst") }.frame(width: 10) })
        #expect(clipped.lines.first == "abcdefghij")
    }

    @Test("The content's floating drawing is not cut at the viewport")
    func offsetLayersFloat() {
        func lines(clipDisabled: Bool) -> [String] {
            let frames = Frames(width: 20, height: 6)
            frames.render(
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView { Text("moved").offset(y: 3) }
                        .frame(height: 2)
                        .scrollClipDisabled(clipDisabled)
                })
            return frames.lines
        }
        #expect(!lines(clipDisabled: false).contains("moved"), "cut at the two-line viewport")
        #expect(lines(clipDisabled: true).firstIndex(of: "moved") == 3, "\(lines(clipDisabled: true))")
    }

    /// With a margin: the page's content margins reach the menu's scroller
    /// too, and it used to draw them through a copy of itself that forgot it
    /// was the framework's.
    @Test(
        "The framework's own scroller — a tall inline menu's — keeps its rows inside its box",
        arguments: [0, 1])
    func chromeScrollerClips(margin: Int) {
        let frames = Frames(width: 30, height: 14)
        frames.render(
            VStack {
                Menu("Pick") {
                    ForEach(0..<60, id: \.self) { index in Button("item \(index)") {} }
                }
                .menuStyle(.inline)
            }
            .contentMargins(margin)
            .scrollClipDisabled())
        let lines = frames.last.lines.map(\.stripped)
        let withItems = lines.indices.filter { lines[$0].contains("item") }
        #expect(!withItems.isEmpty)
        #expect(withItems.allSatisfy { lines[$0].hasPrefix("│") }, "an item drawn outside the box: \(lines)")
        #expect(lines.first?.hasPrefix("╭") == true && lines.last?.hasPrefix("╰") == true, "\(lines)")
        // Nothing of the next item over the bottom border either: a wrapped
        // label's second line has no "item" in it.
        #expect(lines.last?.trimmingCharacters(in: .whitespaces).allSatisfy { "╰─╯".contains($0) } == true, "\(lines)")
    }

    // MARK: - What the overflow draws is what is clicked

    @Test("A click beside a short overflowing row reaches the view drawn there, not the row")
    func clickBesideOverflowReachesTheViewBelow() {
        let frames = Frames(width: 30, height: 8)
        let deleted = Box(false)
        let tapped = Box<Int?>(nil)
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("Delete all files").onTapGesture { deleted.value = true }
            Text("keep")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<6, id: \.self) { index in
                        // Row 1 is long, so the rows above the viewport are
                        // wider than row 0 alone.
                        Text(index == 1 ? "r1 " + String(repeating: "-", count: 22) : "r\(index)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture { tapped.value = index }
                    }
                }
            }
            .frame(height: 3)
            .scrollClipDisabled()
        }
        frames.render(view)
        frames.scrollView?.scrollToOffset(2)
        frames.render(view)
        // Rows 0 and 1 run up over the first two lines: "r0" over the start of
        // the text, whose rest still shows and is still the text's.
        let first = frames.last.lines.first?.stripped ?? ""
        #expect(first.hasPrefix("r0") && first.contains("files"), "\(frames.lines)")
        let column = first.range(of: "files").map { first.distance(from: first.startIndex, to: $0.lowerBound) } ?? 0
        let dispatcher = frames.tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(frames.last.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column + 1, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: column + 1, y: 0))
        #expect(tapped.value == nil, "the row's blank cells took the click")
        #expect(deleted.value, "the text drawn there was clicked")
        // On the row's own cells, the row.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        #expect(tapped.value == 0)
    }

    @Test("An overflow layer keeps the cells it paints, and its regions only over them")
    func drawnPartsKeepPaintedCells() {
        var content = FrameBuffer(lines: ["ab      ", "  cd    ", "        ", "efghij  ", "        "])
        content.hitTestRegions = [
            HitTestRegion(offsetX: 0, offsetY: 0, width: 8, height: 5, handlerID: .init(1))
        ]
        content.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 8, height: 4, opacity: 0.5)]
        var layer = OverlayLayer(offsetX: 10, offsetY: 20, content: content, isOpaque: false)
        layer.isScrollOverflow = true
        let parts = layer.drawnParts()
        // Rows 0 and 1 start at different columns, row 2 paints nothing, and
        // row 4 paints nothing either.
        #expect(parts.map { [$0.offsetX, $0.offsetY] } == [[10, 20], [12, 21], [10, 23]])
        #expect(parts.map { $0.content.lines.map(\.stripped) } == [["ab"], ["cd"], ["efghij"]])
        let marked = parts.allSatisfy(\.isScrollOverflow)
        #expect(marked)
        let regions = parts.flatMap { part in
            part.content.hitTestRegions.map { [part.offsetX + $0.offsetX, part.offsetY + $0.offsetY, $0.width, $0.height] }
        }
        #expect(regions == [[10, 20, 2, 1], [12, 21, 2, 1], [10, 23, 6, 1]], "\(regions)")
        let faded = parts.flatMap { part in
            part.content.opacityRegions.map { [part.offsetX + $0.offsetX, part.offsetY + $0.offsetY, $0.width, $0.height] }
        }
        #expect(faded == [[10, 20, 2, 1], [12, 21, 2, 1], [10, 23, 6, 1]], "\(faded)")
    }

    @Test("A space styled to show, or a cell a run repaints, is painted: the overflow keeps it, drawn and clicked")
    func styledSpacesAndRunsArePainted() {
        let reverse = "\u{1B}[7m", underline = "\u{1B}[4m", reset = "\u{1B}[0m"
        var content = FrameBuffer(lines: [
            "ab\(reverse) \(reset)     ",  // a reverse-video caret after the text
            "  \(underline)  \(reset)    ",  // an underlined blank, nothing else
            "        ",  // blank, but a run blinks a caret on its fourth cell
        ])
        content.hitTestRegions = [HitTestRegion(offsetX: 0, offsetY: 0, width: 8, height: 3, handlerID: .init(1))]
        content.animatedCells = [
            AnimatedCellRun(offsetX: 3, offsetY: 2, width: 1, frames: ["\(reverse) \(reset)", " "], clock: .content)
        ]
        var layer = OverlayLayer(offsetX: 0, offsetY: 0, content: content, isOpaque: false)
        layer.isScrollOverflow = true
        let parts = layer.drawnParts()
        #expect(parts.map { [$0.offsetX, $0.offsetY, $0.content.height] } == [[0, 0, 1], [2, 1, 1], [3, 2, 1]], "\(parts)")
        #expect(parts.map { $0.content.lines.first?.strippedLength ?? -1 } == [3, 2, 1])
        #expect(parts.last?.content.animatedCells.count == 1, "the run goes with its cell")
        let regions = parts.flatMap { part in
            part.content.hitTestRegions.map { [part.offsetX + $0.offsetX, part.offsetY + $0.offsetY, $0.width] }
        }
        #expect(regions == [[0, 0, 3], [2, 1, 2], [3, 2, 1]], "\(regions)")
    }

    @Test("Lines that paint nothing leave nothing to click, however wide their regions")
    func blankOverflowLeavesNothing() {
        var content = FrameBuffer(lines: ["     ", "     "])
        content.hitTestRegions = [HitTestRegion(offsetX: 0, offsetY: 0, width: 5, height: 2, handlerID: .init(1))]
        var layer = OverlayLayer(offsetX: 0, offsetY: 0, content: content, isOpaque: false)
        layer.isScrollOverflow = true
        #expect(layer.drawnParts().isEmpty)
        var trimmed = layer
        trimmed.content = FrameBuffer(lines: [])
        trimmed.content.hitTestRegions = content.hitTestRegions
        #expect(trimmed.excluding(x: 50, y: 50, width: 1, height: 1).isEmpty, "a layer with no cells keeps no regions")
    }

    // MARK: - A later view covers what it draws

    private func overflowing() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<8, id: \.self) { Text("row \($0)") } }
        }
        .frame(width: 12, height: 2)
        .scrollClipDisabled()
    }

    @Test("A short later view, aligned in its stack, covers its text and not the stack's padding")
    func alignmentPaddingDoesNotCover() {
        let frames = Frames(width: 30, height: 8)
        frames.render(VStack(alignment: .trailing, spacing: 0) { overflowing(); Text("ab") })
        #expect(frames.lines[2] == "row 2     ab", "\(frames.lines)")
        #expect(frames.lines[3] == "row 3", "\(frames.lines)")
    }

    /// The reviewer's case for 5b89231e3: a later view whose tap area, its
    /// whole frame here, runs under the overflow drawn through its padding.
    /// Clicks follow what is drawn, as the overflow's own do (B-D2S-5) — and as
    /// SwiftUI's do for a view with no `contentShape`, whose padding is not
    /// hit at all.
    @Test("Under a later view's padding, a click on the overflow drawn there is the overflow's; the rest is the view's")
    func laterViewPaddingClicksFollowTheDrawing() {
        let frames = Frames(width: 30, height: 8)
        let tapped = Box<Int?>(nil)
        let okay = Box(0)
        let view = VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in
                        Text("row \(index)").onTapGesture { tapped.value = index }
                    }
                }
            }
            .frame(width: 12, height: 2)
            .scrollClipDisabled()
            Text("OK").frame(width: 12, alignment: .leading).onTapGesture { okay.value += 1 }
        }
        frames.render(view)
        #expect(frames.lines[2] == "OKw 2", "\(frames.lines)")
        let dispatcher = frames.tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(frames.last.hitTestRegions)
        func click(_ x: Int) {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: 2))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: 2))
        }
        click(3)
        #expect(tapped.value == 2 && okay.value == 0, "the \"w\" drawn there is row 2's")
        click(0)
        #expect(okay.value == 1, "the view's own text is the view's")
        click(8)
        #expect(okay.value == 2 && tapped.value == 2, "past the overflow's last cell the padding is the view's again")
    }

    @Test("Blank later views cover nothing: a spacer, an offset view's footprint, an overlay's leading space")
    func blankCellsDoNotCover() {
        let frames = Frames(width: 30, height: 8)
        frames.render(
            VStack(alignment: .leading, spacing: 0) {
                overflowing()
                Text("moved").offset(x: 20)
                Spacer().frame(width: 12, height: 3)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 0) { Spacer(); Text("!") }.frame(width: 12)
            })
        let lines = frames.lines
        #expect(lines[2].hasPrefix("row 2") && lines[2].contains("moved"), "\(lines)")
        #expect(lines[3].hasPrefix("row 3"), "\(lines)")
        #expect(lines[5].hasPrefix("row 5") && lines[5].hasSuffix("!"), "\(lines)")
    }

    // MARK: - What the cover costs where nothing is unclipped

    private func floating(_ text: String, overflow: Bool = false) -> FrameBuffer {
        var buffer = FrameBuffer(lines: [text])
        var layer = OverlayLayer(offsetX: 3, offsetY: 0, content: FrameBuffer(lines: ["*"]), isOpaque: false)
        layer.isScrollOverflow = overflow
        buffer.overlays = [layer]
        return buffer
    }

    @Test("A stack of children with layers knows, after each append, that none is overflow")
    func stackKnowsItHoldsNoOverflow() {
        var column = FrameBuffer()
        for index in 0..<200 {
            column.appendVertically(floating("row \(index)"))
            // Known without looking: the next append's cover test is one field.
            #expect(column.overlaysAreFreeOfScrollOverflow, "unknown after child \(index)")
        }
        var row = FrameBuffer()
        row.appendHorizontally(floating("a"))
        row.appendHorizontally(floating("b"))
        #expect(row.overlaysAreFreeOfScrollOverflow)
        let composited = column.composited(with: floating("over"), at: (x: 0, y: 0))
        #expect(composited.overlaysAreFreeOfScrollOverflow)
        #expect(column.overlays.count == 200)
    }

    @Test("Overflow in a buffer, however it got there, is still covered by what comes after it")
    func hintNeverHidesOverflow() {
        var column = FrameBuffer()
        column.appendVertically(floating("x"))
        #expect(column.overlaysAreFreeOfScrollOverflow)
        // Put there directly, not through a combining operation.
        var layer = OverlayLayer(offsetX: 0, offsetY: 1, content: FrameBuffer(lines: ["overflow"]), isOpaque: false)
        layer.isScrollOverflow = true
        column.overlays.append(layer)
        #expect(!column.overlaysAreFreeOfScrollOverflow, "any change to the layers is unknown")
        column.appendVertically(FrameBuffer(lines: ["cover"]))
        // "cover" paints the overflow's first five cells: "low" is left of it.
        let drawn = column.overlays.filter(\.isScrollOverflow).map { "\($0.offsetX): \($0.content.lines.map(\.stripped))" }
        #expect(drawn == ["5: [\"low\"]"], "\(drawn)")
        #expect(!column.overlaysAreFreeOfScrollOverflow)
    }

    @MainActor
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
