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

@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

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

    /// The line of `list`'s row `name`.
    private func row(_ name: String, in list: some View) -> String {
        renderToBuffer(list, context: context()).lines.first { $0.stripped.contains(name) } ?? ""
    }

    /// Measured on macOS 15.8 (`Tools/SwiftUIProbes/Badge prominence/badgeprom.swift`):
    /// a prominence written around a row's `.badge(_:)` is the badge's, and
    /// one written inside it is not — the badge sees the environment where it
    /// is written, as any view does.
    @Test("A prominence written around a row's badge reaches it", arguments: [false, true])
    func aroundTheBadge(looped: Bool) {
        let list = List {
            Text("Plain").badge(12)
            if looped {
                ForEach(["Quiet"], id: \.self) { Text($0).badge(12).badgeProminence(.decreased) }
            } else {
                Text("Quiet").badge(12).badgeProminence(.decreased)
            }
        }
        let quiet = row("Quiet", in: list)
        #expect(quiet.contains(badge(in: palette.foregroundQuaternary)), "\(quiet.debugDescription)")
        let plain = row("Plain", in: list)
        #expect(plain.contains(badge(in: palette.foregroundTertiary)), "\(plain.debugDescription)")
    }

    @Test("A looped row's own prominence reaches its badge in a list of looped rows only")
    func aroundTheBadgeInALoop() {
        let list = List(["Quiet", "Loud"], id: \.self) { name in
            Text(name).badge(12).badgeProminence(name == "Quiet" ? .decreased : .standard)
        }
        let quiet = row("Quiet", in: list)
        #expect(quiet.contains(badge(in: palette.foregroundQuaternary)), "\(quiet.debugDescription)")
        let loud = row("Loud", in: list)
        #expect(loud.contains(badge(in: palette.foregroundTertiary)), "\(loud.debugDescription)")
    }

    @Test("A row's own prominence wins over the list's")
    func rowOverridesList() {
        let list = List {
            Text("Loud").badge(12).badgeProminence(.standard)
            Text("Quiet").badge(12)
        }
        .badgeProminence(.decreased)
        let loud = row("Loud", in: list)
        #expect(loud.contains(badge(in: palette.foregroundTertiary)), "\(loud.debugDescription)")
        let quiet = row("Quiet", in: list)
        #expect(quiet.contains(badge(in: palette.foregroundQuaternary)), "\(quiet.debugDescription)")
    }

    @Test("A prominence written inside a row's badge does not reach it, as measured")
    func withinTheBadge() {
        let within = row("Inbox", in: List { Text("Inbox").badgeProminence(.decreased).badge(12) })
        #expect(within.contains(badge(in: palette.foregroundTertiary)), "\(within.debugDescription)")
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
