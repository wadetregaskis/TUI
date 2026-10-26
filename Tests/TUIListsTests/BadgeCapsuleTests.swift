//  🖥️ TUI — A Terminal UI framework for Swift
//  BadgeCapsuleTests.swift
//
//  A list row's `.standard` badge sits in a capsule in the control family —
//  a tinted field a cell wider each side under filled faces, the cap set's
//  line caps under lines — and a `.decreased` one stays plain (owner,
//  B72-CAPSULE (c), 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("A list badge's capsule")
struct BadgeCapsuleTests {
    private func context(width: Int = 30) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.palette = SystemPalette.green
        return RenderContext(
            availableWidth: width, availableHeight: 6, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// The raw line of the row drawing `name`.
    private func row(_ name: String, in list: some View, width: Int = 30) -> String {
        renderToBuffer(list, context: context(width: width)).lines.first { $0.stripped.contains(name) } ?? ""
    }

    private func inbox(_ prominence: BadgeProminence = .standard) -> some View {
        List {
            Text("Other")
            Text("Inbox").badge(12)
        }
        .badgeProminence(prominence)
    }

    @Test("Filled, the default: the badge on a field a cell wider each side")
    func filledField() {
        let line = row("Inbox", in: inbox())
        #expect(line.stripped.hasSuffix(" 12  │"), "\(line.stripped)")
        // The field is painted under the capsule's three cells, in one run.
        let run = line.components(separatedBy: " 12 ").first ?? ""
        #expect(run.hasSuffix("m") && run.split(separator: "\u{1B}").last?.contains("48;") == true,
                "\(line.debugDescription)")
    }

    @Test(".increased is drawn as .standard; .decreased stays plain text")
    func prominence() {
        #expect(row("Inbox", in: inbox(.increased)) == row("Inbox", in: inbox(.standard)))
        let quiet = row("Inbox", in: inbox(.decreased)).stripped
        #expect(quiet.hasSuffix(" 12 │") && !quiet.hasSuffix(" 12  │"), "\(quiet)")
    }

    @Test("Lines: the cap set's caps, in the button border shape in force")
    func lineCaps() {
        #expect(row("Inbox", in: inbox().controlStyle(.lines)).stripped.hasSuffix(" (12) │"))
        #expect(
            row("Inbox", in: inbox().controlStyle(.lines).buttonBorderShape(.roundedRectangle)).stripped
                .hasSuffix(" │12│ │"))
        #expect(row("Inbox", in: inbox().controlStyle(.blank)).stripped.hasSuffix(" 12 │"), "blank: no capsule")
    }

    @Test("A hugging list measures the capsule: the badged row keeps its whole title")
    func huggingMeasuresTheCapsule() {
        let list = List { Text("Inbox").badge(12) }.fixedSize(horizontal: true, vertical: false)
        for style in [ControlStyle.automatic, .lines] {
            let line = row("Inbox", in: list.controlStyle(style), width: 40).stripped
            #expect(line.contains("Inbox") && !line.contains("…"), "\(style): \(line)")
        }
    }

    @Test("Too narrow for both, the title truncates and the capsule survives whole")
    func narrowKeepsTheCapsule() {
        let line = row("In", in: List { Text("Inbox of many letters").badge(12) }, width: 16).stripped
        #expect(line.contains("…") && line.hasSuffix(" 12  │"), "\(line)")
    }
}
