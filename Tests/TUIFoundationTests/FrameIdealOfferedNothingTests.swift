//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameIdealOfferedNothingTests.swift
//
//  A frame with an ideal width, offered no width — under `.fixedSize()` — is
//  exactly that ideal, as SwiftUI's is; offered a width, its content's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A frame's ideal, offered nothing")
struct FrameIdealOfferedNothingTests {
    private let context = makeRenderContext(width: 80, height: 10)

    private func indent(_ line: String) -> Int {
        line.stripped.count - line.stripped.drop(while: { $0 == " " }).count
    }

    @Test("Offered nothing, a frame with an ideal width is the ideal, its content placed in it")
    func idealUnderFixedSize() {
        // SwiftUI: the frame is 10 wide, its 5-wide text at 2.5
        // (`Tools/SwiftUIProbes/Alignment guides/layout1.out`, case D2).
        let view = Text("short").frame(idealWidth: 10).fixedSize()
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.width == 10)
        #expect(indent(buffer.lines.first ?? "") == 2)
        #expect(measureChild(view, proposal: .unspecified, context: context).width == 10)
    }

    @Test("The ideal holds above a minimum and among siblings in a fixed row")
    func idealInAFixedRow() {
        #expect(renderToBuffer(Text("x").frame(minWidth: 3, idealWidth: 8).fixedSize(), context: context).width == 8)
        let row = HStack(spacing: 0) {
            Text("short").frame(idealWidth: 10)
            Text("abc")
        }
        .fixedSize()
        let buffer = renderToBuffer(row, context: context)
        // SwiftUI: the frame 10 wide, the next view at 10.
        #expect(buffer.width == 13)
        #expect(buffer.lines.first?.stripped.hasSuffix("abc") == true)
        #expect(measureChild(row, proposal: .unspecified, context: context).width == 13)
    }

    @Test("Offered a width, a frame with an ideal and no maximum is its content's width")
    func offeredAWidth() {
        // SwiftUI: `short ideal 10 [80]` is 5 (`Flexible frames/frame.out`).
        #expect(renderToBuffer(Text("short").frame(idealWidth: 10), context: context).width == 5)
        #expect(renderToBuffer(Text("short").frame(idealWidth: 10).frame(width: 30), context: context).width == 30)
    }

    /// A frame with an ideal width, its text drawn at its trailing edge.
    private var framed: some View { Text("abc").frame(idealWidth: 10, alignment: .trailing) }

    /// A line wider than the frame's ideal.
    private let long = "0123456789012345678901234"

    /// Measured on SwiftUI (`Tools/SwiftUIProbes/Flexible frames/ideal-placed.out`):
    /// under `.fixedSize()`, a column of several views, a `ZStack` of several,
    /// `VStackLayout`, a `Grid` and an overlay's layer offer the frame a width
    /// as they place it, so it is its content's width (the text at 0); a row,
    /// a column of one view, `HStackLayout` and a padding pass the unspecified
    /// width on, so it is its ideal (the text at 7). The flag reached the whole
    /// subtree, and the column's frame was drawn ten wide (found in review).
    @Test("Under .fixedSize(), a frame a column or a ZStack of several places is offered a width; a row passes none on")
    func placedUnderFixedSize() {
        func first(_ view: some View) -> Int { indent(renderToBuffer(view, context: context).lines.first ?? "") }
        let column = VStack(alignment: .leading, spacing: 0) { framed; Text(long) }.fixedSize()
        #expect(first(column) == 0)
        #expect(measureChild(column, proposal: .unspecified, context: context).width == 25)
        #expect(first(VStack(spacing: 0) { framed }.fixedSize()) == 7, "a column of one passes it on")
        #expect(first(ZStack(alignment: .leading) { framed; Color.clear.frame(width: 25, height: 1) }.fixedSize()) == 0)
        #expect(first(HStack(spacing: 0) { framed; Text("xyz") }.fixedSize()) == 7)
        let nested = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { framed; Text("xyz") }
            Text(long)
        }
        #expect(first(nested.fixedSize()) == 0, "a row in a column is offered a width")
        #expect(first(VStackLayout(alignment: .leading, spacing: 0) { framed; Text(long) }.fixedSize()) == 0)
        #expect(first(HStackLayout(spacing: 0) { framed; Text("xyz") }.fixedSize()) == 7)
        let overlaid = Color.clear.frame(width: 25, height: 1).overlay(alignment: .leading) { framed }.fixedSize()
        #expect(first(overlaid) == 0)
        #expect(first(framed.padding(.leading, 1).fixedSize()) == 8)
    }

    @Test("Down the column the ideal is not read: its content's height (deviations L16)")
    func idealHeightIsNotRead() {
        // SwiftUI: 3 rows (`layout1.out`, case D2). A stack asks every child
        // its natural height by offering none, so that ask is not SwiftUI's
        // unspecified proposal here.
        #expect(renderToBuffer(Text("x").frame(idealHeight: 3).fixedSize(), context: context).height == 1)
    }
}
