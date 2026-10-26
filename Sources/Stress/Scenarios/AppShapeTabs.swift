//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeTabs.swift
//
//  A mail app's sidebar as a tab view: tabs in sections, one per folder, in
//  the sidebar a `.sidebarAdaptable` tab view draws. Its own file for the reason
//  `AppShapeSidebar.swift` gives; see `AppShapes.swift` for why the
//  applications exist at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// Two fixed tabs, then a `TabSection` of one looped tab per folder, beside the
/// selected tab's messages.
///
/// The one app shape with a tab view's sidebar (decisions SPC3: no scenario had
/// one, so the sidebar's per-tab list and its sections were measured by
/// nothing). The selected folder's list moves with the tick; the sidebar holds
/// still, as a real one does between keystrokes.
struct FolderTabsApp: View {
    let folders: [SidebarProject]
    let seed: UInt64
    @State private var selection = 0

    init(count: Int, seed: UInt64) {
        self.folders = (0..<count).map { SidebarProject.sample($0, seed: seed) }
        self.seed = seed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "sidebar-tabs", folders.count)).bold()
            TabView(selection: $selection) {
                Tab("Inbox", systemImage: "tray", value: -1) { FolderMessages(seed: seed, folder: -1) }
                    .badge(folders.count)
                Tab("Sent", systemImage: "paperplane", value: -2) { FolderMessages(seed: seed, folder: -2) }
                TabSection("Folders") {
                    ForEach(folders) { folder in
                        Tab(folder.name, systemImage: "folder", value: folder.id) {
                            FolderMessages(seed: seed, folder: folder.id)
                        }
                        .badge(folder.openIssues)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        }
    }
}

/// The selected folder's messages, moving with the tick.
private struct FolderMessages: View {
    let seed: UInt64
    let folder: Int
    @Environment(StressClock.self) private var clock

    var body: some View {
        let tick = clock.tick
        List {
            ForEach(0..<40, id: \.self) { index in
                let h = mix(seed, folder &* 1_000 &+ index &+ tick)
                HStack(spacing: 1) {
                    Text(verbatim: Synth.name(h))
                    Spacer()
                    Text(verbatim: Synth.status(h)).dim()
                }
            }
        }
    }
}
