//  🖥️ TUI — A Terminal UI framework for Swift
//  MenusClip.swift
//
//  `menus`: a mail app's menu bar opened from the keyboard — File, across to
//  Edit, down into a submenu — and then a message's context menu.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

@MainActor
let menusClip = Clip(
    id: "menus",
    title: "Menus",
    columns: 112,
    rows: 30,
    terminal: "apple",
    script: menusScript(),
    run: {
        // The app menu is named for the process, and this one is a mail app.
        ProcessInfo.processInfo.processName = "Mail"
        await MenusApp.main()
    }
)

private func menusScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 50, height: 17)), .wait(0.9)]
    // The menu bar: the app menu opens, then across to File, Edit and Message,
    // down to Move To, and into it.
    script += [.f10, .wait(0.8), .right, .wait(0.6), .down, .wait(0.35), .down, .wait(0.5)]
    script += [.right, .wait(0.6), .right, .wait(0.6)]
    script += Step.repeat(.down, 3, interval: 0.35)
    script += [.wait(0.3), .right, .wait(0.9), .down, .wait(0.4), .down, .wait(0.7), .escape, .wait(0.25), .escape,
               .wait(0.8)]
    // A message's context menu, from the keyboard (Shift+F10), and away again.
    script += [.down, .wait(0.4), .down, .wait(0.5), .shiftF10, .wait(0.9), .down, .wait(0.35), .down, .wait(0.35),
               .down, .wait(0.8), .escape, .wait(0.4), .up, .wait(0.3), .up, .wait(0.8)]
    return script
}

struct MenusApp: App {
    @State private var unread = 3

    var body: some Scene {
        WindowGroup("TUI · Mail") {
            Mailbox()
                .palette(SystemPalette(.violet))
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {}.keyboardShortcut("n", modifiers: .control)
                Button("New Mailbox…") {}
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save as Draft") {}.keyboardShortcut("s", modifiers: .control)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {}.keyboardShortcut("p", modifiers: .control)
            }
            CommandMenu("Message") {
                Button("Reply") {}.keyboardShortcut("r", modifiers: .control)
                Button("Reply All") {}
                Button("Forward") {}.keyboardShortcut("f", modifiers: .control)
                Menu("Move To") {
                    Button("Inbox") {}
                    Button("Archive") {}
                    Button("Receipts") {}
                    Button("Travel") {}
                }
                Menu("Flag") {
                    Button("Red") {}
                    Button("Orange") {}
                    Button("Green") {}
                }
                Divider()
                Button("Mark as Unread") {}.keyboardShortcut("u", modifiers: .control)
            }
        }
    }
}

/// One message in the list.
struct MailMessage: Identifiable, Hashable {
    let id: Int
    let from: String
    let subject: String
    let time: String
}

/// A mailbox: the messages, the selected one's text beside them.
struct Mailbox: View {
    @State private var selection: Int? = 0

    private let messages = [
        MailMessage(id: 0, from: "Ada Lovelace", subject: "Notes on the engine", time: "09:41"),
        MailMessage(id: 1, from: "Grace Hopper", subject: "Re: compiler review", time: "09:12"),
        MailMessage(id: 2, from: "Linus Pauling", subject: "Lunch on Thursday?", time: "Yesterday"),
        MailMessage(id: 3, from: "Hedy Lamarr", subject: "Frequency hopping patent", time: "Yesterday"),
        MailMessage(id: 4, from: "Alan Turing", subject: "Draft: on computable numbers", time: "Mon"),
        MailMessage(id: 5, from: "Katherine Johnson", subject: "Trajectory figures attached", time: "Mon"),
        MailMessage(id: 6, from: "Claude Shannon", subject: "Juggling robot, part II", time: "Sun"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            List(messages, selection: $selection) { message in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(verbatim: message.from).bold()
                        Spacer()
                        Text(verbatim: message.time).foregroundStyle(.palette.foregroundTertiary)
                    }
                    Text(verbatim: message.subject).foregroundStyle(.palette.foregroundSecondary)
                }
                .contextMenu {
                    Button("Reply") {}
                    Button("Forward") {}
                    Button("Archive") {}
                    Divider()
                    Button("Delete", role: .destructive) {}
                }
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                let message = messages[selection ?? 0]
                Text(verbatim: message.subject).bold()
                Text(verbatim: "From \(message.from) · \(message.time)").foregroundStyle(.palette.foregroundSecondary)
                Text(verbatim: "Dear colleague, the figures you asked for are attached, with my notes on the "
                     + "method. Shall we go through them together this week?")
            }
            .padding(.horizontal, 1)
        }
        .padding(.horizontal, 1)
    }
}
