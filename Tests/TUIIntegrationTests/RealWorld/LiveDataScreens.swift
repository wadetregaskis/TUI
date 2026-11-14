//  🖥️ TUI — A Terminal UI framework for Swift
//  LiveDataScreens.swift
//
//  Real-world screens: data that changes under the focus. Rows inserted
//  above the focused row of a list, the focused row removed, rows appended to
//  a table scrolled to its end, and a button's section that disappears while
//  the button has the focus. The focus must stay on screen on a row that
//  still exists, and nothing may be left drawn where it was.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

@Observable @MainActor private final class Feed {
    var items: [Int] = Array(1...20)
    var selection: Int?
}

/// A list of feed items, the model changed from the test as a network would.
private struct FeedPage: View {
    let feed: Feed

    var body: some View {
        @Bindable var feed = feed
        VStack(alignment: .leading) {
            Text("\(feed.items.count) items")
            List(feed.items, id: \.self, selection: $feed.selection) { Text("Item \($0)") }.focusID("feed")
        }
    }
}

private struct Reading: Identifiable, Sendable {
    let id: Int
    var label: String { "Reading \(id)" }
    var value: String { "\(id * 3 % 17)°" }
}

@Observable @MainActor private final class Sensor {
    var readings = (1...15).map(Reading.init)
}

private struct SensorPage: View {
    let sensor: Sensor

    var body: some View {
        Table(sensor.readings) {
            TableColumn("When", value: \Reading.label)
            TableColumn("Value", value: \Reading.value)
        }
        .focusID("readings")
    }
}

@Observable @MainActor private final class Session { var signedIn = true }

/// A sign-out button in a section that goes when the session ends.
private struct SessionPage: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading) {
            Button("Help") {}.focusID("help")
            if session.signedIn {
                GroupBox("Account") {
                    Button("Sign Out") { session.signedIn = false }.focusID("sign-out")
                }
            }
            Button("Quit") {}.focusID("quit")
        }
    }
}

@MainActor
@Suite("Real world: data changing under the focus")
struct LiveDataScreens {
    @Test("Rows inserted above the chosen row keep it chosen and in sight", arguments: TerminalSize.all)
    func insertAbove(size: TerminalSize) {
        let feed = Feed()
        let app = TestApp(width: size.width, height: size.height) { FeedPage(feed: feed) }
        for _ in 0..<3 where app.focusedID != "feed" { app.press(.tab) }
        #expect(app.focusedID == "feed")
        app.press(.down, times: 3)
        app.press(.space)
        let chosen = feed.selection
        #expect(chosen != nil, "Space chose nothing")
        feed.items.insert(contentsOf: (101...110).reversed(), at: 0)
        app.advance(by: .milliseconds(20))
        // The list stays at its top, where the new rows show, as a feed's
        // do: the wheel's rule, the focused row may be out of sight until a key.
        LayoutSanity.check(app, "ten rows inserted above", focusMustShow: false)
        #expect(feed.selection == chosen)
        app.press(.down)
        LayoutSanity.check(app, "Down")
        if let chosen {
            #expect(LayoutSanity.shows("Item \(chosen + 1)", in: app), "Down did not bring the cursor in sight:\n\(app.screen)")
        }
    }

    @Test("The chosen row removed: the focus stays on the list, on screen", arguments: TerminalSize.all)
    func removeChosen(size: TerminalSize) {
        let feed = Feed()
        let app = TestApp(width: size.width, height: size.height) { FeedPage(feed: feed) }
        for _ in 0..<3 where app.focusedID != "feed" { app.press(.tab) }
        app.press(.end)
        LayoutSanity.check(app, "End")
        feed.items.removeLast(5)
        app.advance(by: .milliseconds(20))
        LayoutSanity.check(app, "the last five removed")
        #expect(app.focusedID == "feed")
        #expect(app.screen.contains("Item 15"), "the new last row is not in sight:\n\(app.screen)")
        app.press(.up)
        LayoutSanity.check(app, "Up")
    }

    @Test("Rows appended to a table scrolled to its end: no blank rows, the new last row reachable",
          arguments: TerminalSize.all)
    func appendToTable(size: TerminalSize) {
        let sensor = Sensor()
        let app = TestApp(width: size.width, height: size.height) { SensorPage(sensor: sensor) }
        for _ in 0..<2 where app.focusedID != "readings" { app.press(.tab) }
        app.press(.end)
        for batch in 0..<3 {
            let first: Int = 16 + batch * 5
            sensor.readings.append(contentsOf: (first...first + 4).map(Reading.init))
            app.advance(by: .milliseconds(20))
            LayoutSanity.check(app, "batch \(batch + 1) appended")
        }
        app.press(.end)
        LayoutSanity.check(app, "End")
        // At 20×6 the table has room for one cut row.
        guard size.height >= 12 else { return }
        #expect(LayoutSanity.shows("Reading 30", in: app), "End fell short:\n\(app.screen)")
        LayoutSanity.expectContiguous(app, (26...30).map { "Reading \($0)" }, atLeast: 3, "the table's end")
    }

    @Test("A focused button's section removed: the focus moves to a control on screen", arguments: TerminalSize.all)
    func focusedSectionRemoved(size: TerminalSize) {
        let session = Session()
        let app = TestApp(width: size.width, height: size.height) { SessionPage(session: session) }
        for _ in 0..<3 where app.focusedID != "sign-out" { app.press(.tab) }
        #expect(app.focusedID == "sign-out")
        app.press(.enter)
        LayoutSanity.check(app, "signed out")
        #expect(!app.screen.contains("Sign Out"), "the section is still drawn:\n\(app.screen)")
        #expect(["help", "quit"].contains(app.focusedID), "the focus is \(app.focusedID ?? "nowhere")")
    }
}
