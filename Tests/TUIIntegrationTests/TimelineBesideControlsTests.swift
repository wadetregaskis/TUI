//  🖥️ TUI — A Terminal UI framework for Swift
//  TimelineBesideControlsTests.swift
//
//  A `List` and a `Button` beside a running `TimelineView` are not drawn
//  again at each of its entries when nothing they read changed: the list does
//  not list its rows again, a button's style does not make its body again.
//  SwiftUI runs the timeline's content alone; tuiarcade measured TUI drawing
//  both controls whole at every entry (TUI-FEEDBACK.md, M2 item 3).
//
//  Counted, not compared: a picture served and one drawn again look the same.
//  `listed` is the row boxes a `List` made, which it makes each time it draws.
//
//  A control that holds the focus is still drawn at each entry: its
//  registration declines every memo around it (see "Framework controls beside
//  a live timeline" in Documentation/Historical/Performance). These tests put
//  the focus on the other control, and check that the focused one still works.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing
import TUI
import TUIApp
import TUITesting
import TUIView

/// The bodies the counting style made, by button title. A global, not a
/// capture, so no view holds anything that would make it compare unequal.
@MainActor private var styleBodies: [String: Int] = [:]

/// A plain style that counts the bodies it makes. `Equatable`, as a style
/// must be for the environment it is set in to be compared at all.
private struct CountingStyle: ButtonStyle, Equatable {
    let title: String

    func makeBody(configuration: Configuration) -> some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = styleBodies[title, default: 0] += 1
        configuration.label
    }
}

/// What the page's list is drawn with, written by a test.
@MainActor
@Observable
private final class Look {
    var isRed = false
    var isDisabled = false
}

/// A 60 Hz timeline whose content reads its date, as a game loop's does.
private struct Loop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Color.clear.onChange(of: timeline.date) { _, _ in }
        }
        .frame(width: 1, height: 1)
    }
}

/// The timeline beside two buttons and a list, all in the one body that
/// holds the timeline: no view of the app's own stands between them and the
/// walk an entry makes, whose memo would serve them anyway. Whichever control
/// comes first takes the focus as the page opens.
private struct Page: View {
    let listFirst: Bool
    let look: Look
    @State private var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Loop()
            if listFirst { rows }
            Button("First") {}.buttonStyle(CountingStyle(title: "First"))
            Button("Second") {}.buttonStyle(CountingStyle(title: "Second"))
            if !listFirst { rows }
        }
    }

    private var rows: some View {
        List([0, 1], id: \.self, selection: $selection) { index in
            Text(verbatim: selection == index ? "row \(index) chosen" : "row \(index)")
        }
        .foregroundStyle(look.isRed ? Color.red : Color.green)
        .disabled(look.isDisabled)
        .frame(width: 24, height: 4)
    }
}

@MainActor
@Suite("A control beside a running timeline is not drawn at its entries", .serialized)
struct TimelineBesideControlsTests {
    /// A settled page: its first frames drawn, and those in which the walk
    /// learns where the live timelines are.
    private func page(listFirst: Bool, look: Look = Look()) -> TestApp {
        styleBodies = [:]
        let app = TestApp(width: 30, height: 8) { Page(listFirst: listFirst, look: look) }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        return app
    }

    @Test("A list that does not hold the focus lists no rows at the timeline's entries")
    func unfocusedListServed() {
        let app = page(listFirst: false)
        #expect(app.screen.contains("row 1"))
        let listed = app.headless.renderCache.rowWork.listed
        app.advance(by: .seconds(1))
        let more = app.headless.renderCache.rowWork.listed - listed
        #expect(more == 0, "60 entries; the list read nothing that moved, and listed \(more) rows")
    }

    @Test("A button that does not hold the focus makes no style body at the timeline's entries")
    func unfocusedButtonsServed() {
        let app = page(listFirst: true)
        #expect(app.screen.contains("Second"))
        let before = styleBodies
        app.advance(by: .seconds(1))
        #expect(styleBodies["First"] == before["First"], "\(before) -> \(styleBodies)")
        #expect(styleBodies["Second"] == before["Second"], "\(before) -> \(styleBodies)")
    }

    @Test("The focused list beside a running timeline still moves its cursor and selects")
    func focusedListStillWorks() {
        let app = page(listFirst: true)
        #expect(app.press(.down))
        app.advance(by: .milliseconds(50))
        #expect(app.press(.space))
        app.advance(by: .milliseconds(200))
        #expect(app.screen.contains("row 1 chosen"))
        // And the focus leaves it, and comes back, with the timeline running.
        #expect(app.press(.tab))
        app.advance(by: .milliseconds(200))
        #expect(app.press(.tab, modifiers: .shift))
        app.advance(by: .milliseconds(50))
        #expect(app.press(.up))
        #expect(app.press(.space))
        app.advance(by: .milliseconds(200))
        #expect(app.screen.contains("row 0 chosen"))
    }

    @Test("A served list still takes a new foreground style and .disabled() from above")
    func servedListTakesTheEnvironment() {
        let look = Look()
        let app = page(listFirst: false, look: look)
        app.advance(by: .milliseconds(200))
        let row = { app.headless.screen.first { $0.stripped.contains("row 1") } ?? "" }
        let plain = row()
        look.isRed = true
        app.advance(by: .milliseconds(200))
        #expect(row().stripped == plain.stripped)
        #expect(row() != plain, "the row is drawn in the new colour: \(row().debugDescription)")
        // Disabled, the list leaves the ring: Tab goes from the first button
        // to the second and back round to the first, never to the list.
        look.isDisabled = true
        app.advance(by: .milliseconds(200))
        let first = app.headless.focusedID
        #expect(app.press(.tab))
        #expect(app.press(.tab))
        app.advance(by: .milliseconds(50))
        #expect(app.headless.focusedID == first, "two Tabs over two buttons come back to the first")
    }
}
