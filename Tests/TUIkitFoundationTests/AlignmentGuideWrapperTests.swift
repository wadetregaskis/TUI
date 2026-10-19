//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideWrapperTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// `G`, a one-cell view whose leading guide is five cells in.
@MainActor
private func leadingFive() -> some View {
    Text("G").alignmentGuide(.leading) { _ in 5 }
}

/// `G`, a one-row view whose top guide is five rows down.
@MainActor
private func topFive() -> some View {
    Text("G").alignmentGuide(.top) { _ in 5 }
}

/// A guide passes out through a single-child wrapper written after it, moved
/// by where the wrapper puts its content, as SwiftUI's does (decisions SA-L11;
/// SwiftUI measured in `Tools/SwiftUIProbes/Alignment guides/layout1.out`,
/// case B, whose figures each test quotes — points there, cells here, a
/// fraction floored where TUIkit places by whole cells).
@MainActor
@Suite("Guides through single-child wrappers")
struct AlignmentGuideWrapperTests {

    /// Where the six-cell `C` beside `inner` in a leading-aligned column
    /// starts: the leading guide `inner` reports, or 0 when it reports none.
    private func leadingReported(_ inner: some View) -> Int {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                inner
                Text("CCCCCC")
            },
            context: makeRenderContext(width: 60, height: 10))
        let line = buffer.lines.last?.stripped ?? ""
        return line.count - line.drop(while: { $0 == " " }).count
    }

    /// The row the six-row column `C` beside `inner` in a top-aligned row
    /// starts on: the top guide `inner` reports, or 0 when it reports none.
    private func topReported(_ inner: some View) -> Int {
        let column = VStack(spacing: 0) { ForEach(0..<6, id: \.self) { _ in Text("C") } }
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 0) {
                inner
                column
            },
            context: makeRenderContext(width: 60, height: 20))
        return buffer.lines.firstIndex { $0.stripped.hasSuffix("C") } ?? -1
    }

    @Test("A frame reports its content's guide where it placed the content")
    func frameTranslatesByItsPlacement() {
        // SwiftUI: 0 (G at −5), 9.25, 14, 14.
        #expect(leadingReported(leadingFive().frame(width: 10, alignment: .leading)) == 0)
        #expect(leadingReported(leadingFive().frame(width: 10, alignment: .center)) == 9)
        #expect(leadingReported(leadingFive().frame(width: 10, alignment: .trailing)) == 14)
        #expect(leadingReported(leadingFive().frame(width: 10, height: 3, alignment: .bottomTrailing)) == 14)
        // SwiftUI: 9.25 for a flexible frame's minimum, 24 through two frames
        // (SwiftUI's outer frame centres by default; TUIkit's fixed frame
        // aligns top-leading, deviation L1, so the test says `.center`).
        #expect(leadingReported(leadingFive().frame(minWidth: 10, alignment: .center)) == 9)
        #expect(
            leadingReported(
                leadingFive().frame(maxWidth: .infinity, alignment: .trailing).frame(width: 20, alignment: .center))
                == 24)
    }

    @Test("A frame reports a top guide where it placed the content down the column")
    func frameTranslatesDown() {
        // SwiftUI: 5 alone, then 0 (G at −5), 6.25 and 8 in a four-row frame.
        #expect(topReported(topFive()) == 5)
        #expect(topReported(topFive().frame(height: 4, alignment: .top)) == 0)
        #expect(topReported(topFive().frame(height: 4, alignment: .center)) == 6)
        #expect(topReported(topFive().frame(height: 4, alignment: .bottom)) == 8)
    }

    @Test("An offset reports its content's guide from where it is laid out, not drawn")
    func offsetPassesItsContentsGuide() {
        // SwiftUI: 5 and 5.
        #expect(leadingReported(leadingFive().offset(x: 3)) == 5)
        #expect(topReported(topFive().offset(y: 2)) == 5)
    }

    @Test("A position reports its content's guide from where it placed the content")
    func positionTranslatesByItsPlacement() {
        // SwiftUI: 7.25, its one-point view centred on x = 3 at 2.5; here the
        // view is a whole cell at 3. The frame centres, as SwiftUI's does by
        // default (TUIkit's aligns top-leading, deviation L1).
        #expect(
            leadingReported(leadingFive().position(x: 3, y: 0).frame(width: 10, height: 2, alignment: .center)) == 8)
    }

    @Test("A border reports its content's guide moved in by its rings")
    func borderTranslatesByItsRings() {
        // SwiftUI strokes inside the view and reports 5; a terminal border
        // takes a line and a blank cell each side across, a line down.
        #expect(leadingReported(leadingFive().border()) == 7)
        #expect(leadingReported(leadingFive().border(width: 2)) == 9)
        #expect(topReported(topFive().border()) == 6)
    }

    @Test("A guide passes the wrappers that keep their content's place and size")
    func sizeNeutralWrappersPassTheGuide() {
        // SwiftUI: 5 through each.
        #expect(leadingReported(leadingFive().overlay { Text("OOOOOOOOOO") }) == 5)
        #expect(leadingReported(leadingFive().background { Text("OOOOOOOOOO") }) == 5)
        #expect(leadingReported(leadingFive().foregroundStyle(.red)) == 5)
        #expect(leadingReported(leadingFive().id(1)) == 5)
        #expect(leadingReported(leadingFive().onAppear {}) == 5)
        #expect(leadingReported(leadingFive().fixedSize()) == 5)
        #expect(leadingReported(leadingFive().opacity(0.5)) == 5)
        #expect(leadingReported(leadingFive().disabled(true)) == 5)
        // SwiftUI: 7 through a leading padding of 2.
        #expect(leadingReported(leadingFive().padding(.leading, 2)) == 7)
    }

    /// A wrapper's content is asked for its guide laid out as the wrapper
    /// lays it out: `.textCase(.uppercase)` draws "ßß" as "SSSS", four cells,
    /// and the guide on the "X" after it is four cells in. Asked without the
    /// wrapper's style, the row was laid out two cells wide and the bar below
    /// put at 2, under nothing (found in review).
    @Test("A guide through a wrapper is placed in the content as the wrapper lays it out")
    func guideThroughAWrapperUsesItsContext() {
        let buffer = renderToBuffer(
            VStack(alignment: .wrapperProbeMark, spacing: 0) {
                HStack(spacing: 0) {
                    Text("ßß")
                    Text("x").alignmentGuide(.wrapperProbeMark) { $0[.leading] }
                }
                .textCase(.uppercase)
                Text("|").alignmentGuide(.wrapperProbeMark) { $0[.leading] }
            },
            context: makeRenderContext(width: 20, height: 4))
        #expect(buffer.lines.prefix(2).map { $0.stripped.prefix(5) } == ["SSSSX", "    |"])
    }

    /// A wrapper that keeps its content's geometry but has not said what
    /// context it lays its content out in stops a guide: one placed from a
    /// layout that is never drawn is worse than none.
    @Test("A guide stops at a wrapper that has not said what context it gives its content")
    func unsaidWrapperStopsTheGuide() {
        #expect(leadingReported(UnsaidWrapper(content: leadingFive())) == 0)
    }
}

/// A custom guide the wrapper tests line rows up on.
private enum WrapperProbeMark: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Double { context[.leading] }
}

extension HorizontalAlignment {
    fileprivate static let wrapperProbeMark = Self(WrapperProbeMark.self)
}

/// A wrapper that draws its content unchanged and says nothing of the context
/// it gives it.
private struct UnsaidWrapper<Content: View>: View, SingleContentWrapper, DrawsContentUnchanged {
    let content: Content
    var body: some View { content }
    var wrappedContent: Content { content }
}
