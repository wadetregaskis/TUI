//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EmptyContentLayoutTests.swift
//
//  What a stack gives content with nothing in it: a frame on a `nil`, on an
//  empty `Group`, on `EmptyView`, and an empty stack between two siblings.
//  SwiftUI's answers were measured with an `NSHostingView` probe and are
//  recorded in `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §3, beside the
//  place TUIkit answers differently (an empty stack's spacing).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// The rows `view` draws, styling stripped, between an `A` and a `B`.
@MainActor
private func rows<V: View>(between view: V, spacing: Int) -> [String] {
    let context = makeRenderContext(width: 8, height: 12)
    let stack = VStack(alignment: .leading, spacing: spacing) {
        Text("A")
        view
        Text("B")
    }
    return renderToBuffer(stack, context: context).lines.map {
        $0.stripped.trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
@Suite("Content with nothing in it, in a stack")
struct EmptyContentLayoutTests {
    private let absent: Text? = nil
    private let never = false

    /// SwiftUI: 32 points for the two texts, and 32 again with each of these.
    @Test("A frame on a nil or an empty Group keeps no rows, as in SwiftUI")
    func frameOnNothingKeepsNoRows() {
        #expect(rows(between: absent.frame(height: 5), spacing: 0) == ["A", "B"])
        #expect(
            rows(between: Group { if never { Text("x") } }.frame(height: 5), spacing: 0)
                == ["A", "B"])
    }

    /// SwiftUI: 82 points — the 32 and the frame's 50.
    @Test("A frame on a stack that is always there keeps its rows, as in SwiftUI")
    func frameOnAStackKeepsItsRows() {
        let slot = VStack(spacing: 0) { if never { Text("x") } }.frame(height: 5)
        #expect(rows(between: slot, spacing: 0) == ["A", "", "", "", "", "", "B"])
    }

    /// SwiftUI: 32 — a frame on `EmptyView` is as empty as one on a `nil`
    /// (measured again 2026-10-18, `Tools/SwiftUIProbes/Alignment
    /// guides/layout1.out`, case D). `EmptyView` is content with no members,
    /// so the frame, which reaches each member, has none to reach.
    @Test("A frame on EmptyView keeps no rows, as in SwiftUI")
    func frameOnEmptyViewKeepsNoRows() {
        #expect(rows(between: EmptyView().frame(height: 5), spacing: 0) == ["A", "B"])
        #expect(rows(between: Group { EmptyView() }.frame(height: 5), spacing: 0) == ["A", "B"])
        #expect(rows(between: EmptyView().id(1).frame(height: 5), spacing: 0) == ["A", "B"])
    }

    /// SwiftUI: 32 — `EmptyView().padding(20)` adds nothing either.
    @Test("A padding on EmptyView keeps no rows, as in SwiftUI")
    func paddingOnEmptyViewKeepsNoRows() {
        #expect(rows(between: EmptyView().padding(2), spacing: 0) == ["A", "B"])
        #expect(rows(between: EmptyView().padding(2), spacing: 1) == ["A", "", "B"])
    }

    /// SwiftUI: 32, and the overlay or background is not drawn at all.
    @Test("An overlay or a background on EmptyView draws nothing and keeps no rows, as in SwiftUI")
    func layerOnEmptyViewDrawsNothing() {
        #expect(rows(between: EmptyView().overlay { Text("x") }, spacing: 0) == ["A", "B"])
        #expect(rows(between: EmptyView().background { Text("x") }, spacing: 0) == ["A", "B"])
    }

    /// SwiftUI: the two boxes touch — a frame's width on `EmptyView` is none.
    @Test("A frame on EmptyView in a row takes no columns")
    func frameOnEmptyViewInARow() {
        let row = HStack(spacing: 0) {
            Text("A")
            EmptyView().frame(width: 5)
            Text("B")
        }
        #expect(renderToBuffer(row, context: makeRenderContext(width: 12, height: 2)).lines.first?.stripped == "AB")
    }

    /// A view of the app's own whose body is an `EmptyView` is that body:
    /// nothing.
    @Test("A view whose body is an EmptyView keeps no rows")
    func appViewOfEmptyViewKeepsNoRows() {
        struct Nothing: View {
            var body: some View { EmptyView() }
        }
        #expect(rows(between: Nothing(), spacing: 0) == ["A", "B"])
    }

    /// What a stack of it measures is what it draws. On its own, not in a
    /// container — a sheet's whole content, say — a padded `EmptyView` is
    /// still padding round a view that draws nothing.
    @Test("A padding on EmptyView draws what it measures")
    func paddingOnEmptyViewDrawsWhatItMeasures() {
        let context = makeRenderContext(width: 8, height: 12)
        let stack = VStack(alignment: .leading, spacing: 0) {
            Text("A")
            EmptyView().padding(2)
            Text("B")
        }
        let measured = measureChild(stack, proposal: ProposedSize(width: 8, height: nil), context: context)
        let drawn = renderToBuffer(stack, context: context)
        #expect(measured.height == 2)
        #expect(drawn.height == measured.height, "measured \(measured.height) rows, drew \(drawn.height)")
        #expect(renderToBuffer(EmptyView().padding(2), context: context).width == 4)
    }

    /// SwiftUI: 52 points against 42 — the empty stack is a child, and has the
    /// stack's 10 points on each side of it. TUIkit charges spacing only
    /// between children that take a row (or are spacers), so an empty stack
    /// changes nothing, as a `nil` changes nothing in both.
    @Test("An empty stack takes no spacing, where SwiftUI's takes it on both sides")
    func emptyStackTakesNoSpacing() {
        #expect(rows(between: VStack(spacing: 0) { if never { Text("x") } }, spacing: 1) == ["A", "", "B"])
        #expect(rows(between: absent, spacing: 1) == ["A", "", "B"])
    }
}
