//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyViewMembersTests.swift
//
//  An `AnyView` around several views hands its container each of them, as
//  SwiftUI's does (measured on macOS 15.8,
//  `Tools/SwiftUIProbes/Sections and subview counting/b15.swift`: two rows of
//  `AnyView(Group { a; b })` are four subviews, and an `HStack` lays them along
//  its row). It was one child everywhere. Decisions D1S, B-D1S-3.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport
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

/// How many rows a loop's closure has built.
@MainActor
private final class Built {
    var rows = 0
    func count() { rows += 1 }
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

    @Test("An AnyView's views are the container's children, each at an identity of its own, the same on every frame")
    func identities() {
        let paths = Paths()
        let view = HStack(spacing: 1) {
            AnyView(Group { PathProbe(paths: paths, name: "a"); PathProbe(paths: paths, name: "b") })
            PathProbe(paths: paths, name: "c")
        }
        let drawn = lines(view)
        // Laid along the row: taken apart, not one child stacking its two.
        #expect(drawn.first?.hasPrefix("a b c") == true, "\(drawn)")
        let first = paths.drawn
        paths.drawn = []
        _ = lines(view)
        // Measured and drawn more than once a frame; three places either way,
        // none shared with the sibling of the same type beside them.
        #expect(Set(first).count == 3, "\(first)")
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

    @Test("An AnyView in a container is taken apart, and as a ForEach's row stays one child, keeping the loop's row memo and laziness")
    func loopRowsStayWhole() {
        let loop = ForEach(0..<2, id: \.self) { i in AnyView(Group { Text("r\(i)"); Text("s\(i)") }) }
        #expect(loop.rowShape(sectionWholeness: .apart) == .single)
        #expect(resolveChildViews(from: loop, context: makeRenderContext(width: 10, height: 4)).count == 2)
        // Beside it in one row: the AnyView written in the HStack lays its two
        // along the row, each erased row stacks its two in a column.
        let drawn = lines(HStack(alignment: .top, spacing: 1) { AnyView(Group { Text("a"); Text("b") }); loop })
            .map { String($0.reversed().drop { $0 == " " }.reversed()) }
        #expect(Array(drawn.prefix(2)) == ["a b r0 r1", "    s0 s1"], "\(drawn)")
    }

    /// What the second of two frames of `view` composed and served, under the
    /// live loop's per-pass lifecycle over one render cache.
    private func secondFrameRowWork(_ view: some View) -> RenderCache.RowWork {
        let tui = TUIContext()
        func frame() {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            environment.installVolatileReadTracker(VolatileReadTracker())
            let context = RenderContext(
                availableWidth: 30, availableHeight: 40, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        frame()
        let before = tui.renderCache.rowWork
        frame()
        return tui.renderCache.rowWork.delta(since: before)
    }

    @Test("A loop of bordered rows, or of rows erased in an if/else arm or under an if, is one child a row and serves its rows from the memo on the next frame")
    func erasedArmRowsKeepTheRowMemo() {
        // `.border()` is `if width <= 0 { self } else { AnyView(rings) }`: an
        // `AnyView` in an arm. Counted as spliced, its rows' count was unknown,
        // and the loop built and took apart every row on every walk, its row
        // memo never consulted — the `modifiers` scenario's 400 rows went from
        // all served to none.
        let bordered = ForEach(0..<6, id: \.self) { i in Text("r\(i)").padding(1).border() }
        let filtered = ForEach(0..<6, id: \.self) { i in if i >= 0 { Text("f\(i)").border() } }
        let erased = ForEach(0..<6, id: \.self) { i in
            if i.isMultiple(of: 2) { AnyView(Text("e\(i)")) } else { Text("t\(i)").border() }
        }
        #expect(bordered.rowShape(sectionWholeness: .apart) == .single)
        #expect(filtered.rowShape(sectionWholeness: .apart) == .single)
        #expect(erased.rowShape(sectionWholeness: .apart) == .single)
        // Arms that differ as rows still leave the count to the row.
        let differing = ForEach(0..<2, id: \.self) { i in
            if i > 0 { Group { Text("a"); Text("b") } } else { AnyView(Text("c")) }
        }
        #expect(differing.rowShape(sectionWholeness: .apart) == .varying)

        for work in [
            secondFrameRowWork(VStack(spacing: 0) { bordered }),
            secondFrameRowWork(VStack(spacing: 0) { filtered }),
            secondFrameRowWork(VStack(spacing: 0) { erased }),
        ] {
            #expect(work.rendered == 0 && work.served >= 6, "\(work)")
        }
    }

    /// `.border()` erases its rings, and an `AnyView`'s type says nothing of
    /// how many views it holds: a row of several views with one bordered
    /// counted as varying, and its loop built and counted every row on every
    /// walk — in a lazy stack, every row of the collection, not the window's.
    @Test("A row of several views with one bordered counts them from its type, and a lazy stack of them builds its window")
    func rowWithOneBorderedViewCounts() {
        let bordered = ForEach(0..<6, id: \.self) { i in
            Text("a\(i)")
            Text("b\(i)").border()
        }
        #expect(bordered.rowShape(sectionWholeness: .apart) == .fixed(2))
        #expect(resolveChildViews(from: bordered, context: makeRenderContext(width: 10, height: 4)).count == 12)

        // Rows built on the second of two frames of a lazy stack of 200 such
        // rows, six lines tall — against the same rows with nothing bordered.
        let built = Built()
        let borderedRows = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<200, id: \.self) { i in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built.count()
                    Text("a\(i)")
                    Text("b\(i)").border()
                }
            }
        }
        .frame(height: 6)
        let plainRows = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<200, id: \.self) { i in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built.count()
                    Text("a\(i)")
                    Text("b\(i)")
                }
            }
        }
        .frame(height: 6)
        // The same rows with the bordered view padded to the rings' cells
        // instead: as tall, nothing erased.
        let paddedRows = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<200, id: \.self) { i in
                    // swiftlint:disable:next redundant_discardable_let
                    let _ = built.count()
                    Text("a\(i)")
                    Text("b\(i)").padding(1)
                }
            }
        }
        .frame(height: 6)
        let bordering = secondFrameRowsBuilt(borderedRows, counting: built)
        let plain = secondFrameRowsBuilt(plainRows, counting: built)
        let padded = secondFrameRowsBuilt(paddedRows, counting: built)
        // Counted as varying, every row was built three times a frame (600).
        // Its window's rows are built now — more often than the plain rows',
        // and exactly as often as the same rows' with the rings' cells padded
        // instead, nothing erased: what costs the extra builds is the rows'
        // heights, views one and three lines tall in turn, not the erasure.
        // (Which window path that sends the stack down is not established
        // here.)
        #expect(bordering == padded, "a frame built \(bordering) of 200 bordered rows, \(padded) padded")
        #expect(bordering < 200 / 4, "a frame built \(bordering) of 200 bordered rows (\(plain) plain)")
        #expect(plain < 200 / 4, "precondition: \(plain) of 200 plain rows")
    }

    /// How many rows `built` counted on the second of two frames of `view`.
    private func secondFrameRowsBuilt(_ view: some View, counting built: Built) -> Int {
        let tui = TUIContext()
        func frame() {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            environment.installVolatileReadTracker(VolatileReadTracker())
            let context = RenderContext(
                availableWidth: 30, availableHeight: 40, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        frame()
        built.rows = 0
        frame()
        return built.rows
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
