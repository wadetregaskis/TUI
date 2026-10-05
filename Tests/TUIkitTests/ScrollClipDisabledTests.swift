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

@testable import TUIkit
@testable import TUIkitCore
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

    @MainActor
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
