//  🖥️ TUI — A Terminal UI framework for Swift
//  NegativePaddingTests.swift
//
//  A negative `padding` as SwiftUI's (owner, 2026-10-29, NEG-PADDING): the
//  frame is pulled in over the content by the inset on each edge, the content
//  is offered as many cells more, and it is drawn at its full size past the
//  frame, at its view's place in the stacking order — over the views before
//  it, under the views after it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIChrome
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Negative padding")
struct NegativePaddingTests {

    private func composited(_ view: some View, width: Int = 20, height: Int = 6) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .compositingOverlays(maxWidth: width, maxHeight: height, palette: SystemPalette.green)
            .lines.map { $0.stripped }
    }

    private func size(_ view: some View, width: Int = 20, height: Int = 6) -> ViewSize {
        measureChild(
            view, proposal: ProposedSize(width: width, height: height),
            context: makeRenderContext(width: width, height: height))
    }

    /// What is measured is what is drawn: the render's buffer, before its
    /// overflow is composited, is the size the measure reported.
    private func expectParity(_ view: some View, width: Int = 20, height: Int = 6) {
        let measured = size(view, width: width, height: height)
        let drawn = renderToBuffer(view, context: makeRenderContext(width: width, height: height))
        #expect(drawn.width == measured.width, "drawn \(drawn.width) wide, measured \(measured.width)")
        #expect(drawn.height == measured.height, "drawn \(drawn.height) tall, measured \(measured.height)")
    }

    @Test("A negative padding reports the frame that much smaller on each edge")
    func reportsSmallerFrame() {
        let column = VStack(alignment: .leading, spacing: 0) {
            Text("Hello")
            Text("World")
            Text("Again")
        }
        let measured = size(column.padding(-1))
        #expect(measured.width == 3)
        #expect(measured.height == 1)
        expectParity(column.padding(-1))
        expectParity(Text("Hello").padding(.horizontal, -1))
    }

    @Test("The content still draws in full, overhanging its frame by the inset")
    func contentDrawsInFull() {
        let out = composited(
            VStack(alignment: .leading, spacing: 0) {
                Text("Hello").padding(.horizontal, -1)
            }.padding(.leading, 2))
        // The frame is three cells from column 2; the text starts a cell
        // before it.
        #expect(out.first?.hasPrefix(" Hello") == true, "\(out)")
    }

    @Test("In an HStack the neighbours sit closer by the overhang, the earlier one drawn over")
    func overlapsInHStack() {
        let row = HStack(spacing: 0) {
            Text("AAAA")
            Text("Hello").padding(.horizontal, -1)
            Text("BBBB")
        }
        #expect(size(row).width == 11)
        expectParity(row)
        let out = composited(row)
        // The text's frame is columns 4..<7 and it draws from column 3: over
        // the "A" before it, and under the "B" after it, which covers its "o".
        #expect(out.first?.hasPrefix("AAAHellBBBB") == true, "\(out)")
    }

    @Test("In a VStack a frame pulled to no rows keeps its place, its content drawn over the row before")
    func overlapsInVStack() {
        let column = VStack(alignment: .leading, spacing: 0) {
            Text("top")
            Text("mid").padding(.vertical, -1)
            Text("bot")
        }
        #expect(size(column).height == 2)
        expectParity(column)
        let out = composited(column)
        #expect(out.count >= 2, "\(out)")
        #expect(out[0].hasPrefix("mid"), "drawn a row up, over the row before it: \(out)")
        #expect(out[1].hasPrefix("bot"), "the row after it moved up by the overhang: \(out)")
    }

    @Test("A negative inset on one edge moves the content only on that edge")
    func singleEdge() {
        let leading = HStack(spacing: 0) {
            Text("XXXX")
            Text("Hello").padding(.leading, -2)
        }
        #expect(size(leading).width == 7)
        expectParity(leading)
        #expect(composited(leading).first?.hasPrefix("XXHello") == true, "\(composited(leading))")

        let trailing = HStack(spacing: 0) {
            Text("Hello").padding(.trailing, -2)
            Text("YY")
        }
        #expect(size(trailing).width == 5)
        expectParity(trailing)
        #expect(composited(trailing).first?.hasPrefix("HelYY") == true, "\(composited(trailing))")
    }

    @Test("Positive and negative insets mix, each on its own edge")
    func mixedSigns() {
        let row = HStack(spacing: 0) {
            Text("Hello").padding(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: -1))
            Text("Z")
        }
        #expect(size(row).width == 7)
        expectParity(row)
        #expect(composited(row).first?.hasPrefix("  HellZ") == true, "\(composited(row))")

        // The cell positive padding always leaves its content is counted from
        // the space before the frame is pulled in: counted from the frame, the
        // text measured two cells and drew none.
        let cancelling = HStack(spacing: 0) {
            Text("Hi").padding(EdgeInsets(top: 0, leading: 3, bottom: 0, trailing: -3))
            Text("Z")
        }
        #expect(size(cancelling).width == 3)
        expectParity(cancelling)
        // The frame is the two blank cells of the leading inset; the text is
        // drawn past it, beyond the "Z" laid out after it.
        #expect(composited(cancelling).first?.hasPrefix("  ZHi") == true, "\(composited(cancelling))")
    }

    @Test("A negative inset grows the proposal the content is offered")
    func growsTheProposal() {
        // Offered 7 columns, the text is offered 11 and fits on one line.
        let padded = Text("Hello world").padding(.horizontal, -2)
        let measured = size(padded, width: 7)
        #expect(measured.width == 7)
        #expect(measured.height == 1)
        expectParity(padded, width: 7)
    }

    @Test("A padding more negative than the content reports zero, and still draws")
    func zeroSizeResult() {
        let padded = Text("Hi").padding(-5)
        let measured = size(padded)
        #expect(measured.width == 0)
        #expect(measured.height == 0)
        let row = HStack(spacing: 0) {
            Text("AB")
            padded
            Text("CD")
        }
        #expect(size(row).width == 4)
        expectParity(row)
        _ = composited(row)
    }
}
