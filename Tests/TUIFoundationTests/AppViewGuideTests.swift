//  🖥️ TUI — A Terminal UI framework for Swift
//  AppViewGuideTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A custom guide the rows below line up on.
private enum AppViewDecimalPointID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { 0 }
}

extension HorizontalAlignment {
    fileprivate static let appViewDecimalPoint = Self(AppViewDecimalPointID.self)
}

/// A row of the app's own whose body is one view carrying a guide.
private struct GuidedRow: View {
    var body: some View {
        Text("ab").alignmentGuide(.leading) { _ in 3 }
    }
}

/// A row of the app's own whose decimal point is a custom guide set deep in
/// its body.
private struct AmountRow: View {
    let whole: String
    let fraction: String
    var body: some View {
        HStack(spacing: 0) {
            Text(whole)
            Text(fraction).alignmentGuide(.appViewDecimalPoint) { _ in 0 }
        }
    }
}

/// A view whose body holds its own type, and no guide anywhere.
private struct BareTree: View {
    let depth: Int
    var body: some View {
        if depth > 0 {
            Self(depth: depth - 1)
        }
    }
}

/// A view whose body holds its own type, with a guide at its leaf.
private struct GuidedTree: View {
    let depth: Int
    var body: some View {
        if depth > 0 {
            Self(depth: depth - 1)
        } else {
            Text("ab").alignmentGuide(.leading) { _ in 3 }
        }
    }
}

/// A view with its own type in both arms of an `if`/`else`: asked through the
/// type system alone, 2ⁿ questions before the stack ran out.
private struct Fork: View {
    let depth: Int
    var body: some View {
        if depth.isMultiple(of: 2) {
            Self(depth: depth - 1)
        } else {
            Self(depth: depth - 2)
        }
    }
}

/// Two views whose bodies hold each other, the guide in the first: asked
/// first, the first's question meets the second, whose own answer is worked
/// out while the first is still open.
private struct CycleFirst: View {
    let depth: Int
    var body: some View {
        VStack {
            if depth > 0 {
                CycleSecond(depth: depth)
            }
            Text("g").alignmentGuide(.leading) { _ in 1 }
        }
    }
}

/// See ``CycleFirst``.
private struct CycleSecond: View {
    let depth: Int
    var body: some View {
        if depth > 0 {
            CycleFirst(depth: depth - 1)
        }
    }
}

/// A guide inside a view type of the app's own travels out of it, as
/// SwiftUI's does: a container asks the view's body (decisions B19).
@MainActor
@Suite("Guides out of an app's own view types")
struct AppViewGuideTests {

    /// The leading edges of each line, which is what a guide moves.
    private func indents(_ buffer: FrameBuffer) -> [Int] {
        buffer.lines.map { line in
            let stripped = line.stripped
            return stripped.count - stripped.drop(while: { $0 == " " }).count
        }
    }

    @Test("A guide travels out of a view type of the app's own")
    func guideTravelsOutOfAnAppView() {
        // SwiftUI: a view of one's own passes every guide its body has, so
        // "x" moves three cells to meet the row's guide.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                GuidedRow()
                Text("x")
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(buffer) == [0, 3])
    }

    @Test("A custom guide set inside each row view lines the rows up on it")
    func decimalPointThroughAppRows() {
        let buffer = renderToBuffer(
            VStack(alignment: .appViewDecimalPoint) {
                AmountRow(whole: "12", fraction: ".5")
                AmountRow(whole: "1", fraction: ".25")
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(buffer.lines.map(\.stripped) == ["12.5 ", " 1.25"])
    }

    @Test("A view whose body holds its own type answers without asking itself again")
    func recursiveBodyWithNoGuide() {
        #expect(!BareTree._providesAlignmentGuide)
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                BareTree(depth: 3)
                Text("x")
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(buffer) == [0])
    }

    @Test("A guide at the leaf of a view whose body holds its own type travels out")
    func recursiveBodyWithAGuide() {
        #expect(GuidedTree._providesAlignmentGuide)
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                GuidedTree(depth: 3)
                Text("x")
            },
            context: makeRenderContext(width: 30, height: 4))
        #expect(indents(buffer) == [0, 3])
    }

    @Test("A view with its own type in both arms of an if/else is asked once")
    func ifElseOfItsOwnTypeIsAskedOnce() {
        let memo = BodyWitnessMemo.alignmentGuide
        let before = memo.pointee.bodiesAsked
        #expect(!Fork._providesAlignmentGuide)
        #expect(!Fork._providesAlignmentGuide)
        #expect(memo.pointee.bodiesAsked - before <= 1)
    }

    @Test("A type answered while another of its cycle was open is asked again on its own")
    func cycleMemberIsNotKeptFalse() {
        // Asked first, `CycleFirst` meets `CycleSecond`, whose body meets
        // `CycleFirst` again, still open: `false` there is exact for the
        // first, but not for the second, which reaches the guide through it.
        #expect(CycleFirst._providesAlignmentGuide)
        #expect(CycleSecond._providesAlignmentGuide)
    }
}
