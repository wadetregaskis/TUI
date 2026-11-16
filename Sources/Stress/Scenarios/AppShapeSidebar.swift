//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeSidebar.swift
//
//  A source list: one hand-written row above a few hundred looped ones — the
//  sidebar a `NavigationSplitView` app writes. Its own file because
//  `AppShapeViews.swift` is already at the size the repository splits at; see
//  `AppShapes.swift` for why the applications exist at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

// MARK: - The data

/// A project, as a sidebar lists one.
struct SidebarProject: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let openIssues: Int

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        return Self(id: index, name: Synth.slug(h), openIssues: Int(h % 40))
    }
}

/// What the tagged sidebar selects: everything, or one project — an app's own
/// enum, which nothing but a `.tag(_:)` on each looped row can name.
enum SidebarPick: Hashable, Sendable {
    case all
    case project(Int)
}

// MARK: - The app

/// "All projects", written by hand, then one looped row per project, beside a
/// detail pane.
///
/// The hand-written row is the point. It gives the loop a sibling, so the
/// `List` cannot take the windowed path a loop gets as its whole content: the
/// children arrive flattened and are walked eagerly, every row every frame,
/// and each looped row's selection value has to be recovered from the loop that
/// made it. The pair prices that recovery: `sidebar` tags every looped row with
/// the app's enum, which can only be read off the BUILT row, and
/// `sidebar-untagged` is the same list answering by each project's `id`, which
/// is a key-path read.
struct ProjectSidebarApp: View {
    /// Synthesised once, like a workspace's project list.
    let projects: [SidebarProject]
    let tagged: Bool

    init(count: Int, seed: UInt64, tagged: Bool) {
        self.projects = (0..<count).map { SidebarProject.sample($0, seed: seed) }
        self.tagged = tagged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                Lf(
                    "stress.scenario.app-shapes.heading",
                    tagged ? "sidebar" : "sidebar-untagged", projects.count)
            ).bold()
            NavigationSplitView {
                if tagged {
                    TaggedProjectList(projects: projects)
                } else {
                    UntaggedProjectList(projects: projects)
                }
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(projects.count) projects")
                    Divider()
                    HStack(spacing: 2) {
                        Spacer()
                        // In a leaf, for the reason `TickStamp` gives.
                        TickStamp()
                    }
                }
            }
        }
    }
}

/// The sidebar under the app's enum: every looped row carries a `.tag(_:)`.
private struct TaggedProjectList: View {
    let projects: [SidebarProject]
    @State private var pick: SidebarPick? = .all

    var body: some View {
        List(selection: $pick) {
            Text("All projects").tag(SidebarPick.all)
            ForEach(projects) { project in
                ProjectRow(project: project).tag(SidebarPick.project(project.id))
            }
        }
    }
}

/// The same sidebar under the projects' own ids: no looped row is tagged, and
/// the hand-written one takes an id no project has.
private struct UntaggedProjectList: View {
    let projects: [SidebarProject]
    @State private var pick: Int? = -1

    var body: some View {
        List(selection: $pick) {
            Text("All projects").tag(-1)
            ForEach(projects) { ProjectRow(project: $0) }
        }
    }
}

// MARK: - The filtered sidebar

/// The source list filtered in its body, as a search field drives one: two
/// thousand projects, a new array of them every frame, in the sidebar a
/// `NavigationSplitView` hugs.
///
/// The shape the hug's kept width is priced on. The split view asks its sidebar
/// for the width of its widest row on every frame, by the measure and again by
/// the render, and the rows the list is handed are a new buffer each time, so a
/// kept width compared against the rows themselves compared every one of them
/// per ask (`_ListCore.widestRowWidth`). The `sidebar` pair has a hand-written
/// row, which leaves the list nothing to compare and walks it instead.
struct FilteredSidebarApp: View {
    /// Synthesised once, like a workspace's project list.
    let projects: [SidebarProject]
    @State private var pick: Int? = 0

    init(count: Int, seed: UInt64) {
        self.projects = (0..<count).map { SidebarProject.sample($0, seed: seed) }
    }

    var body: some View {
        // Every project with issues open: what a "has issues" filter shows, and
        // a new array each time the body runs.
        let shown = projects.filter { $0.openIssues > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "sidebar-filtered", shown.count)).bold()
            NavigationSplitView {
                List(shown, selection: $pick) { ProjectRow(project: $0) }
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(shown.count) of \(projects.count) projects")
                    Divider()
                    HStack(spacing: 2) {
                        Spacer()
                        // In a leaf, for the reason `TickStamp` gives.
                        TickStamp()
                    }
                }
            }
        }
    }
}

/// One project: its name, and a count pushed to the trailing edge.
private struct ProjectRow: View {
    let project: SidebarProject

    var body: some View {
        HStack(spacing: 1) {
            Text(project.name)
            Spacer()
            Text("\(project.openIssues)").dim()
        }
    }
}
