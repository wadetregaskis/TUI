//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewNarrowWidthTests.swift
//
//  A split view with no room for its columns side by side collapses into a
//  stack, as it does in a compact size class. Before, three columns at 20
//  cells drew 32 wide, and Tab reached a divider past the screen's edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUINavigation
@testable import TUITestSupport

@MainActor
@Suite("A split view too narrow for its columns collapses into a stack", .rendersEnglishUI)
struct NavigationSplitViewNarrowWidthTests {

    private func splitContext(width: Int, height: Int = 9) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.statusBar = StatusBarState()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: TUIContext())
    }

    /// One frame through the per-frame passes, as the run loop drives them.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!
        let focusManager = context.environment.focusManager!
        context.environment.mouseEventDispatcher?.beginRenderPass()
        stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        stateStorage.endRenderPass()
        context.environment.mouseEventDispatcher?.setRegions(buffer.hitTestRegions)
        return buffer
    }

    private final class Box {
        var visibility: NavigationSplitViewVisibility
        init(_ visibility: NavigationSplitViewVisibility) { self.visibility = visibility }
        var binding: Binding<NavigationSplitViewVisibility> {
            Binding(get: { self.visibility }, set: { self.visibility = $0 })
        }
    }

    /// Three columns, a button in each, so each column is a focus stop.
    private func threeColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Button("SIDE") {}
        } content: {
            Button("CONT") {}
        } detail: {
            Button("DETL") {}
        }
    }

    private func twoColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Button("SIDE") {}
        } detail: {
            Button("DETL") {}
        }
    }

    /// The labels the frame draws, of the three columns'.
    private func labels(_ buffer: FrameBuffer) -> [String] {
        let text = buffer.lines.map(\.stripped).joined(separator: "\n")
        return ["SIDE", "CONT", "DETL"].filter { text.contains($0) }
    }

    /// Records each focus stop that is not drawn wholly inside `width`: no
    /// region carrying its id, or one past the edge.
    private func expectStopsOnScreen(
        _ buffer: FrameBuffer, _ focusManager: FocusManager, width: Int, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(!focusManager.focusableIDs.isEmpty, "\(label): no focus stops", sourceLocation: sourceLocation)
        for id in focusManager.focusableIDs {
            let regions = buffer.hitTestRegions.filter { $0.focusID == id }
            #expect(!regions.isEmpty, "\(label): \(id) is not drawn", sourceLocation: sourceLocation)
            #expect(
                regions.allSatisfy { $0.offsetX >= 0 && $0.offsetX + $0.width <= width },
                "\(label): \(id) is drawn past the edge, at \(regions.map { ($0.offsetX, $0.width) })",
                sourceLocation: sourceLocation)
        }
    }

    @Test("No row is wider than the width, and every focus stop is drawn inside it", arguments: [20, 40, 80])
    func fits(width: Int) {
        for three in [true, false] {
            let context = splitContext(width: width)
            let focusManager = context.environment.focusManager!
            let box = Box(.all)
            let view = three ? AnyView(threeColumns(box)) : AnyView(twoColumns(box))
            _ = frame(view, context)
            let buffer = frame(view, context)
            let label = "\(three ? "three" : "two") columns at \(width)"
            #expect(buffer.width <= width, "\(label): \(buffer.width) wide")
            for line in buffer.lines {
                #expect(line.stripped.count <= width, "\(label): \(line.stripped)")
            }
            expectStopsOnScreen(buffer, focusManager, width: width, label)
            #expect(box.visibility == .all, "\(label): the visibility is the app's")
        }
    }

    @Test("Side by side from 32 cells for three columns and 21 for two; below, a stack with the sidebar on top")
    func whereItCollapses() {
        let all = ["SIDE", "CONT", "DETL"]
        let expected: [(three: Bool, width: Int, labels: [String])] = [
            (true, 20, ["SIDE"]), (true, 31, ["SIDE"]), (true, 32, all), (true, 40, all), (true, 80, all),
            (false, 20, ["SIDE"]), (false, 21, ["SIDE", "DETL"]), (false, 40, ["SIDE", "DETL"]),
        ]
        for (three, width, labels) in expected {
            let context = splitContext(width: width)
            let view = three ? AnyView(threeColumns(Box(.all))) : AnyView(twoColumns(Box(.all)))
            _ = frame(view, context)
            #expect(self.labels(frame(view, context)) == labels, "\(three ? "three" : "two") at \(width)")
        }
    }

    @Test("Tab visits every stop, each on screen, and no divider that is not drawn", arguments: [20, 40, 80])
    func tabStaysOnScreen(width: Int) {
        let context = splitContext(width: width)
        let focusManager = context.environment.focusManager!
        let view = threeColumns(Box(.all))
        var buffer = frame(view, context)
        buffer = frame(view, context)
        let stops = focusManager.focusableIDs
        #expect(stops.contains { $0.hasPrefix("nav-split-divider") } == (width >= 32), "width \(width): \(stops)")
        var visited: Set<String> = []
        for _ in 0..<stops.count {
            focusManager.focusNext()
            buffer = frame(view, context)
            guard let focused = focusManager.currentFocusedID else {
                Issue.record("width \(width): nothing focused")
                continue
            }
            visited.insert(focused)
            let regions = buffer.hitTestRegions.filter { $0.focusID == focused }
            #expect(
                !regions.isEmpty && regions.allSatisfy { $0.offsetX >= 0 && $0.offsetX + $0.width <= width },
                "width \(width): \(focused) is focused off screen")
        }
        #expect(visited == Set(stops), "width \(width): Tab reached \(visited.sorted()) of \(stops)")
    }

    @Test("The columns come back side by side with the width, and the visibility never changed")
    func expandsAgain() {
        let box = Box(.all)
        let view = threeColumns(box)
        let narrow = splitContext(width: 20)
        _ = frame(view, narrow)
        #expect(labels(frame(view, narrow)) == ["SIDE"])
        let wide = narrow.withAvailableSize(width: 80, height: 9)
        _ = frame(view, wide)
        #expect(labels(frame(view, wide)) == ["SIDE", "CONT", "DETL"])
        #expect(box.visibility == .all)
    }

    @Test("The visible columns are what need room: beside the ▶ edge, then without it, then a stack")
    func roomForTheVisibleColumns() {
        let expected: [(width: Int, edge: Bool, labels: [String])] = [
            (22, true, ["CONT", "DETL"]), (21, false, ["CONT", "DETL"]), (15, false, ["SIDE"]),
        ]
        for (width, edge, labels) in expected {
            let context = splitContext(width: width)
            let focusManager = context.environment.focusManager!
            let view = threeColumns(Box(.doubleColumn))
            _ = frame(view, context)
            let buffer = frame(view, context)
            #expect(buffer.lines.contains { $0.stripped.contains("▶") } == edge, "width \(width)")
            #expect(self.labels(buffer) == labels, "width \(width)")
            #expect(buffer.width <= width, "width \(width)")
            expectStopsOnScreen(buffer, focusManager, width: width, "width \(width)")
        }
    }

    @Test("A detail shown alone never collapses, and is drawn no wider than the split", arguments: 2...12)
    func detailAloneFits(width: Int) {
        let context = splitContext(width: width)
        let view = twoColumns(Box(.detailOnly))
        _ = frame(view, context)
        let buffer = frame(view, context)
        #expect(buffer.width <= width, "\(buffer.width) wide")
        #expect(buffer.lines.contains { $0.stripped.contains("▶") }, "the edge stays")
        #expect(!labels(buffer).contains("SIDE"))
    }
}
