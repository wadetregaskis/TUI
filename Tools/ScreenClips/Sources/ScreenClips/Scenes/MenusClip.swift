//  🖥️ TUI — A Terminal UI framework for Swift
//  MenusClip.swift
//
//  `menus`: a mail app's menu bar opened from the keyboard — File, across to
//  Message, into Flag — which flags a message; a message's context menu,
//  which archives it out of the list; and Edit ▸ Undo, twice, by its
//  shortcut, which puts both back. Each chord is captioned as it is pressed,
//  each change is animated — the flag fades in, an archived row fades and
//  closes up, an undone one fades back — and a toast says what happened.
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

/// A key, captioned as it is pressed: the chord and what it does, for a viewer
/// who cannot see the keyboard.
private func key(_ step: Step, _ caption: String) -> [Step] {
    [.cue("key \(caption)"), step]
}

private func menusScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 52, height: 15)), .wait(0.9)]
    // The menu bar: F10 lights the app menu's title, → moves to File and ↓
    // opens it, across Edit to Message, down to Flag, and into it: the first
    // message is flagged red.
    script += key(.f10, "F10  menu bar") + [.wait(0.8)]
    script += key(.right, "→  next title") + [.wait(0.6)]
    script += key(.down, "↓  open") + [.wait(0.6), .down, .wait(0.35), .down, .wait(0.5)]
    script += [.right, .wait(0.6), .right, .wait(0.6)]
    script += [.cue("key ↓  down the menu")] + Step.repeat(.down, 4, interval: 0.35)
    script += [.wait(0.3)] + key(.right, "→  into Flag") + [.wait(0.8)]
    script += key(.enter, "⏎  Red") + [.wait(1.4)]
    // A message's context menu, from the keyboard (Shift+F10): Archive, and
    // it leaves the list.
    script += [.cue("clear"), .down, .wait(0.4), .down, .wait(0.5)]
    script += key(.shiftF10, "⇧F10  context menu") + [.wait(0.8), .down, .wait(0.35), .down, .wait(0.7)]
    script += key(.enter, "⏎  Archive") + [.wait(1.8)]
    // Edit ▸ Undo, twice from its shortcut: the message comes back, then the
    // flag goes, and the loop ends where it began, toast and caption gone.
    script += key(.control("z"), "⌃Z  undo") + [.wait(1.4)]
    script += key(.control("z"), "⌃Z  undo") + [.wait(1.0), .up, .wait(0.3), .up, .wait(0.6)]
    script += [.cue("clear"), .wait(0.9)]
    return script
}

struct MenusApp: App {
    @State private var store = MailStore()

    var body: some Scene {
        WindowGroup("TUI · Mail") {
            Mailbox(store: store)
                .palette(SystemPalette(.violet))
                .task {
                    for await cue in ClipCues.stream() {
                        withAnimation(.easeOut(duration: 0.15)) {
                            store.caption = cue.hasPrefix("key ") ? String(cue.dropFirst(4)) : nil
                            if cue == "clear" { store.toast = nil }
                        }
                    }
                }
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
    var flag: Color?
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
    /// What just happened, said in a toast at the foot of the window.
    var toast: String?
    /// The chord last pressed and what it does, captioned until the next.
    var caption: String?
    /// The message fading out of the list as it is archived.
    var leaving: Int?
    /// Each change's state before it, and what its undo says.
    private var history: [(messages: [MailMessage], selection: Int?, undone: String)] = []

    var canUndo: Bool { !history.isEmpty }
    var selected: MailMessage? { messages.first { $0.id == selection } ?? messages.first }

    private func change(_ said: String, undone: String, _ edit: (inout [MailMessage]) -> Void) {
        history.append((messages, selection, undone))
        withAnimation(.easeInOut(duration: 0.35)) {
            edit(&messages)
            toast = said
        }
    }

    private func editSelected(
        _ said: String, undone: (MailMessage) -> String, _ edit: @escaping (inout MailMessage) -> Void
    ) {
        guard let id = selection, let message = messages.first(where: { $0.id == id }) else { return }
        change(said, undone: undone(message)) { list in
            if let index = list.firstIndex(where: { $0.id == id }) { edit(&list[index]) }
        }
    }

    func flagSelected(_ colour: Color) {
        editSelected("Flagged", undone: { "Unflagged “\($0.subject)”" }) { $0.flag = colour }
    }

    func markSelectedUnread() {
        editSelected("Marked as unread", undone: { "Marked “\($0.subject)” as read" }) { $0.unread = true }
    }
    func archiveSelected() { if let id = selection { archive(id) } }

    /// Fades `id` out where it is, then takes it out of the list, so the eye
    /// sees which row went before the rows close up.
    func archive(_ id: Int) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        withAnimation(.easeIn(duration: 0.3)) { leaving = id }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
            change("Archived “\(message.subject)”", undone: "Unarchived “\(message.subject)” from \(message.from)") {
                $0.remove(at: index)
            }
            leaving = nil
            if selection == id { selection = messages[min(index, messages.count - 1)].id }
        }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            messages = last.messages
            toast = last.undone
        }
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
                        if let flag = message.flag {
                            Text(verbatim: "⚑").foregroundStyle(flag).transition(.opacity)
                        }
                        Text(verbatim: message.time).foregroundStyle(.palette.foregroundTertiary)
                    }
                    Text(verbatim: "  " + message.subject).foregroundStyle(.palette.foregroundSecondary)
                }
                .opacity(store.leaving == message.id ? 0 : 1)
                .transition(.opacity)
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
        // The camera's height (15), less the menu bar's row: the toast and the
        // caption sit at the foot of what is filmed, not of the window. At 15 the
        // foot was the row under the shot, and a toast of two lines showed only
        // its first.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 14, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 2) {
                if let toast = store.toast {
                    Text(verbatim: " \(toast) ")
                        .background(.regularMaterial)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if let caption = store.caption {
                    Text(verbatim: " \(caption) ")
                        .bold()
                        .foregroundStyle(.palette.background)
                        .background(.palette.accent)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 1)
            // The camera's width: the caption at the right of what is filmed.
            .frame(width: 52)
        }
        // Held at the top of the window, as the camera frames it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
