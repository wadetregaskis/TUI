//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyViewMembersTests.swift
//
//  An `AnyView` around several views hands its container each of them, as
//  SwiftUI's does (measured on macOS 15.8, `D1S/probe/b15`: two rows of
//  `AnyView(Group { a; b })` are four subviews, and an `HStack` lays them along
//  its row). It was one child everywhere. Decisions D1S, B-D1S-3.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// What a layout was handed.
@MainActor
private final class Count {
    var subviews = -1
}

private struct Counting: Layout {
    let count: Count

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        count.subviews = subviews.count
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

/// Records the identity path it is drawn at.
@MainActor
private final class Paths {
    var drawn: [String] = []
}

private struct PathProbe: View, Renderable {
    let paths: Paths
    let name: String
    var body: Never { fatalError("PathProbe renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        paths.drawn.append(context.identity.path)
        return FrameBuffer(text: name)
    }
}

@MainActor
@Suite("An AnyView around several views is several children")
struct AnyViewMembersTests {

    private func lines(_ view: some View, width: Int = 20) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 8)).lines.map(\.stripped)
    }

    private func subviewCount(_ view: some View) -> Int {
        var count = -1
        _ = lines(
            Group(subviews: view) { subviews -> EmptyView in
                count = subviews.count
                return EmptyView()
            })
        return count
    }

    @Test("The subview APIs and a Layout count what an AnyView erases, as SwiftUI does")
    func counts() {
        #expect(subviewCount(AnyView(Group { Text("a"); Text("b") })) == 2)
        #expect(subviewCount(AnyView(Text("a"))) == 1)
        let count = Count()
        _ = lines(Counting(count: count) { AnyView(Group { Text("a"); Text("b") }); Text("c") })
        #expect(count.subviews == 3)
    }

    @Test("An HStack lays an AnyView's views along its row")
    func row() {
        let drawn = lines(HStack(spacing: 1) { AnyView(Group { Text("a"); Text("b") }); Text("c") })
        #expect(drawn.first?.hasPrefix("a b c") == true, "\(drawn)")
    }

    @Test("An AnyView's views keep identities of their own, the same on every frame")
    func identities() {
        let paths = Paths()
        let view = VStack {
            AnyView(Group { PathProbe(paths: paths, name: "a"); PathProbe(paths: paths, name: "b") })
        }
        _ = lines(view)
        let first = paths.drawn
        paths.drawn = []
        _ = lines(view)
        // Measured and drawn more than once a frame; two places either way.
        #expect(Set(first).count == 2, "\(first)")
        #expect(Set(paths.drawn) == Set(first))
    }

    @Test("A List reads the rows of a loop in an AnyView, each selected by its element")
    func listOfAnErasedLoop() {
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                AnyView(ForEach(["alpha", "beta"], id: \.self) { Text($0) })
            }
            .frame(height: 6))
        let handler = fixture.handler
        #expect(handler?.itemCount == 2)
        #expect((0..<2).map { handler?.id(at: $0) } == ["alpha", "beta"])
    }

    @Test("As a ForEach's row an AnyView stays one child, keeping the loop's row memo and laziness")
    func loopRowsStayWhole() {
        let loop = ForEach(0..<3, id: \.self) { _ in AnyView(Group { Text("a"); Text("b") }) }
        #expect(loop.rowShape(keepingSectionsWhole: false) == .single)
        #expect(resolveChildViews(from: loop, context: makeRenderContext(width: 10, height: 4)).count == 3)
    }
}
