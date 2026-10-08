//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BadgeProminenceTests.swift
//
//  `.badgeProminence(_:)`: a `List` draws its rows' badges in the ink the
//  prominence in its environment names — the palette's tertiary foreground for
//  `.standard` and `.increased` (as macOS 15.8 draws those two alike), its
//  quaternary for `.decreased`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Badge prominence")
struct BadgeProminenceTests {
    private let palette = SystemPalette.green

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        return RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// The badged row's raw line, in a list told `prominence` (or nothing).
    private func badgedRow(_ prominence: BadgeProminence?) -> String {
        let list = List {
            Text("Inbox").badge(12)
        }
        let lines: [String]
        if let prominence {
            lines = renderToBuffer(list.badgeProminence(prominence), context: context()).lines
        } else {
            lines = renderToBuffer(list, context: context()).lines
        }
        return lines.first { $0.stripped.contains("Inbox") } ?? ""
    }

    /// The badge's text, drawn in `ink` exactly as the list draws it.
    private func badge(in ink: Color) -> String {
        ANSIRenderer.colorize("12", foreground: ink.opaqueSpelling)
    }

    @Test("The two inks differ in the palette under test, or nothing here can fail")
    func inksDiffer() {
        #expect(badge(in: palette.foregroundTertiary) != badge(in: palette.foregroundQuaternary))
    }

    @Test("A badge draws in the tertiary foreground by default and at .standard")
    func standardIsTertiary() {
        for row in [badgedRow(nil), badgedRow(.standard)] {
            #expect(row.contains(badge(in: palette.foregroundTertiary)), "\(row.debugDescription)")
            #expect(!row.contains(badge(in: palette.foregroundQuaternary)), "\(row.debugDescription)")
        }
    }

    @Test("A .decreased badge draws in the quaternary foreground")
    func decreasedIsQuaternary() {
        let row = badgedRow(.decreased)
        #expect(row.contains(badge(in: palette.foregroundQuaternary)), "\(row.debugDescription)")
        #expect(!row.contains(badge(in: palette.foregroundTertiary)), "\(row.debugDescription)")
    }

    @Test("An .increased badge draws as a .standard one does, as measured on macOS 15.8")
    func increasedIsStandard() {
        #expect(badgedRow(.increased) == badgedRow(.standard))
    }

    @Test("The environment value defaults to .standard and reads back what was set")
    func environmentValue() {
        var environment = EnvironmentValues()
        #expect(environment.badgeProminence == .standard)
        environment.badgeProminence = .decreased
        #expect(environment.badgeProminence == .decreased)
        #expect(BadgeProminence.increased != .standard)
    }
}
