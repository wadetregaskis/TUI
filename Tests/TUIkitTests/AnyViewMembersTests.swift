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

/// Records the section wholeness of the walk it is drawn in.
@MainActor
private final class Wholeness {
    var seen: [SectionWholeness] = []
}

private struct WholenessProbe: View, Renderable {
    let wholeness: Wholeness
    var body: Never { fatalError("WholenessProbe renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        wholeness.seen.append(context.sectionWholeness)
        return FrameBuffer(text: "w")
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
        #expect(loop.rowShape(sectionWholeness: .apart) == .single)
        #expect(resolveChildViews(from: loop, context: makeRenderContext(width: 10, height: 4)).count == 3)
    }

    @Test("An AnyView around one view costs a lazy stack no section scope, as a plain view costs it none")
    func oneViewCostsNoSectionScope() {
        #expect(AnyView.erasesOneView(AnyView(Text("a"))))
        #expect(!AnyView.erasesOneView(AnyView(Group { Text("a"); Text("b") })))
        #expect(!AnyView.erasesOneView(Text("a")))
        // A loop of erased rows hands over no section: a loop never takes an
        // erased row apart. One erased view is answered by what it erases.
        #expect(!mayHandOver(.section, ForEach<Range<Int>, Int, AnyView>.self))
        #expect(!mayHandOver(.section, in: AnyView(Text("a"))))
        #expect(mayHandOver(.section, in: AnyView(Section { Text("a") })))
        // So the rows of such a stack are drawn in a walk that keeps no section
        // whole, as they were before an `AnyView` was a provider.
        let wholeness = Wholeness()
        _ = lines(
            ScrollView {
                LazyVStack { ForEach(0..<3, id: \.self) { _ in AnyView(WholenessProbe(wholeness: wholeness)) } }
            }.frame(height: 4))
        _ = lines(ScrollView { LazyVStack { AnyView(WholenessProbe(wholeness: wholeness)) } }.frame(height: 4))
        #expect(!wholeness.seen.isEmpty && wholeness.seen.allSatisfy { $0 == .apart }, "\(wholeness.seen)")
    }

    /// Renders `probe` — or `-` without one — from the environment, and is
    /// equal to every other instance, so only the erased type's note can stop
    /// its memo serving what it drew under a probe that has gone.
    private struct ProbeEcho: View, Equatable {
        nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
        @Environment(\.anyViewMembersProbe) private var probe
        var body: some View { Text(probe) }
    }

    @Test("An AnyView taken apart whose content drops a modifier draws its views without it")
    func takenApartContentChangingTypeIsNotServedStale() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.renderCache = RenderCache()
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4, environment: environment,
            identity: ViewIdentity(path: "Root"))
        func frame(_ flag: Bool) -> String {
            let view = HStack(spacing: 1) {
                flag
                    ? AnyView(Group { ProbeEcho().equatable(); Text("t") }.environment(\.anyViewMembersProbe, "xxx"))
                    : AnyView(Group { ProbeEcho().equatable(); Text("t") })
            }
            let cache = context.environment.renderCache!
            cache.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            cache.removeInactive()
            return buffer.lines.first?.stripped ?? ""
        }
        #expect(frame(true).hasPrefix("xxx t"))
        #expect(frame(true).hasPrefix("xxx t"))
        let swapped = frame(false)
        #expect(swapped.hasPrefix("- t"), "served under the modifier that was swapped out: \(swapped)")
    }
}

private struct AnyViewMembersProbeKey: EnvironmentKey {
    static let defaultValue = "-"
}

extension EnvironmentValues {
    fileprivate var anyViewMembersProbe: String {
        get { self[AnyViewMembersProbeKey.self] }
        set { self[AnyViewMembersProbeKey.self] = newValue }
    }
}
