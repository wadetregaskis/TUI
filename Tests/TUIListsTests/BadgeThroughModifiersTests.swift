//  🖥️ TUI — A Terminal UI framework for Swift
//  BadgeThroughModifiersTests.swift
//
//  A `List` row's `.badge(_:)` with a modifier written after it is still the
//  row's badge (decisions B-LISTS-1): measured on macOS 15.8,
//  `.badge(5).padding(.leading, 0)` draws its badge, and a prominence written
//  around the padding reaches it (`Tools/SwiftUIProbes/Badge
//  prominence/badgeprom.swift`). Until 2026-11-08 only environment writes were
//  read through, and any other modifier after the badge drew the row without one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("A row's badge under modifiers")
struct BadgeThroughModifiersTests {
    private let palette = SystemPalette.green

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = palette
        // No capsule round a badge, so its ink is read plain.
        environment.controlStyle = .blank
        return RenderContext(
            availableWidth: 30, availableHeight: 6, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// The line of `list`'s row `name`, raw.
    private func row(_ name: String, in list: some View) -> String {
        renderToBuffer(list, context: context()).lines.first { $0.stripped.contains(name) } ?? ""
    }

    /// The badge's text, drawn in `ink` exactly as the list draws it.
    private func badge(in ink: Color) -> String {
        ANSIRenderer.colorize("12", foreground: ink.opaqueSpelling)
    }

    @Test("A badge with a padding, a style or a gesture after it is drawn")
    func badgeUnderModifiers() {
        let list = List {
            Text("Pad").badge(12).padding(.leading, 0)
            Text("Ink").badge(12).foregroundStyle(.red)
            Text("Tap").badge(12).onTapGesture {}
            Text("Two").badge(12).padding(.leading, 0).onTapGesture {}
        }
        for name in ["Pad", "Ink", "Tap", "Two"] {
            let line = row(name, in: list)
            #expect(line.stripped.contains(" 12"), "\(name): \(line.stripped.debugDescription)")
        }
    }

    @Test("A looped row's badge under a padding is drawn", arguments: [false, true])
    func loopedBadgeUnderPadding(listOfData: Bool) {
        let names = ["Alpha", "Beta"]
        let line: String
        if listOfData {
            line = row("Beta", in: List(names, id: \.self) { Text($0).badge(12).padding(.leading, 0) })
        } else {
            line = row("Beta", in: List { ForEach(names, id: \.self) { Text($0).badge(12).padding(.leading, 0) } })
        }
        #expect(line.stripped.contains(" 12"), "\(line.stripped.debugDescription)")
    }

    @Test("A prominence written around the padding after a badge reaches it, as measured")
    func prominenceAroundThePadding() {
        let list = List {
            Text("Quiet").badge(12).padding(.leading, 0).badgeProminence(.decreased)
            Text("Plain").badge(12).padding(.leading, 0)
        }
        let quiet = row("Quiet", in: list)
        #expect(quiet.contains(badge(in: palette.foregroundQuaternary)), "\(quiet.debugDescription)")
        let plain = row("Plain", in: list)
        #expect(plain.contains(badge(in: palette.foregroundTertiary)), "\(plain.debugDescription)")
    }

    @Test("The prominence nearest the badge wins")
    func nearestProminenceWins() {
        let line = row(
            "Near",
            in: List {
                Text("Near").badge(12).badgeProminence(.decreased).padding(.leading, 0).badgeProminence(.standard)
            })
        #expect(line.contains(badge(in: palette.foregroundQuaternary)), "\(line.debugDescription)")
    }

    @Test("The type gate sees a badge through wrappers, and nothing where there is none")
    func typeGate() {
        func carries<V: View>(_: V) -> Bool { viewTypeCarriesBadge(V.self) }
        #expect(carries(Text("a").badge(1).padding().foregroundStyle(.red)))
        #expect(!carries(Text("a").padding().foregroundStyle(.red)))
        #expect(!carries(Text("a")))
    }
}
