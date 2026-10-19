//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewShowsIndicatorsTests.swift
//
//  `ScrollView.showsIndicators`, SwiftUI's stored property (its initializer is
//  deprecated and absent): `false` hides what `.automatic` would show, a
//  stated visibility around the view wins, and a scroll view nested in the
//  content keeps its own indicators — the precedence measured on SwiftUI
//  (macOS 15, 2026-10-18).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("ScrollView.showsIndicators")
struct ScrollViewShowsIndicatorsTests {

    /// A viewport asking for the "N more lines" style, whose indicator is a
    /// line of words a test can look for.
    private func textCtx(width: Int = 24, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.scrollIndicatorStyle = .text
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func tallScrollView(showsIndicators: Bool) -> ScrollView<some View> {
        var view = ScrollView {
            VStack(alignment: .leading) {
                ForEach(0..<20) { Text("Line \($0)") }
            }
        }
        view.showsIndicators = showsIndicators
        return view
    }

    private func lines(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map(\.stripped)
    }

    @Test("It is true by default, and false hides the indicator automatic visibility would show")
    func falseHidesAutomatic() {
        #expect(ScrollView { Text("x") }.showsIndicators)
        let shown = lines(renderToBuffer(tallScrollView(showsIndicators: true), context: textCtx(height: 6)))
        #expect(shown[5].contains("lines below"), "sanity: \(shown)")
        let hidden = lines(renderToBuffer(tallScrollView(showsIndicators: false), context: textCtx(height: 6)))
        #expect(!hidden.joined().contains("lines below"), "\(hidden)")
        #expect(hidden[5].hasPrefix("Line 5"))
    }

    @Test("A stated visible around the view wins over false")
    func statedVisibleWins() {
        let buffer = renderToBuffer(
            tallScrollView(showsIndicators: false).scrollIndicators(.visible), context: textCtx(height: 6))
        #expect(lines(buffer)[5].contains("lines below"), "\(lines(buffer))")
    }

    @Test("A scroll view nested in the content keeps its own indicators")
    func nestedKeepsItsOwn() {
        var outer = ScrollView {
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(0..<20) { Text("Inner \($0)") }
                    }
                }
                .frame(height: 4)
                ForEach(0..<20) { Text("Outer \($0)") }
            }
        }
        outer.showsIndicators = false
        let drawn = lines(renderToBuffer(outer, context: textCtx(height: 10)))
        #expect(drawn[3].contains("lines below"), "the inner view's own indicator: \(drawn)")
        #expect(!drawn[9].contains("lines below"), "the outer view's is hidden: \(drawn)")
    }
}
