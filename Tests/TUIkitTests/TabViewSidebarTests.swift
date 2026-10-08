//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewSidebarTests.swift
//
//  `.sidebarAdaptable`: a sidebar listing the tabs — sections under their
//  headers, badges, a disabled tab stepped over — beside the selected tab's
//  content, and the environment values that say where a tab view's tabs are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// Reports what a tab's content reads about where the tabs are.
private struct PlacementProbe: View {
    @Environment(\.tabBarPlacement) private var placement
    @Environment(\.isTabBarShowingSections) private var showingSections

    var body: some View {
        let name: String =
            switch placement {
            case .some(.sidebar): "sidebar"
            case .some(.topBar): "topBar"
            case .some: "other"
            case nil: "none"
            }
        Text("PLACED \(name) \(showingSections ? "sections" : "flat")")
    }
}

@MainActor
@Suite("Tab view sidebar")
struct TabViewSidebarTests {
    private final class Box {
        var value = 0
    }

    private func mail(_ box: Box) -> some View {
        TabView(selection: Binding(get: { box.value }, set: { box.value = $0 })) {
            Tab("Inbox", systemImage: "tray", value: 0) { Text("INBOX BODY") }
                .badge(3)
            Tab("Sent", systemImage: "paperplane", value: 1) { Text("SENT BODY") }
            TabSection("Folders") {
                Tab("Work", systemImage: "folder", value: 2) { Text("WORK BODY") }
                Tab("Home", systemImage: "folder", value: 3) { Text("HOME BODY") }.disabled(true)
                Tab("Old", systemImage: "folder", value: 4) { Text("OLD BODY") }
            }
            Tab("Archive", systemImage: "archivebox", value: 5) { Text("ARCHIVE BODY") }
                .tabPlacement(.sidebarOnly)
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @Test("The sidebar lists every tab, its section's header above it, its badge beside it")
    func sidebarListsTheTabs() {
        let box = Box()
        let lines = renderToBuffer(mail(box), context: makeRenderContext(width: 60, height: 12))
            .lines.map(\.stripped)
        let text = lines.joined(separator: "\n")
        for title in ["Inbox", "Sent", "Folders", "Work", "Home", "Old", "Archive"] {
            #expect(text.contains(title), "\(title) in\n\(text)")
        }
        #expect(lines.contains { $0.contains("Inbox") && $0.contains("3") }, "\(text)")
        #expect(text.contains("INBOX BODY") && !text.contains("SENT BODY"), "\(text)")
        // The section's header is above its first tab, and the tab bar's tabs
        // are not drawn as a strip anywhere.
        let header = lines.firstIndex { $0.contains("Folders") }
        let work = lines.firstIndex { $0.contains("Work") }
        #expect(header != nil && work != nil && header! < work!, "\(text)")
        #expect(!text.contains("▐"), "no strip chips: \(text)")
    }

    @Test("The arrow keys move through the tabs, stepping over a disabled one, and Return chooses")
    func keysChooseTheTab() {
        let box = Box()
        let context = makeRenderContext(width: 60, height: 12)
        let view = mail(box)
        _ = renderToBuffer(view, context: context)
        _ = renderToBuffer(view, context: context)
        let manager = context.environment.focusManager
        for _ in 0..<3 {
            _ = manager?.dispatchKeyEvent(KeyEvent(key: .down))
            _ = renderToBuffer(view, context: context)
        }
        #expect(box.value == 0, "the cursor moves; the selection waits for Return")
        _ = manager?.dispatchKeyEvent(KeyEvent(key: .enter))
        // Sent, Work, then Old: Home is disabled, and the header is no row.
        #expect(box.value == 4, "selected \(box.value)")
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
        #expect(lines.contains("OLD BODY"), "\(lines)")
    }

    @Test("A tab's content reads where the tabs are", arguments: [true, false])
    func placementEnvironment(sidebar: Bool) {
        let tabs = TabView(selection: .constant(0)) {
            Tab("A", value: 0) { PlacementProbe() }
        }
        let view: AnyView = sidebar ? AnyView(tabs.tabViewStyle(.sidebarAdaptable)) : AnyView(tabs)
        let text = renderToBuffer(view, context: makeRenderContext(width: 60, height: 8))
            .lines.map(\.stripped).joined()
        #expect(text.contains(sidebar ? "PLACED sidebar sections" : "PLACED topBar flat"), "\(text)")
        let outside = renderToBuffer(PlacementProbe(), context: makeRenderContext(width: 60, height: 2))
            .lines.map(\.stripped).joined()
        #expect(outside.contains("PLACED none flat"), "\(outside)")
    }

    @Test("The sidebar's header, footer and bottom bar are drawn around its tabs, and only in a sidebar")
    func accessories() {
        let tabs = TabView(selection: .constant(0)) {
            Tab("Only", value: 0) { Text("BODY") }
        }
        .tabViewSidebarHeader { Text("HEADER") }
        .tabViewSidebarFooter { Text("FOOTER") }
        .tabViewSidebarBottomBar { Text("BOTTOM") }
        let sidebar = renderToBuffer(
            tabs.tabViewStyle(.sidebarAdaptable), context: makeRenderContext(width: 60, height: 12)
        ).lines.map(\.stripped)
        let header = sidebar.firstIndex { $0.contains("HEADER") }
        let only = sidebar.firstIndex { $0.contains("Only") }
        let footer = sidebar.firstIndex { $0.contains("FOOTER") }
        let bottom = sidebar.firstIndex { $0.contains("BOTTOM") }
        #expect(header != nil && only != nil && footer != nil && bottom != nil, "\(sidebar)")
        if let header, let only, let footer, let bottom {
            #expect(header < only && only < footer && footer < bottom, "\(sidebar)")
        }
        let strip = renderToBuffer(tabs, context: makeRenderContext(width: 60, height: 12))
            .lines.map(\.stripped).joined()
        #expect(!strip.contains("HEADER") && !strip.contains("FOOTER"), "\(strip)")
    }

    @Test("The bottom accessory placement is nil, as on macOS")
    func bottomAccessoryPlacement() {
        #expect(EnvironmentValues().tabViewBottomAccessoryPlacement == nil)
    }

    @Test("The sidebar is a sidebar list: a Label tab label's icon is drawn in the list item tint")
    func sidebarTintsLabelIcons() {
        let tabs = TabView {
            Tab {
                Text("BODY")
            } label: {
                Label {
                    Text("Work")
                } icon: {
                    Text("*")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .listItemTint(.fixed(.red))
        let row =
            renderToBuffer(tabs, context: makeRenderContext(width: 40, height: 6)).lines
            .first { $0.stripped.contains("Work") } ?? ""
        #expect(row.contains(ANSIRenderer.colorize("*", foreground: Color.red.opaqueSpelling)), "\(row.debugDescription)")
    }

    @Test("A section's actions are drawn after its header in the sidebar; on a lone tab, and in a strip, nowhere")
    func sectionActions() {
        let tabs = TabView {
            Tab("Inbox", systemImage: "tray") { Text("INBOX BODY") }
                .sectionActions { Text("LONE") }
            TabSection("Folders") {
                Tab("Work", systemImage: "folder") { Text("WORK BODY") }
            }
            .sectionActions { Text("NEW FOLDER") }
        }
        let sidebar = renderToBuffer(
            tabs.tabViewStyle(.sidebarAdaptable), context: makeRenderContext(width: 70, height: 12)
        ).lines.map(\.stripped)
        #expect(sidebar.contains { $0.contains("Folders") && $0.contains("NEW FOLDER") }, "\(sidebar)")
        #expect(!sidebar.joined().contains("LONE"), "\(sidebar)")
        let strip = renderToBuffer(tabs, context: makeRenderContext(width: 70, height: 12))
            .lines.map(\.stripped).joined()
        #expect(!strip.contains("NEW FOLDER") && !strip.contains("LONE"), "\(strip)")
    }
}
