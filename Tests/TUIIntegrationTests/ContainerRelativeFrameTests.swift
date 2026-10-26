//  🖥️ TUI — A Terminal UI framework for Swift
//  ContainerRelativeFrameTests.swift
//
//  `containerRelativeFrame`, against SwiftUI's measured rules: the length is
//  the nearest container's — the window's content area, a scroll view's
//  viewport — and a frame in between is not a container.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("containerRelativeFrame")
struct ContainerRelativeFrameTests {
    /// One frame of a window group, `width` × `height`, trailing blanks trimmed.
    private func scene<V: View>(_ content: V, width: Int = 20, height: Int = 3) -> [String] {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = WindowGroup { content }.renderScene(context: context)
        tuiContext.stateStorage.endRenderPass()
        return buffer.lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
    }

    /// The columns `marker` starts at in `line`, its first character's.
    private func column(of marker: Character, in line: String) -> Int? {
        line.firstIndex(of: marker).map { line.distance(from: line.startIndex, to: $0) }
    }

    @Test("The window's content area is the container")
    func windowIsTheContainer() {
        // A 20-wide frame, its text at the trailing edge: the frame spans the window.
        let drawn = scene(Text("x").containerRelativeFrame(.horizontal, alignment: .trailing))
        #expect(column(of: "x", in: drawn[1]) == 19)
    }

    @Test("A frame is not a container")
    func frameIsNotAContainer() {
        // A quarter of the 20-wide window is 5, inside a 12-wide frame too.
        let drawn = scene(
            HStack(spacing: 0) {
                Text("a").containerRelativeFrame(.horizontal, count: 4, spacing: 0, alignment: .leading)
                Text("b")
            }.frame(width: 12, alignment: .leading))
        let line = drawn.first { $0.contains("a") } ?? ""
        #expect(column(of: "b", in: line).map { $0 - (column(of: "a", in: line) ?? 0) } == 5, "\(drawn)")
    }

    @Test("count, span and spacing divide the container in whole cells, dividing last")
    func countSpanSpacing() {
        // available = 20 − 2 × 3 = 14; 14 × 3 ÷ 4 = 10 (10.5 floored once); + 2 × 2 = 14.
        let drawn = scene(
            HStack(spacing: 0) {
                Text("a").containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: 2, alignment: .leading)
                Text("b")
            })
        let line = drawn.first { $0.contains("a") } ?? ""
        #expect(column(of: "b", in: line).map { $0 - (column(of: "a", in: line) ?? 0) } == 14, "\(drawn)")
    }

    @Test("A scroll view's viewport is the container for what it scrolls")
    func scrollViewIsTheContainer() {
        let drawn = scene(
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("\(index)").containerRelativeFrame(.horizontal, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: 10, height: 1))
        let line = drawn.first { $0.contains("0") } ?? ""
        #expect(column(of: "0", in: line).map { line.dropFirst($0).hasPrefix("0         ") || line.dropFirst($0) == "0" } == true,
                "each page is the viewport's 10 wide, so the next page is off-screen: \(drawn)")
        #expect(!line.contains("1"))
    }

    @Test("A scroll view's \"N more\" lines, reserved, come out of the container: a full-height view fills the window between them")
    func reservedIndicatorLinesLeaveTheContainer() {
        let drawn = scene(
            ScrollView {
                Text("x").containerRelativeFrame(.vertical, alignment: .bottom)
            }
            .scrollIndicators(.visible)
            .scrollIndicatorStyle(.text)
            .frame(height: 6),
            height: 6)
        // The window is lines 1 to 4; sized against the viewport, the x was the
        // sixth line of the content, below the window, and the view scrolled.
        #expect(drawn.firstIndex { $0.contains("x") } == 4, "\(drawn)")
        #expect(drawn.allSatisfy { !$0.contains("1 more") }, "nothing to scroll: \(drawn)")
    }

    @Test("A list is the container for its rows")
    func listIsTheContainer() {
        // A plain list in the 20-wide window: rows get the width less the gutters.
        let inList = scene(
            List {
                Text("x").containerRelativeFrame(.horizontal, alignment: .trailing)
            }
            .listStyle(.plain), height: 4)
        // Framed at the window's width, the trailing `x` would land past the
        // row's last cell and be cut; at the row's, it sits in that last cell.
        let row = inList.first { $0.contains("x") }
        #expect(row != nil, "the x is drawn: \(inList)")
        #expect(row.flatMap { column(of: "x", in: $0) }.map { (16...18).contains($0) } == true, "\(inList)")
    }

    @Test("A tab, a navigation stack and a split-view column are containers too")
    func navigationContainers() {
        let trailing = Text("x").containerRelativeFrame(.horizontal, alignment: .trailing)

        // A stack's screen is the stack's width: the window's, here.
        let stack = scene(NavigationStack { trailing }, height: 4)
        #expect(stack.compactMap { column(of: "x", in: $0) }.first == 19, "\(stack)")

        // A tab hugs its widest content, and this one is as wide as its tab.
        let tabs = scene(TabView(selection: .constant(0)) { Tab("One", value: 0) { trailing } }.tabViewStyle(.compact), height: 4)
        #expect(tabs.compactMap { column(of: "x", in: $0) }.first.map { $0 >= 15 } == true, "\(tabs)")

        // A sidebar's content is its column's width, not the window's.
        let split = scene(
            NavigationSplitView { trailing } detail: { Text("detail") }, width: 40, height: 4)
        let sidebarX = split.compactMap { column(of: "x", in: $0) }.first
        let detail = split.compactMap { line in line.range(of: "detail").map { line.distance(from: line.startIndex, to: $0.lowerBound) } }.first
        #expect(sidebarX != nil && detail != nil && sidebarX! < detail!, "\(split)")
        #expect(sidebarX.map { $0 > 5 } == true, "trailing in its column: \(split)")
    }

    @Test("The closure form works the length out from the container's")
    func closureForm() {
        let drawn = scene(
            HStack(spacing: 0) {
                Text("a").containerRelativeFrame(.horizontal, alignment: .leading) { length, axis in
                    axis == .horizontal ? length / 4 : length
                }
                Text("b")
            })
        let line = drawn.first { $0.contains("a") } ?? ""
        #expect(column(of: "b", in: line).map { $0 - (column(of: "a", in: line) ?? 0) } == 5)
    }

    @Test("With no container around it the view keeps its own size")
    func noContainer() {
        let buffer = renderToBuffer(
            Text("x").containerRelativeFrame(.horizontal), context: makeRenderContext(width: 20, height: 1))
        #expect(buffer.width == 1)
    }
}
