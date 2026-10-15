//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewStyleTests.swift
//
//  SwiftUI's tab view styles, each drawing one of TUIkit's two strips:
//  `.automatic` and `.tabBarOnly` the compact one, `.grouped` the bordered one
//  (measured on macOS 15.8: the first two a toolbar tab bar, the third an
//  `NSTabView`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitTabs
@testable import TUIkitTestSupport

@MainActor
@Suite("Tab view styles")
struct TabViewStyleTests {
    private func lines<S: TabViewStyle>(_ style: S) -> [String] {
        let view = TabView(selection: .constant(0)) {
            Tab("One", value: 0) { Text("first") }
            Tab("Two", value: 1) { Text("second") }
        }
        .tabViewStyle(style)
        return renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines
    }

    @Test("The two looks differ, or nothing here can fail")
    func looksDiffer() {
        #expect(lines(.compact) != lines(.bordered))
    }

    @Test(".automatic and .tabBarOnly draw the compact strip")
    func automaticAndTabBarOnlyAreCompact() {
        #expect(lines(.automatic) == lines(.compact))
        #expect(lines(.tabBarOnly) == lines(.compact))
    }

    @Test(".grouped draws the bordered folder tabs over a box")
    func groupedIsBordered() {
        #expect(lines(.grouped) == lines(.bordered))
    }
}
