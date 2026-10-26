//  🖥️ TUI — A Terminal UI framework for Swift
//  MenusClip.swift
//
//  `menus`: a mail app's menu bar opened from the keyboard — File, across to
//  Message, into Flag — which flags a message; a message's context menu,
//  which archives it out of the list; and Edit ▸ Undo, twice, by its
//  shortcut, which puts both back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
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
    // The menu bar: the app menu opens, across File and Edit to Message, down
    // to Flag, and into it: the first message is flagged red.
    script += [.f10, .wait(0.8), .right, .wait(0.6), .down, .wait(0.35), .down, .wait(0.5)]
    script += [.right, .wait(0.6), .right, .wait(0.6)]
    script += Step.repeat(.down, 4, interval: 0.35)
    script += [.wait(0.3), .right, .wait(0.8), .enter, .wait(1.1)]
    // A message's context menu, from the keyboard (Shift+F10): Archive, and
    // it leaves the list.
    script += [.down, .wait(0.4), .down, .wait(0.5), .shiftF10, .wait(0.8), .down, .wait(0.35), .down, .wait(0.7),
               .enter, .wait(1.3)]
    // Edit ▸ Undo, twice from its shortcut: the message comes back, then the
    // flag goes, and the loop ends where it began.
    script += [.control("z"), .wait(1.0), .control("z"), .wait(0.6), .up, .wait(0.3), .up, .wait(0.8)]
    return script
}

struct MenusApp: App {
    @State private var store = MailStore()

    var body: some Scene {
        WindowGroup("TUI · Mail") {
            Mailbox(store: store)
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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }.keyboardShortcut("z", modifiers: .control)
                    .disabled(!store.canUndo)
            }
            CommandMenu("Message") {
                Button("Reply") {}.keyboardShortcut("r", modifiers: .control)
                Button("Reply All") {}
                Button("Forward") {}.keyboardShortcut("f", modifiers: .control)
                Menu("Move To") {
                    Button("Archive") { store.archiveSelected() }
                    Button("Receipts") { store.archiveSelected() }
                    Button("Travel") { store.archiveSelected() }
                }
                Menu("Flag") {
                    Button("Red") { store.flagSelected(.red) }
                    Button("Orange") { store.flagSelected(.orange) }
                    Button("Green") { store.flagSelected(.green) }
                }
                Divider()
                Button("Mark as Unread") { store.markSelectedUnread() }.keyboardShortcut("u", modifiers: .control)
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
    var flag: Color? = nil
    var unread = false
}

/// The mailbox the menus act on: what each command does to it, and an undo
/// for each.
@Observable @MainActor
final class MailStore {
    var messages = [
        MailMessage(id: 0, from: "Ada Lovelace", subject: "Notes on the engine", time: "09:41"),
        MailMessage(id: 1, from: "Grace Hopper", subject: "Re: compiler review", time: "09:12"),
        MailMessage(id: 2, from: "Linus Pauling", subject: "Lunch on Thursday?", time: "Yesterday"),
        MailMessage(id: 3, from: "Hedy Lamarr", subject: "Frequency hopping patent", time: "Yesterday"),
        MailMessage(id: 4, from: "Alan Turing", subject: "Draft: on computable numbers", time: "Mon"),
        MailMessage(id: 5, from: "Katherine Johnson", subject: "Trajectory figures attached", time: "Mon"),
        MailMessage(id: 6, from: "Claude Shannon", subject: "Juggling robot, part II", time: "Sun"),
    ]
    var selection: Int? = 0
    private var history: [(messages: [MailMessage], selection: Int?)] = []

    var canUndo: Bool { !history.isEmpty }
    var selected: MailMessage? { messages.first { $0.id == selection } ?? messages.first }

    private func change(_ edit: (inout [MailMessage]) -> Void) {
        history.append((messages, selection))
        withAnimation(.easeInOut(duration: 0.25)) { edit(&messages) }
    }

    private func editSelected(_ edit: @escaping (inout MailMessage) -> Void) {
        guard let id = selection else { return }
        change { list in
            if let index = list.firstIndex(where: { $0.id == id }) { edit(&list[index]) }
        }
    }

    func flagSelected(_ colour: Color) { editSelected { $0.flag = colour } }
    func markSelectedUnread() { editSelected { $0.unread = true } }
    func archiveSelected() { if let id = selection { archive(id) } }

    func archive(_ id: Int) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change { $0.remove(at: index) }
        if selection == id { selection = messages[min(index, messages.count - 1)].id }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.25)) { messages = last.messages }
        selection = last.selection
    }
}

/// A mailbox: the messages, the selected one's text beside them.
struct Mailbox: View {
    @Bindable var store: MailStore

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            List(store.messages, selection: $store.selection) { message in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        Text(verbatim: message.unread ? "●" : " ").foregroundStyle(.palette.accent)
                        Text(verbatim: message.from).bold()
                        Spacer()
                        if let flag = message.flag { Text(verbatim: "⚑").foregroundStyle(flag) }
                        Text(verbatim: message.time).foregroundStyle(.palette.foregroundTertiary)
                    }
                    Text(verbatim: "  " + message.subject).foregroundStyle(.palette.foregroundSecondary)
                }
                .contextMenu {
                    Button("Reply") {}
                    Button("Forward") {}
                    Button("Archive") { store.archive(message.id) }
                    Divider()
                    Button("Delete", role: .destructive) { store.archive(message.id) }
                }
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                if let message = store.selected {
                    Text(verbatim: message.subject).bold()
                    Text(verbatim: "From \(message.from) · \(message.time)").foregroundStyle(.palette.foregroundSecondary)
                    Text(verbatim: "Dear colleague, the figures you asked for are attached, with my notes on the "
                         + "method. Shall we go through them together this week?")
                }
            }
            .padding(.horizontal, 1)
        }
        .padding(.horizontal, 1)
    }
}
