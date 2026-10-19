//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideThroughWrappersTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A guide travels out through a wrapper that draws its content unchanged —
/// `.onTapGesture`, an environment write — and is asked there in the context
/// the wrapper lays its content out in (`ContentContextStating`). A stack's
/// guide is worked out by measuring the stack's children, so a query that
/// stepped through an environment write in the context above it measured them
/// without the write, and the guide sat where nothing is drawn.
@MainActor
@Suite("alignmentGuide through wrappers that draw their content unchanged")
struct AlignmentGuideThroughWrappersTests {

    /// The column of the first `character` on the line holding it, and that
    /// line, in `buffer`.
    private func position(of character: Character, in buffer: FrameBuffer) -> (line: Int, column: Int)? {
        for (index, line) in buffer.lines.enumerated() {
            let stripped = line.stripped
            if let found = stripped.firstIndex(of: character) {
                return (index, stripped.distance(from: stripped.startIndex, to: found))
            }
        }
        return nil
    }

    @Test("A guide inside .onTapGesture places the stack around it")
    func guideThroughATapGesture() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text("x")
                HStack(spacing: 0) {
                    Text("ab")
                    Text("|").alignmentGuide(.leading) { _ in 0 }
                }
                .onTapGesture {}
            },
            context: makeRenderContext(width: 20, height: 4))

        #expect(position(of: "x", in: buffer)?.column == 2, "x over the bar, two cells in")
        #expect(position(of: "|", in: buffer)?.column == 2)
    }

    /// `.textCase(.uppercase)` writes the style cascade, and "ß" draws as
    /// "SS": the row's guide is four cells in, not the two the unwritten
    /// context measures.
    @Test("A guide inside a style write is found where the written content draws it")
    func guideThroughAStyleWrite() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text("x")
                HStack(spacing: 0) {
                    Text("ßß")
                    Text("|").alignmentGuide(.leading) { _ in 0 }
                }
                .textCase(.uppercase)
            },
            context: makeRenderContext(width: 20, height: 4))

        #expect(buffer.lines.contains { $0.stripped.contains("SSSS|") }, "the row drawn upper-cased")
        #expect(position(of: "|", in: buffer)?.column == 4)
        #expect(position(of: "x", in: buffer)?.column == 4, "x over the bar, where the row draws it")
    }

    /// `.lineLimit(1)` writes the environment, and the first row draws on one
    /// line where the unwritten context measures three: the column's guide is
    /// its second line, not its fourth.
    @Test("A guide inside an environment write is found where the written content draws it")
    func guideThroughAnEnvironmentWrite() {
        let buffer = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("A")
                VStack(alignment: .leading, spacing: 0) {
                    Text("a\nb\nc")
                    Text("B").alignmentGuide(.top) { _ in 0 }
                }
                .lineLimit(1)
            },
            context: makeRenderContext(width: 20, height: 6))

        let row = position(of: "B", in: buffer)?.line
        #expect(row == 1, "B under the column's one drawn line")
        #expect(position(of: "A", in: buffer)?.line == row, "A level with B, the column's guide")
    }
}
