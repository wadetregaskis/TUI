//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationLinkIndicatorTests.swift
//
//  `navigationLinkIndicatorVisibility(_:)`: a link draws a `›` when asked
//  to, none by default, and the setting reaches the links inside a view and
//  can be narrowed to one link.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Navigation link indicator", .rendersEnglishUI)
struct NavigationLinkIndicatorTests {
    private func lines(_ view: some View) -> [String] {
        renderToBuffer(NavigationStack { view }, context: makeRenderContext(width: 30, height: 6))
            .lines.map(\.stripped)
    }

    private func line(_ lines: [String], containing text: String) -> String {
        lines.first { $0.contains(text) } ?? ""
    }

    @Test("Automatic and hidden draw no indicator; visible draws one after the label")
    func visibility() {
        let link = { NavigationLink("Detail", value: 1) }
        #expect(!line(lines(link()), containing: "Detail").contains("›"))
        #expect(!line(lines(link().navigationLinkIndicatorVisibility(.hidden)), containing: "Detail").contains("›"))
        #expect(line(lines(link().navigationLinkIndicatorVisibility(.visible)), containing: "Detail").contains("Detail ›"))
    }

    @Test("Set on a stack it reaches every link; set on one link it overrides the stack's")
    func scope() {
        let drawn = lines(
            VStack {
                NavigationLink("First", value: 1)
                NavigationLink("Second", value: 2).navigationLinkIndicatorVisibility(.hidden)
            }
            .navigationLinkIndicatorVisibility(.visible))
        #expect(line(drawn, containing: "First").contains("›"))
        #expect(!line(drawn, containing: "Second").contains("›"))
    }
}
