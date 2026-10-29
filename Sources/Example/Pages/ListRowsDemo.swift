//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// What a row can say about itself in a list: a background of its own
/// (`.listRowBackground`); insets of its own (`.listRowInsets`); a section
/// header made prominent (`.headerProminence`). And what an empty list draws in
/// place of its rows — TUI's `.listEmptyPlaceholder(_:)`. Badges have a demo of
/// their own, ``BadgesDemo``.
struct ListRowsDemo: View {
    @State private var showsTasks = true

    private static let tasks = ["Buy bread", "Water the plants", "Call Ada"]

    var body: some View {
        DemoSection("page.list.rowsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.list.rowsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    List {
                        Section("page.list.rows.inbox") {
                            Text("page.list.rows.background")
                                .listRowBackground(Color.palette.info.opacity(0.35))
                            Text("page.list.rows.inset").listRowInsets(.leading, 4)
                        }
                        .headerProminence(.increased)
                    }
                    .frame(width: 36, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Toggle("page.list.rows.showTasks", isOn: $showsTasks)
                        List(showsTasks ? Self.tasks : [], id: \.self) { task in
                            Text(verbatim: task)
                        }
                        .listEmptyPlaceholder("page.list.rows.nothingToDo")
                        .frame(width: 30, height: 5)
                        Text("page.list.rows.tasksHint")
                            .foregroundStyle(.palette.foregroundSecondary)
                            .frame(width: 30, alignment: .leading)
                    }
                }
            }
        }
    }
}
