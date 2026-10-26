//  🖥️ TUI — A Terminal UI framework for Swift
//  SafeAreaInsetTests.swift
//
//  `safeAreaInset(edge:alignment:spacing:content:)` and `safeAreaBar`, against
//  SwiftUI's measured layout: the bar beside the view, no spacing by default,
//  the bar across the full extent and placed by `alignment`, the view proposed
//  what is left, and two bars stacking outward.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("safeAreaInset")
struct SafeAreaInsetTests {
    private func lines<V: View>(_ view: V, width: Int = 10, height: Int = 6) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
    }

    @Test("A bottom bar sits below the view, with no spacing by default")
    func bottomBar() {
        #expect(lines(Text("A").safeAreaInset(edge: .bottom) { Text("B") }) == ["A", "B"])
        #expect(lines(Text("A").safeAreaInset(edge: .bottom, spacing: 1) { Text("B") }) == ["A", " ", "B"])
        #expect(lines(Text("A").safeAreaBar(edge: .bottom) { Text("B") }) == ["A", "B"])
    }

    @Test("A top bar sits above it")
    func topBar() {
        #expect(lines(Text("A").safeAreaInset(edge: .top) { Text("B") }) == ["B", "A"])
    }

    @Test("A bar wider than the view sets the width, and the view is centred")
    func wideBar() {
        #expect(lines(Text("A").safeAreaInset(edge: .bottom) { Text("BBB") }) == [" A ", "BBB"])
    }

    @Test("Alignment places the bar across the view")
    func alignment() {
        #expect(lines(Text("AAAA").safeAreaInset(edge: .bottom, alignment: .leading) { Text("B") })
            == ["AAAA", "B   "])
        #expect(lines(Text("AAAA").safeAreaInset(edge: .bottom, alignment: .trailing) { Text("B") })
            == ["AAAA", "   B"])
    }

    @Test("Leading and trailing bars sit beside the view")
    func sideBars() {
        #expect(lines(Text("A").safeAreaInset(edge: .leading) { Text("B") }) == ["BA"])
        #expect(lines(Text("A").safeAreaInset(edge: .trailing, spacing: 1) { Text("B") }) == ["A B"])
    }

    @Test("Two bars on one edge stack outward")
    func twoBars() {
        let view = Text("A")
            .safeAreaInset(edge: .bottom) { Text("B") }
            .safeAreaInset(edge: .bottom) { Text("C") }
        #expect(lines(view) == ["A", "B", "C"])
    }

    @Test("The view is proposed what the bar leaves, and the two fill the space")
    func viewGetsTheRemainder() {
        let drawn = lines(VStack(spacing: 0) { Text("x"); Spacer() }.safeAreaInset(edge: .bottom) { Text("bar") })
        #expect(drawn.count == 6)
        #expect(drawn.last?.trimmingCharacters(in: .whitespaces) == "bar")
        let measured = measureChild(
            Text("A").safeAreaInset(edge: .bottom) { Text("BBB") },
            proposal: ProposedSize(width: 10, height: 6), context: makeRenderContext())
        #expect(measured.width == 3 && measured.height == 2, "the measure agrees with the render")
    }

    @Test("An empty bar leaves the view as it was, spacing and all")
    func emptyBar() {
        #expect(lines(Text("A").safeAreaInset(edge: .bottom, spacing: 2) { EmptyView() }) == ["A"])
    }
}
