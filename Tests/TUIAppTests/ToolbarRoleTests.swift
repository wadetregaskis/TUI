//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarRoleTests.swift
//
//  `.toolbarRole(_:)`: under `.editor` the top bar keeps the title at its
//  leading end beside principal items; under `.automatic` a principal item
//  takes the title's place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// The role the probe page states, reachable from an `App`.
private final class Role: @unchecked Sendable {
    static let shared = Role()
    var role: ToolbarRole?
    var principal = true
}

/// A titled page with a principal item, its role stated from outside.
private struct RoleApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            if let role = Role.shared.role {
                page.toolbarRole(role)
            } else {
                page
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }

    private var page: some View {
        Text("PAGE")
            .navigationTitle("DOC")
            .toolbar {
                if Role.shared.principal {
                    ToolbarItem(placement: .principal) { Text("MID") }
                }
                ToolbarItem(placement: .primaryAction) { Text("END") }
            }
    }
}

@MainActor
@Suite("Toolbar role", .serialized)
struct ToolbarRoleTests {

    private func reset() {
        Role.shared.role = nil
        Role.shared.principal = true
    }

    /// The top bar's row, two frames in: one to declare, one to draw.
    private func topRow() -> String {
        let app = TestApp(RoleApp(), width: 40, height: 6)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen.styledLines.first?.stripped ?? ""
    }

    @Test("By default a principal item takes the title's place")
    func automaticGivesTheTitleAway() {
        reset()
        defer { reset() }
        let row = topRow()
        #expect(row.contains("MID") && row.contains("END"), "\(row)")
        #expect(!row.contains("DOC"), "\(row)")
        Role.shared.role = .automatic
        #expect(!topRow().contains("DOC"))
    }

    @Test("Under the editor role the title stays at the leading end, beside the principal item")
    func editorKeepsTheTitle() {
        reset()
        defer { reset() }
        Role.shared.role = .editor
        let row = topRow()
        let doc = row.range(of: "DOC")
        let mid = row.range(of: "MID")
        #expect(doc != nil && mid != nil, "\(row)")
        if let doc, let mid { #expect(doc.lowerBound < mid.lowerBound, "\(row)") }
        #expect(row.hasPrefix("DOC"), "at the leading end: \(row)")
    }

    @Test("With nothing principal the roles draw the same bar")
    func nothingPrincipal() {
        reset()
        defer { reset() }
        Role.shared.principal = false
        let automatic = topRow()
        Role.shared.role = .editor
        #expect(topRow() == automatic)
        #expect(automatic.contains("DOC"), "\(automatic)")
    }
}
