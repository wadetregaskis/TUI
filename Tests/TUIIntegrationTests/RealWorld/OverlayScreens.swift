//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlayScreens.swift
//
//  Real-world screens: what floats over a page. An alert over a busy page of
//  a table and a form, a confirmation dialog over a list, a popover from a
//  button in the bottom-right corner, and menus opened at the right edge and
//  the bottom. Each must lie on the screen, take the focus, and give it back
//  to the control that raised it when it goes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private struct Order: Identifiable, Sendable {
    let id: Int
    var title: String { "Order #\(1_000 + id)" }
    var total: String { "$\(id * 13).00" }
}

/// A table of orders, a note field, and a Delete All that asks first.
private struct OrdersPage: View {
    @State private var asksToDelete = false
    @State private var note = ""
    @State private var deleted = false

    var body: some View {
        VStack(alignment: .leading) {
            Table((1...20).map(Order.init)) {
                TableColumn("Order", value: \Order.title)
                TableColumn("Total", value: \Order.total)
            }
            .focusID("orders")
            TextField("Note", text: $note).focusID("note")
            Button(deleted ? "Deleted" : "Delete All…") { asksToDelete = true }.focusID("delete-all")
        }
        .alert("Delete all orders?", isPresented: $asksToDelete) {
            Button("Delete", role: .destructive) { deleted = true }.focusID("confirm")
            Button("Cancel", role: .cancel) {}.focusID("cancel")
        } message: {
            Text("This cannot be undone.")
        }
    }
}

/// A list of tracks, and a Remove button that asks how.
private struct TracksPage: View {
    @State private var asks = false

    var body: some View {
        VStack(alignment: .leading) {
            List(1...30, id: \.self) { Text("Track \($0)") }.focusID("tracks")
            Button("Remove…") { asks = true }.focusID("remove")
                .confirmationDialog("Remove the track?", isPresented: $asks) {
                    Button("Remove from Library", role: .destructive) {}
                    Button("Remove Download") {}
                }
        }
    }
}

/// A button pinned to the bottom-right corner, with a popover of filters.
private struct CornerPopoverPage: View {
    @State private var showsFilters = false
    @State private var unread = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button("Filters") { showsFilters = true }.focusID("filters")
                    .popover(isPresented: $showsFilters) {
                        VStack(alignment: .leading) {
                            Text("Filter the inbox by")
                            Toggle("Unread only", isOn: $unread).focusID("unread")
                        }
                    }
            }
        }
    }
}

/// A Menu at the right end of a top bar, and a menu Picker at the bottom.
private struct EdgeMenusPage: View {
    @State private var sort = "Name"

    var body: some View {
        VStack {
            HStack {
                Text("Projects")
                Spacer()
                Menu("Actions") {
                    Button("Duplicate Project") {}
                    Button("Archive Project") {}
                    Divider()
                    Button("Delete Project", role: .destructive) {}
                }
            }
            Spacer()
            Picker("Sort by", selection: $sort) {
                ForEach(["Name", "Date Modified", "Size", "Kind"], id: \.self) { Text($0) }
            }
            .focusID("sort")
            .pickerStyle(.menu)
        }
    }
}

@MainActor
@Suite("Real world: alerts, dialogs, popovers and menus")
struct OverlayScreens {
    @Test("An alert over a busy page: on screen, focused, and Cancel gives the focus back",
          arguments: TerminalSize.all)
    func alertOverBusyPage(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { OrdersPage() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<5 where app.focusedID != "delete-all" { app.press(.tab) }
        #expect(app.focusedID == "delete-all")
        app.press(.enter)
        LayoutSanity.check(app, "the alert up")
        #expect(["confirm", "cancel"].contains(app.focusedID), "the alert has no focus: \(app.focusedID ?? "none")")
        if size.width >= 40 { LayoutSanity.expectNotSilentlyCut(app, "Delete all orders?", "the alert's title") }
        app.press(.escape)
        LayoutSanity.check(app, "the alert gone")
        #expect(app.focusedID == "delete-all", "the focus did not come back: \(app.focusedID ?? "none")")
    }

    @Test("A confirmation dialog over a scrolled list: on screen, and it gives the focus back",
          arguments: TerminalSize.all)
    func confirmationOverList(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { TracksPage() }
        LayoutSanity.check(app, "launch")
        app.scroll(.down, by: 5, at: CellPoint(x: 2, y: 1))
        for _ in 0..<4 where app.focusedID != "remove" { app.press(.tab) }
        #expect(app.focusedID == "remove")
        app.press(.enter)
        LayoutSanity.check(app, "the dialog up")
        if size.width >= 40 { LayoutSanity.expectNotSilentlyCut(app, "Remove from Library", "the first action") }
        app.press(.escape)
        LayoutSanity.check(app, "the dialog gone")
        #expect(app.focusedID == "remove", "the focus did not come back: \(app.focusedID ?? "none")")
    }

    @Test("A popover from the bottom-right corner lies on the screen and takes the focus",
          arguments: TerminalSize.all)
    func cornerPopover(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { CornerPopoverPage() }
        for _ in 0..<3 where app.focusedID != "filters" { app.press(.tab) }
        #expect(app.focusedID == "filters")
        app.press(.enter)
        LayoutSanity.check(app, "the popover up")
        // A popover leaves the focus until a first key finds its content
        // ("Dialogs and pickers", decisions B14): Tab is that key.
        app.press(.tab)
        LayoutSanity.check(app, "Tab into the popover")
        #expect(app.focusedID == "unread", "Tab did not reach the popover's toggle: \(app.focusedID ?? "none")")
        if size.width >= 40 { LayoutSanity.expectNotSilentlyCut(app, "Unread only", "the toggle") }
        app.press(.escape)
        LayoutSanity.check(app, "the popover gone")
    }

    @Test("A menu at the right edge and a menu picker at the bottom open on the screen",
          arguments: TerminalSize.all)
    func edgeMenus(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { EdgeMenusPage() }
        LayoutSanity.focus("Actio", in: app)
        app.press(.enter)
        LayoutSanity.check(app, "the menu open")
        if size.width >= 40 { LayoutSanity.expectNotSilentlyCut(app, "Duplicate Project", "the first item") }
        app.press(.escape)
        LayoutSanity.check(app, "the menu closed")
        for _ in 0..<3 where app.focusedID != "sort" { app.press(.tab) }
        #expect(app.focusedID == "sort")
        app.press(.enter)
        LayoutSanity.check(app, "the picker open")
        if size.height >= 12 { LayoutSanity.expectNotSilentlyCut(app, "Date Modified", "an option") }
        app.press(.escape)
        LayoutSanity.check(app, "the picker closed")
    }
}
