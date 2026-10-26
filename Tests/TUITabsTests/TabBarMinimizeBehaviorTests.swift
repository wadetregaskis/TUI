//  🖥️ TUI — A Terminal UI framework for Swift
//  TabBarMinimizeBehaviorTests.swift
//
//  `tabBarMinimizeBehavior(_:)`: under `.automatic`, macOS's one value, a
//  `.bordered` or `.grouped` tab view in a horizontally compact size class
//  draws the compact strip, as a `.sidebarAdaptable` one does (owner,
//  TABBARMIN, option b). A regular class, the default, draws them as ever.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITabs
@testable import TUITestSupport

/// The tab styles that collapse, and the strip they collapse to.
enum MinimizedStyle: CaseIterable, Sendable {
    case bordered, grouped
}

@MainActor
@Suite("A tab bar minimizes to the compact strip in a compact size class")
struct TabBarMinimizeBehaviorTests {
    private func tabs() -> some View {
        TabView {
            Tab("Inbox", systemImage: "tray") { Text("INBOX BODY") }
            Tab("Sent", systemImage: "paperplane") { Text("SENT BODY") }
        }
    }

    private func styled(_ style: MinimizedStyle) -> some View {
        Group {
            switch style {
            case .bordered: tabs().tabViewStyle(.bordered)
            case .grouped: tabs().tabViewStyle(.grouped)
            }
        }
    }

    private func lines(_ view: some View, _ sizeClass: UserInterfaceSizeClass) -> [String] {
        renderToBuffer(
            view.environment(\.horizontalSizeClass, sizeClass), context: makeRenderContext(width: 40, height: 8)
        ).lines.map(\.stripped)
    }

    @Test("Regular: the folder tabs over a box, as ever", arguments: MinimizedStyle.allCases)
    func regularKeepsTheFolderTabs(style: MinimizedStyle) {
        let drawn = lines(styled(style), .regular)
        #expect(drawn != lines(tabs().tabViewStyle(.compact), .regular), "\(drawn)")
        #expect(drawn.joined().contains("│"), "no box around the content: \(drawn)")
    }

    @Test("Compact: the compact strip, with and without the modifier", arguments: MinimizedStyle.allCases)
    func compactDrawsTheStrip(style: MinimizedStyle) {
        let strip = lines(tabs().tabViewStyle(.compact), .compact)
        #expect(lines(styled(style), .compact) == strip)
        #expect(lines(styled(style).tabBarMinimizeBehavior(.automatic), .compact) == strip)
    }

    @Test("The behavior is in the environment, `.automatic` by default")
    func environmentValue() {
        #expect(EnvironmentValues().tabBarMinimizeBehavior == .automatic)
    }
}
