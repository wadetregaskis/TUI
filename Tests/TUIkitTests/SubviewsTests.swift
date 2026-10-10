//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SubviewsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// MARK: - Fixtures

/// What a transform was handed, kept for the test to read.
@MainActor
private final class Captured {
    var count = -1
    var ids: [Subview.ID] = []
    var tags: [Int?] = []
    var sliceStart = -1
}

/// The identity each probe rendered at, by name.
@MainActor
private final class IdentityLog {
    var paths: [String: [String]] = [:]
}

/// Draws its name, and records the identity it drew at.
private struct Probe: View, Renderable {
    let name: String
    let log: IdentityLog

    var body: Never { fatalError("Probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        log.paths[name, default: []].append(context.identity.path)
        return FrameBuffer(text: name)
    }
}

/// Counts how many rows a loop built.
@MainActor
private final class BuildCount {
    var rows = 0
}

private struct Named: Identifiable, Equatable {
    let id: String
}

// MARK: - Suite

/// `Group(subviews:transform:)`, `Subview` and `SubviewsCollection`, against the
/// counts and behaviours measured on SwiftUI (W05 probes B, s and t).
@MainActor
@Suite("Subviews")
struct SubviewsTests {

    private func render(_ view: some View, width: Int = 40, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    /// How many subviews `content` has.
    private func count(@ViewBuilder _ content: () -> some View) -> Int {
        let captured = Captured()
        _ = render(
            Group(subviews: content()) { subviews -> EmptyView in
                captured.count = subviews.count
                return EmptyView()
            })
        return captured.count
    }

    // MARK: - What counts as a subview

    @Test("Two views are two subviews")
    func twoViews() {
        #expect(count { Text("a"); Text("b") } == 2)
    }

    @Test("A ForEach contributes one subview per row")
    func forEachRows() {
        #expect(
            count {
                ForEach(0..<3) { Text("\($0)") }
                Text("x")
            } == 4)
    }

    @Test("A Group is its members; a stack is one subview")
    func groupFlattensStackDoesNot() {
        #expect(count { Group { Text("a"); Text("b") } } == 2)
        #expect(count { VStack { Text("a"); Text("b") } } == 1)
    }

    @Test("A false condition and an EmptyView are no subviews")
    func emptiesAreNothing() {
        #expect(
            count {
                if true { Text("a") }
                if false { Text("b") }
                EmptyView()
            } == 1)
    }

    @Test("A Section is its header's, content's and footer's members")
    func sectionFlattens() {
        #expect(
            count {
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("H")
                } footer: {
                    Text("f")
                }
            } == 4)
    }

    @Test("A nested Group(subviews:) result is flattened again")
    func nestedResultFlattens() {
        let inner = Group(subviews: Group { Text("a"); Text("b") }) { subviews in
            subviews
            Text("c")
        }
        #expect(count { inner } == 3)
    }

    // MARK: - Drawing

    @Test("In a stack, the transform's views are the stack's children")
    func membersLayOutInTheContainer() {
        let lines = render(
            HStack(spacing: 1) {
                Group(subviews: Group { Text("a"); Text("b") }) { subviews in
                    subviews
                }
            })
        #expect(lines == ["a b"])
    }

    @Test("Alone, the members stack vertically")
    func aloneStacksVertically() {
        let lines = render(
            Group(subviews: Group { Text("a"); Text("b") }) { subviews in
                subviews
            })
        #expect(lines == ["a", "b"])
    }

    @Test("A slice keeps the parent's indices and contributes its members")
    func sliceKeepsIndices() {
        let captured = Captured()
        let lines = render(
            HStack(spacing: 1) {
                Group(subviews: Group { Text("a"); Text("b"); Text("c") }) { subviews in
                    captured.sliceStart = subviews[1...].startIndex
                    return subviews[1...]
                }
            })
        #expect(captured.sliceStart == 1)
        #expect(lines == ["b c"])
    }

    @Test("A subview placed twice is drawn twice")
    func placedTwice() {
        let lines = render(
            HStack(spacing: 1) {
                Group(subviews: Text("x")) { subviews in
                    subviews[0]
                    subviews[0]
                }
            })
        #expect(lines == ["x x"])
    }

    @Test("A modifier on the proxy applies, and the view's own wins over it")
    func proxyModifiers() {
        let red = "\u{1B}[" + Color.red.foregroundCodes().joined(separator: ";") + "m"
        let blue = "\u{1B}[" + Color.blue.foregroundCodes().joined(separator: ";") + "m"
        let buffer = renderToBuffer(
            Group(subviews: Group { Text("plain"); Text("own").foregroundStyle(.blue) }) { subviews in
                ForEach(subviews) { subview in
                    subview.foregroundStyle(.red)
                }
            },
            context: makeRenderContext(width: 40, height: 4))
        #expect(buffer.lines[0].contains(red))
        #expect(buffer.lines[1].contains(blue))
        #expect(!buffer.lines[1].contains(red))
    }

    // MARK: - Identity

    @Test("Members and the transform's own views never share an identity")
    func identityNamespaces() {
        let log = IdentityLog()
        _ = render(
            VStack {
                Group(subviews: Probe(name: "member", log: log)) { subviews in
                    Probe(name: "built", log: log)
                    subviews
                }
            })
        let member = log.paths["member"] ?? []
        let built = log.paths["built"] ?? []
        #expect(!member.isEmpty && !built.isEmpty)
        #expect(Set(member).isDisjoint(with: built))
    }

    @Test("A subview draws at one identity wherever it is placed")
    func identityIsPinned() {
        let log = IdentityLog()
        _ = render(
            VStack {
                Group(subviews: Probe(name: "member", log: log)) { subviews in
                    HStack { subviews[0] }
                    VStack { Text("pad"); subviews[0] }
                }
            })
        #expect(Set(log.paths["member"] ?? []).count == 1)
    }

    @Test("A subview's id follows its element across a reorder")
    func idFollowsElement() {
        func ids(_ items: [Named]) -> [String: Subview.ID] {
            let captured = Captured()
            _ = render(
                Group(subviews: ForEach(items) { Text($0.id) }) { subviews -> EmptyView in
                    captured.ids = subviews.map(\.id)
                    return EmptyView()
                })
            return Dictionary(uniqueKeysWithValues: zip(items.map(\.id), captured.ids))
        }
        let forward = ids([Named(id: "a"), Named(id: "b"), Named(id: "c")])
        let backward = ids([Named(id: "c"), Named(id: "b"), Named(id: "a")])
        #expect(forward == backward)
        #expect(Set(forward.values).count == 3)
    }

    // MARK: - Container values and laziness

    @Test("A subview reads its container values, and a ForEach row its element's id")
    func containerValues() {
        let captured = Captured()
        _ = render(
            Group(
                subviews: Group {
                    Text("a").tag(5).padding()
                    ForEach([7, 8], id: \.self) { Text("\($0)") }
                }
            ) { subviews -> EmptyView in
                captured.tags = subviews.map { $0.containerValues.tag(for: Int.self) }
                return EmptyView()
            })
        #expect(captured.tags == [5, 7, 8])
    }

    @Test("A lone loop's count and ids build no row")
    func loneLoopIsLazy() {
        let built = BuildCount()
        let captured = Captured()
        _ = render(
            Group(
                subviews: ForEach(0..<1000) { index -> Text in
                    built.rows += 1
                    return Text("\(index)")
                }
            ) { subviews -> EmptyView in
                captured.count = subviews.count
                captured.tags = [subviews[500].containerValues.tag(for: Int.self)]
                return EmptyView()
            })
        #expect(captured.count == 1000)
        #expect(captured.tags == [500])
        #expect(built.rows == 0)
    }

    @Test("The value hash bypasses a subview, and reads the types around it")
    func valueHashPlans() {
        // A `Subview` holds a `ChildView`, whose `Any.Type?` the value hash
        // cannot read safely: a subtree holding one is measured afresh rather
        // than served from the per-pass memos — slower, never wrong. The
        // wrappers and layouts this wave added hold nothing of the kind, so
        // they must not bypass too.
        let plans = ValueHashPlans()
        #expect(plans.plan(for: Subview.self).pointee.shape == .bypass)
        #expect(plans.plan(for: _ContainerValueView<Text>.self).pointee.shape != .bypass)
        #expect(plans.plan(for: GroupElementsOfContent<Text, Text>.self).pointee.shape != .bypass)
        #expect(plans.plan(for: GridLayout.self).pointee.shape != .bypass)
        #expect(plans.plan(for: ViewSpacing.self).pointee.shape != .bypass)
    }

    @Test("The sizing options are plain values")
    func sizingOptions() {
        let uniform = Subview.ContainerSizingOptions.uniform(axis: .horizontal)
        #expect(uniform != .variable)
        #expect(uniform == .uniform(axis: .horizontal))
    }
}
