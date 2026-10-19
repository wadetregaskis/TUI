//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitDividerPointerShapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitNavigation
@testable import TUIkitTestSupport

/// The resize arrows TUIkit's split dividers give the pointer, where its
/// controls set their own shapes (decisions O12, B-O12-6).
@MainActor
@Suite("Split dividers' pointer shapes")
struct SplitDividerPointerShapeTests {
    /// The cell of the first region with a focus id that is one cell across
    /// the axis: the divider's.
    private func divider(in buffer: FrameBuffer, wide: Bool) -> (x: Int, y: Int)? {
        buffer.hitTestRegions.first { region in
            region.focusID != nil && (wide ? region.height == 1 && region.width > 1 : region.width == 1 && region.height > 1)
        }.map { (x: $0.offsetX, y: $0.offsetY) }
    }

    @Test("An HSplitView's divider gives a column's arrow, a VSplitView's a row's")
    func splitViews() {
        let harness = PointerShapeHarness(controlShapes: true)
        let across = harness.frame(HSplitView { Text("left"); Text("right") })
        guard let column = divider(in: across, wide: false) else {
            Issue.record("no divider region: \(across.hitTestRegions)")
            return
        }
        #expect(harness.shape(atX: column.x, y: column.y) == .columnResize)
        let down = harness.frame(VSplitView { Text("top"); Text("bottom") })
        guard let row = divider(in: down, wide: true) else {
            Issue.record("no divider region: \(down.hitTestRegions)")
            return
        }
        #expect(harness.shape(atX: row.x, y: row.y) == .rowResize)
    }

    @Test("A NavigationSplitView's divider gives a column's arrow")
    func navigationSplitView() {
        let harness = PointerShapeHarness(controlShapes: true, width: 60)
        let buffer = harness.frame(NavigationSplitView { Text("sidebar") } detail: { Text("detail") })
        guard let column = divider(in: buffer, wide: false) else {
            Issue.record("no divider region: \(buffer.hitTestRegions)")
            return
        }
        #expect(harness.shape(atX: column.x, y: column.y) == .columnResize)
    }
}
