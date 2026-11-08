//  🖥️ TUI — A Terminal UI framework for Swift
//  EffectOnMultiMemberContentTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIFoundation
import TUIGrid
@testable import TUITestSupport

/// An effect modifier written on content of several members — a `Group`, a
/// `ForEach`, a `GridRow`'s cells — leaves the members separate children of
/// the enclosing stack or grid, and fires its effect once for all of them.
///
/// Both halves measured in SwiftUI with an `NSHostingView` probe: layout
/// distributes per member, and `.onAppear` on a two-member `Group` or a
/// `ForEach` of three, and `.task` on a `Group`, each fire once. Before, the
/// members reached the stack as one opaque child, stacked vertically: an
/// `.onAppear` turned a row into a column, and a `GridRow` carrying one fell
/// out of the grid's columns.
@MainActor
@Suite("Effect modifiers on multi-member content")
struct EffectOnMultiMemberContentTests {

    @MainActor final class Counter {
        var value = 0
        func bump() { value += 1 }
    }

    /// A context whose state and lifecycle persist across frames, as the run
    /// loop's do.
    private func makeContext(width: Int = 40, height: Int = 12) -> RenderContext {
        makeRenderContext(width: width, height: height)
    }

    /// Renders `view` once a frame for `frames` frames, bracketed as the run
    /// loop brackets a frame, letting the tasks a frame started finish.
    @discardableResult
    private func renderFrames<V: View>(_ view: V, frames: Int, context: RenderContext) async -> [String] {
        var lines: [String] = []
        for _ in 0..<frames {
            context.environment.lifecycle?.beginRenderPass()
            lines = renderToBuffer(view, context: context).lines.map(\.stripped)
            context.environment.lifecycle?.endRenderPass()
            if let lifecycle = context.environment.lifecycle { await finishStartedTasks(of: lifecycle) }
        }
        return lines
    }

    // MARK: - Layout

    @Test("An .onAppear on a Group in an HStack lays its members side by side")
    func onAppearGroupKeepsTheRow() async {
        let plain = await renderFrames(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            }, frames: 1, context: makeContext())
        let modified = await renderFrames(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
                .onAppear {}
            }, frames: 1, context: makeContext())
        #expect(modified == plain)
        #expect(modified.first?.trimmingTrailingSpaces == "A B")
    }

    @Test("Every effect modifier keeps a Group's members side by side")
    func everyEffectModifierKeepsTheRow() async {
        func row(_ view: some View) async -> [String] {
            await renderFrames(HStack(spacing: 1) { view }, frames: 1, context: makeContext())
        }
        let group = Group {
            Text("A")
            Text("B")
        }
        let expected = ["A B"]
        #expect(await row(group.onDisappear {}).map(\.trimmingTrailingSpaces) == expected)
        #expect(await row(group.task {}).map(\.trimmingTrailingSpaces) == expected)
        #expect(await row(group.onChange(of: 1) {}).map(\.trimmingTrailingSpaces) == expected)
        #expect(await row(group.onTapGesture {}).map(\.trimmingTrailingSpaces) == expected)
        #expect(await row(group.keyboardShortcut("k")).map(\.trimmingTrailingSpaces) == expected)
    }

    @Test("A GridRow carrying .onAppear is still a row of the grid")
    func onAppearGridRowKeepsTheLattice() async {
        let plain = await renderFrames(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc")
                    Text("dd")
                }
            }, frames: 1, context: makeContext())
        let modified = await renderFrames(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc")
                    Text("dd")
                }
                .onAppear {}
            }, frames: 1, context: makeContext())
        #expect(modified == plain)
    }

    // MARK: - Fired once

    @Test(".onAppear on a two-member Group fires once, over several frames")
    func onAppearOnGroupFiresOnce() async {
        let counter = Counter()
        await renderFrames(
            HStack {
                Group {
                    Text("A")
                    Text("B")
                }
                .onAppear { counter.bump() }
            }, frames: 3, context: makeContext())
        #expect(counter.value == 1)
    }

    @Test(".onAppear on a ForEach of three fires once")
    func onAppearOnForEachFiresOnce() async {
        let counter = Counter()
        await renderFrames(
            VStack {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
                    .onAppear { counter.bump() }
            }, frames: 3, context: makeContext())
        #expect(counter.value == 1)
    }

    @Test(".task on a two-member Group starts once")
    func taskOnGroupStartsOnce() async {
        let counter = Counter()
        await renderFrames(
            HStack {
                Group {
                    Text("A")
                    Text("B")
                }
                .task { counter.bump() }
            }, frames: 3, context: makeContext())
        #expect(counter.value == 1)
    }

    @Test(".onAppear on a GridRow fires once")
    func onAppearOnGridRowFiresOnce() async {
        let counter = Counter()
        await renderFrames(
            Grid {
                GridRow {
                    Text("a")
                    Text("b")
                }
                .onAppear { counter.bump() }
            }, frames: 3, context: makeContext())
        #expect(counter.value == 1)
    }

    @Test(".onChange on a Group runs once a change")
    func onChangeOnGroupRunsOnce() async {
        let counter = Counter()
        let context = makeContext()
        func frame(_ value: Int) async {
            await renderFrames(
                HStack {
                    Group {
                        Text("A")
                        Text("B")
                    }
                    .onChange(of: value) { counter.bump() }
                }, frames: 1, context: context)
        }
        await frame(1)
        await frame(1)
        #expect(counter.value == 0)
        await frame(2)
        #expect(counter.value == 1)
        await frame(2)
        await frame(3)
        #expect(counter.value == 2)
    }

    @Test(".onDisappear on a Group fires once when the Group leaves")
    func onDisappearOnGroupFiresOnce() async {
        let counter = Counter()
        let context = makeContext()
        func frame(_ shown: Bool) async {
            await renderFrames(
                HStack {
                    if shown {
                        Group {
                            Text("A")
                            Text("B")
                        }
                        .onDisappear { counter.bump() }
                    }
                }, frames: 1, context: context)
        }
        await frame(true)
        await frame(true)
        #expect(counter.value == 0)
        await frame(false)
        #expect(counter.value == 1)
    }

    @Test("An effect on content with no members still fires, and takes no cells")
    func effectOnMemberlessContentFires() async {
        let counter = Counter()
        let lines = await renderFrames(
            HStack(spacing: 1) {
                Text("A")
                ForEach([Int](), id: \.self) { Text("\($0)") }
                    .onAppear { counter.bump() }
                Text("B")
            }, frames: 2, context: makeContext())
        #expect(counter.value == 1)
        #expect(lines.first?.trimmingTrailingSpaces == "A B")
    }
}

extension String {
    fileprivate var trimmingTrailingSpaces: String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
