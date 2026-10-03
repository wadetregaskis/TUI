//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerRelativeFrameTests.swift
//
//  `containerRelativeFrame`, against SwiftUI's measured rules: the length is
//  the nearest container's — the window's content area, a scroll view's
//  viewport — and a frame in between is not a container.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

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
