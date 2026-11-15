//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollCanvasFitsContentTests.swift
//
//  SCROLL-FIT (design 2a, "the scroll view's canvas"; B-SCROLLFIT-7): a
//  vertical scroll view draws its content at the content's height, not at
//  the viewport's when the content is shorter, so a view that fills what it
//  is offered takes its minimum there, as SwiftUI's content is proposed no
//  height. A view that wants the viewport says so with
//  `.containerRelativeFrame(.vertical)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("SCROLL-FIT: a scroll view's content is its own height, and fillers in it take their minimum")
struct ScrollCanvasFitsContentTests {
    private static func app(@ViewBuilder _ content: () -> some View) -> TestApp {
        let content = content()
        return TestApp(width: 30, height: 12) {
            ScrollView { content }.environment(\.scrollFitsContent, true)
        }
    }

    @Test("A Spacer between two lines no longer pushes the second to the viewport's bottom")
    func spacerTakesItsMinimum() {
        let app = Self.app {
            VStack(alignment: .leading, spacing: 0) {
                Text("first")
                Spacer()
                Text("second")
            }
        }
        let second = app.screen.lines.firstIndex { $0.contains("second") }
        // The spacer's minimum in a stack of no spacing is nothing.
        #expect(second == 1, "\(app.screen)")
    }

    @Test("A Color, a shape and a GeometryReader under a title take no lines")
    func fillersTakeNothing() {
        for (name, filler) in [
            ("color", AnyView(Color.blue)), ("rectangle", AnyView(Rectangle())),
            ("reader", AnyView(GeometryReader { _ in Text("inside") })),
            ("max height", AnyView(Text("tall").frame(maxHeight: .infinity))),
        ] {
            let app = Self.app {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    filler
                    Text("after")
                }
            }
            let after = app.screen.lines.firstIndex { $0.contains("after") }
            // A frame of an unbounded height is its text's height.
            #expect(after == (name == "max height" ? 2 : 1), "\(name):\n\(app.screen)")
        }
    }

    @Test("containerRelativeFrame(.vertical) still makes a view the viewport's height")
    func containerRelativeFrameReadsTheViewport() {
        let app = Self.app {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.containerRelativeFrame(.vertical)
                Text("below the fold")
            }
        }
        #expect(!app.screen.contains("below the fold"), "\(app.screen)")
        app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5))
        #expect(app.screen.contains("below the fold"), "\(app.screen)")
    }

    @Test("A resizable image alone is its ideal height, not the viewport's")
    func resizableImageIsItsIdealHeight() throws {
        let picture = try #require(ScrollFitCatalogue.picture)
        let result = ScrollFitMeasure.measure(.imageResizable, .alone, rows: 3, walk: false, fitsContent: true)
        #expect(result.sizeA == CellSize(width: 60, height: 15), "\(result) \(picture.path)")
    }
}
