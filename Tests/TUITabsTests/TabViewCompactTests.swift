//  🖥️ TUI — A Terminal UI framework for Swift
//  TabViewCompactTests.swift
//
//  A `.sidebarAdaptable` tab view in a horizontally compact size class shows
//  its tabs as a strip, not a sidebar (decisions B3), as SwiftUI's shows a tab
//  bar on iPhone and a sidebar on iPad.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUITabs
@testable import TUITestSupport

/// Reports what a tab's content reads about where the tabs are.
private struct PlacementProbe: View {
    @Environment(\.tabBarPlacement) private var placement
    @Environment(\.isTabBarShowingSections) private var showingSections

    var body: some View {
        Text("PLACED \(placement == .sidebar ? "sidebar" : placement == .topBar ? "topBar" : "other")"
            + " \(showingSections ? "sections" : "flat")")
    }
}

/// The size class the tab view is drawn in, and how often its first tab's
/// content appeared.
@Observable
private final class Classes: @unchecked Sendable {
    var horizontal: UserInterfaceSizeClass = .regular
    var appearances = 0
}

@MainActor
@Suite("A sidebar-adaptable tab view in a compact size class shows a strip")
struct TabViewCompactTests {
    private func mail(_ sizeClass: UserInterfaceSizeClass) -> some View {
        TabView {
            Tab("Inbox", systemImage: "tray") { PlacementProbe() }
            Tab("Sent", systemImage: "paperplane") { Text("SENT BODY") }
            TabSection("Folders") {
                Tab("Work", systemImage: "folder") { Text("WORK BODY") }
            }
            Tab("Archive", systemImage: "archivebox") { Text("ARCHIVE BODY") }
                .tabPlacement(.sidebarOnly)
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.horizontalSizeClass, sizeClass)
    }

    private func lines(_ sizeClass: UserInterfaceSizeClass) -> [String] {
        renderToBuffer(mail(sizeClass), context: makeRenderContext(width: 70, height: 12)).lines.map(\.stripped)
    }

    @Test("Regular: the sidebar lists the tabs, one to a row, with its sections")
    func regularSidebar() {
        let drawn = lines(.regular)
        let text = drawn.joined(separator: "\n")
        #expect(!drawn.contains { $0.contains("Inbox") && $0.contains("Sent") }, "\(text)")
        #expect(text.contains("Folders") && text.contains("Archive"), "\(text)")
        #expect(text.contains("PLACED sidebar sections"), "\(text)")
    }

    @Test("Compact: the tabs are a strip over the content, with no section headers and no sidebar-only tab")
    func compactStrip() {
        let drawn = lines(.compact)
        let text = drawn.joined(separator: "\n")
        #expect(drawn.contains { $0.contains("Inbox") && $0.contains("Sent") && $0.contains("Work") }, "\(text)")
        #expect(!text.contains("Folders") && !text.contains("Archive"), "\(text)")
        #expect(text.contains("PLACED topBar flat"), "\(text)")
    }

    // MARK: - Across a change of size class

    private struct Mail: View {
        let classes: Classes
        var body: some View {
            TabView {
                Tab("Inbox", systemImage: "tray") {
                    Text("INBOX BODY").onAppear { classes.appearances += 1 }
                }
                Tab("Sent", systemImage: "paperplane") { Text("SENT BODY") }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environment(\.horizontalSizeClass, classes.horizontal)
        }
    }

    private struct Page: App {
        let classes: Classes
        init() { self.init(classes: Classes()) }
        init(classes: Classes) { self.classes = classes }
        var body: some Scene { WindowGroup { Mail(classes: classes) } }
    }

    @Test("The selected tab's content keeps its place when the size class changes")
    func contentKeepsItsPlace() {
        let classes = Classes()
        let app = HeadlessApp(Page(classes: classes), width: 50, height: 10)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        #expect(classes.appearances == 1)
        classes.horizontal = .compact
        frame()
        frame()
        #expect(app.screen.contains { $0.stripped.contains("INBOX BODY") }, "\(app.screen)")
        classes.horizontal = .regular
        frame()
        frame()
        #expect(classes.appearances == 1, "the tab's content was made anew when the size class changed")
    }
}
