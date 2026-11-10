//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlaidBarHoverTests.swift
//
//  A scrollbar drawn over the content for the pointer (`.overContent`, the
//  default) arrives on the frame after the pointer comes over the view, under
//  a pointer that has not moved since. The arrow under it lights on that
//  arrival, as it does when the pointer moves onto it: the bar's handler is
//  entered as the reshape slides it under the pointer, and the frame that
//  draws what it lit is asked for then, not at the pointer's next move.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("An overlaid scrollbar lights the arrow it arrives under")
struct OverlaidBarHoverTests {
    /// A focused button above, so the scroll view rests unfocused and its bar
    /// is drawn over the content only while the pointer is over it.
    private struct Page: View {
        var body: some View {
            VStack(spacing: 0) {
                Button("top") {}
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<30, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 20, height: 6)
            }
        }
    }

    /// The cells of the bar's arrows: the scroll view's last column, on its
    /// first line and its last.
    @Test(
        "The arrow under the pointer is lit on the frame the bar arrives under it",
        arguments: [CellPoint(x: 19, y: 1), CellPoint(x: 19, y: 6)])
    func arrowLitAsTheBarArrives(_ arrow: CellPoint) {
        ColorDepth.withCurrent(.truecolor) {
            let app = TestApp(width: 30, height: 12) { Page() }
            app.frame(atNanos: 16_666_667)
            #expect(!app.screen.text.contains("▲"), "the bar is drawn before the pointer came:\n\(app.screen)")
            // The pointer comes over the view straight onto the arrow's cell;
            // the bar is drawn in the frame that answers it.
            app.hover(at: arrow)
            let arrived = app.screen.styledLines[arrow.y]
            #expect(app.screen.lines[arrow.y].contains { "▲▼".contains($0) }, "no bar:\n\(app.screen)")
            // The same cell again: a move within the bar's region, which is
            // what lit the arrow before.
            app.hover(at: arrow)
            let moved = app.screen.styledLines[arrow.y]
            // The pointer elsewhere over the view: the bar stays, its arrow not lit.
            app.hover(at: CellPoint(x: 2, y: 3))
            let away = app.screen.styledLines[arrow.y]
            #expect(away != moved, "the arrow is not lit even under the pointer: \(moved.debugDescription)")
            #expect(
                arrived == moved,
                "the arrow lit only at the next move:\n\(arrived.debugDescription)\n\(moved.debugDescription)")
        }
    }
}
