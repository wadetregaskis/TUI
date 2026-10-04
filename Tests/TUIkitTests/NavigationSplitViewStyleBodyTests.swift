//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewStyleBodyTests.swift
//
//  `NavigationSplitViewStyle.makeBody(configuration:)`: a built-in style's
//  body is the columns laid out by its proportions, a custom style can draw
//  one and decorate it, and a style that gives only proportions still works.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// SwiftUI's shape of a custom style: a built-in's body, decorated.
private struct FramedBalancedStyle: NavigationSplitViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        BalancedNavigationSplitViewStyle().makeBody(configuration: configuration)
            .border()
    }
}

/// TUIkit's own shape: proportions only.
private struct NarrowSidebarStyle: NavigationSplitViewStyle {
    var sidebarProportion: Double { 0.2 }
    var threeColumnProportions: (sidebar: Double, content: Double, detail: Double) { (0.2, 0.2, 0.6) }
}

@MainActor
@Suite("Navigation split view style bodies", .rendersEnglishUI)
struct NavigationSplitViewStyleBodyTests {
    private func split(_ style: some NavigationSplitViewStyle) -> [String] {
        let view = NavigationSplitView {
            Text("sidebar")
        } detail: {
            Text("detail")
        }
        .navigationSplitViewStyle(style)
        return renderToBuffer(view, context: makeRenderContext(width: 60, height: 8)).lines.map(\.stripped)
    }

    private func column(of text: String, in lines: [String]) -> Int? {
        for line in lines {
            if let range = line.range(of: text) { return line.distance(from: line.startIndex, to: range.lowerBound) }
        }
        return nil
    }

    @Test("A custom style draws a built-in's body and decorates it")
    func decoratedBuiltIn() throws {
        let framed = split(FramedBalancedStyle())
        let balanced = split(.balanced)
        #expect(framed.first?.hasPrefix("╭") == true, "the custom body's border: \(framed)")
        let framedDetail = try #require(column(of: "detail", in: framed))
        let balancedDetail = try #require(column(of: "detail", in: balanced))
        // Inside a border the split is two columns narrower, so the balanced
        // proportion puts the detail a little further left, plus the border's.
        #expect(abs(framedDetail - balancedDetail) <= 2, "laid out by the balanced proportions")
    }

    @Test("A style that gives only proportions is laid out by them")
    func proportionsOnly() throws {
        let narrow = try #require(column(of: "detail", in: split(NarrowSidebarStyle())))
        let automatic = try #require(column(of: "detail", in: split(.automatic)))
        #expect(narrow < automatic, "a 0.2 sidebar leaves the detail further left than 0.33")
    }

    @Test("A built-in style's body is its columns: the same picture as before bodies existed")
    func builtInBodyIsTheColumns() {
        let viaBody = renderToBuffer(
            BalancedNavigationSplitViewStyle().makeBody(
                configuration: NavigationSplitViewStyleConfiguration(
                    columns: AnyView(
                        _NavigationSplitViewCore(
                            sidebar: Text("sidebar"), content: EmptyView(), detail: Text("detail"),
                            isThreeColumn: false, columnVisibility: nil)))),
            context: makeRenderContext(width: 60, height: 8)
        ).lines.map(\.stripped)
        #expect(viaBody == split(.balanced))
    }
}
