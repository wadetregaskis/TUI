//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameIdealOfferedNothingTests.swift
//
//  A frame with an ideal width, offered no width — under `.fixedSize()` — is
//  exactly that ideal, as SwiftUI's is; offered a width, its content's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

    @Test("Down the column the ideal is not read: its content's height (deviations L16)")
    func idealHeightIsNotRead() {
        // SwiftUI: 3 rows (`layout1.out`, case D2). A stack asks every child
        // its natural height by offering none, so that ask is not SwiftUI's
        // unspecified proposal here.
        #expect(renderToBuffer(Text("x").frame(idealHeight: 3).fixedSize(), context: context).height == 1)
    }
}
