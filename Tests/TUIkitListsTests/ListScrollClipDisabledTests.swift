//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListScrollClipDisabledTests.swift
//
//  `scrollClipDisabled(_:)` on a `List` (decisions B-D2S-4): the rows next to
//  the window draw past the list's frame, as SwiftUI's list draws rows on
//  below its frame with the modifier set (measured on macOS 15), at the list's
//  place in the stacking order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("scrollClipDisabled on a List")
struct ListScrollClipDisabledTests {
    @MainActor
    private final class Frames {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var last = FrameBuffer()

        /// The frame, its layers composited as the screen root composites them.
        @discardableResult
        func render<V: View>(_ view: V) -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(availableWidth: 20, availableHeight: 12, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            last = buffer.compositingOverlays(maxWidth: 20, maxHeight: 12, palette: environment.palette)
            return last
        }

        var lines: [String] { last.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } }

        var list: ItemListHandler<Int>? { focusManager.currentFocused as? ItemListHandler<Int> }
    }

    /// A plain list four lines tall between two blank lines, so what it draws
    /// past its frame shows.
    private func page(clipDisabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("top")
            Spacer().frame(height: 1)
            List(selection: .constant(Int?.none)) {
                ForEach(0..<20, id: \.self) { Text("row \($0)") }
            }
            .listStyle(.plain)
            .frame(height: 4)
            .scrollClipDisabled(clipDisabled)
            Spacer().frame(height: 1)
            Text("bottom")
        }
    }

    @Test("Clipped, the default: no row is drawn past the frame")
    func clippedByDefault() {
        let frames = Frames()
        frames.render(page(clipDisabled: false))
        #expect(Array(frames.lines.prefix(8)) == ["top", "", "row 0", "row 1", "row 2", "row 3", "", "bottom"],
            "\(frames.lines)")
    }

    @Test("Unclipped: the next row draws below the frame, and the one before above it once scrolled")
    func rowsRunOn() {
        let frames = Frames()
        let view = page(clipDisabled: true)
        frames.render(view)
        #expect(Array(frames.lines.prefix(8)) == ["top", "", "row 0", "row 1", "row 2", "row 3", "row 4", "bottom"],
            "\(frames.lines)")
        frames.list?.scrollToOffset(3)
        frames.render(view)
        #expect(Array(frames.lines.prefix(8)) == ["top", "row 2", "row 3", "row 4", "row 5", "row 6", "row 7", "bottom"],
            "\(frames.lines)")
    }
}
