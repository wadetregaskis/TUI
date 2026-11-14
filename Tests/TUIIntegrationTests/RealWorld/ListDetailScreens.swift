//  🖥️ TUI — A Terminal UI framework for Swift
//  ListDetailScreens.swift
//
//  Real-world screens: a list beside its detail. A List in a NavigationSplitView's
//  sidebar choosing what its detail shows, a long sidebar whose last row must
//  be reachable, and three columns. The detail must follow the selection, and
//  the columns must not overlap or leave the screen at any size.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private struct Contact: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String { "Contact \(id)" }
    var phone: String { "555-01\(id < 10 ? "0" : "")\(id)" }
}

/// Contacts in a sidebar list, the chosen one's card in the detail.
private struct ContactsPage: View {
    let count: Int
    @State private var selection: Int?

    var body: some View {
        NavigationSplitView {
            List((1...count).map(Contact.init), selection: $selection) { contact in
                Text("#\(contact.id)")
            }
            .focusID("contacts")
        } detail: {
            if let selection {
                VStack(alignment: .leading) {
                    Text("Card of Contact \(selection)").bold()
                    Text("Phone: \(Contact(id: selection).phone)")
                    Button("Call") {}.focusID("call")
                }
            } else {
                Text("No contact chosen")
            }
        }
    }
}

/// Mailboxes, the messages in the chosen one, and the chosen message.
private struct MailPage: View {
    @State private var mailbox: String? = "Inbox"
    @State private var message: Int?

    var body: some View {
        NavigationSplitView {
            List(["Inbox", "Sent", "Archive"], id: \.self, selection: $mailbox) { Text($0) }
                .focusID("mailboxes")
        } content: {
            List(1...(mailbox == "Inbox" ? 30 : 4), id: \.self, selection: $message) { Text("M\($0)") }
                .focusID("messages")
        } detail: {
            Text(message.map { "Reading mail \($0)" } ?? "Nothing to read")
        }
    }
}

@MainActor
@Suite("Real world: a list beside its detail")
struct ListDetailScreens {
    @Test("Choosing a contact with Down shows its card in the detail", arguments: TerminalSize.all)
    func detailFollowsSelection(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { ContactsPage(count: 8) }
        LayoutSanity.check(app, "launch")
        for _ in 0..<4 where app.focusedID != "contacts" { app.press(.tab) }
        #expect(app.focusedID == "contacts")
        app.press(.down)
        app.press(.down)
        app.press(.enter)
        LayoutSanity.check(app, "a contact chosen")
        if size.width >= 40 {
            #expect(app.screen.contains("Card of"), "the detail does not show the card:\n\(app.screen)")
        }
    }

    @Test("A sidebar of 60 contacts: End reaches the last, the wheel too", arguments: TerminalSize.all)
    func longSidebar(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { ContactsPage(count: 60) }
        for _ in 0..<4 where app.focusedID != "contacts" { app.press(.tab) }
        LayoutSanity.reach("#60", in: app, by: .end, limit: 2)
        let wheeled = TestApp(width: size.width, height: size.height) { ContactsPage(count: 60) }
        LayoutSanity.reach("#60", in: wheeled, by: .wheelDown(over: "#1"), limit: 80)
    }

    @Test("Three columns: Tab reaches each, the long middle one scrolls to its end", arguments: TerminalSize.all)
    func threeColumns(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { MailPage() }
        LayoutSanity.check(app, "launch")
        var seen: Set<String> = []
        // At 20 columns the three columns' minimums are wider than the screen,
        // so the second divider and the detail lie past its right edge, and
        // Tab focuses the divider there. macOS hides the sidebar of a window
        // too narrow for its columns; this split does not yet.
        withKnownIssue("three columns wider than a 20-column screen put a divider off it") {
            for step in 0..<6 {
                if let focused = app.focusedID { seen.insert(focused) }
                app.press(.tab)
                LayoutSanity.check(app, "Tab ×\(step + 1)")
            }
        } when: {
            size.width < 40
        }
        #expect(seen.isSuperset(of: ["mailboxes", "messages"]), "Tab visited only \(seen.sorted())")
        for _ in 0..<6 where app.focusedID != "messages" { app.press(.tab) }
        LayoutSanity.reach("M30", in: app, by: .end, limit: 2)
    }
}
