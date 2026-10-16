//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainersPage+Groups.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// `GroupBox` and `ControlGroup`: a titled box around related content, and a
/// row of related controls drawn as one — the two SwiftUI containers that are
/// about grouping rather than layout.
struct GroupingContainersRow: View {
    @State private var zoom = 100
    @State private var autosaves = true

    /// Steps of the zoom the control group's buttons move between.
    private static let zoomStep = 25

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            DemoSection("page.containers.section.groupBox") {
                VStack(alignment: .leading, spacing: 1) {
                    // A title, and content inset on a surface of its own.
                    GroupBox("page.containers.groupBox.title") {
                        Text("page.containers.groupBox.body")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                    // A label of any view — here an icon and a title.
                    GroupBox {
                        Toggle("page.containers.groupBox.toggle", isOn: $autosaves)
                    } label: {
                        Label("page.containers.groupBox.labelTitle", systemImage: "gearshape")
                    }
                }
            }
            DemoSection("page.containers.section.controlGroup") {
                VStack(alignment: .leading, spacing: 1) {
                    // Three buttons drawn side by side and touching, one control
                    // to the eye — each still its own Tab stop.
                    ControlGroup {
                        Button("−") { zoom = max(Self.zoomStep, zoom - Self.zoomStep) }
                        Button("100%") { zoom = 100 }
                        Button("+") { zoom = min(400, zoom + Self.zoomStep) }
                    }
                    Text("\(L("page.containers.controlGroup.zoom")) \(zoom)%")
                        .foregroundStyle(.palette.foregroundSecondary)
                }
            }
        }
    }
}
