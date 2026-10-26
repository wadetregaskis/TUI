//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarModifierMetadataTests.swift
//
//  `.toolbar` and `.toolbarVisibility` are not containers: a `.tag`, a
//  container value or a `.zIndex` written inside either still reaches the
//  container around it, as it does in SwiftUI, where a value "is unaffected by
//  views that aren't containers".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIChrome
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Metadata through the toolbar modifiers")
struct ToolbarModifierMetadataTests {

    private func render(_ view: some View, width: Int = 20, height: Int = 4) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines.map(\.stripped)
    }

    @Test("A tag inside .toolbar or .toolbarVisibility is still the subview's tag")
    func tagSurvives() {
        let lines = render(
            VStack {
                ForEach(
                    subviews: Group {
                        Text("a").tag(5).toolbar { ToolbarItem { Text("item") } }
                        Text("b").tag(6).toolbarVisibility(.hidden, for: .bottomBar)
                        Text("c").tag(7)
                    }
                ) { subview in
                    Text("tag \(subview.containerValues.tag(for: Int.self) ?? -1)")
                }
            })
        #expect(lines.prefix(3) == ["tag 5", "tag 6", "tag 7"], "\(lines)")
    }

    @Test("A zIndex inside .toolbar or .toolbarVisibility still orders the ZStack")
    func zIndexSurvives() {
        let toolbar = render(
            ZStack {
                Text("BBB").zIndex(1).toolbar { ToolbarItem { Text("item") } }
                Text("AAA")
            })
        let visibility = render(
            ZStack {
                Text("BBB").zIndex(1).toolbarVisibility(.hidden, for: .windowToolbar)
                Text("AAA")
            })
        #expect(toolbar.first?.contains("BBB") == true, "\(toolbar)")
        #expect(visibility.first?.contains("BBB") == true, "\(visibility)")
    }
}
