//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarLabelStyleTests.swift
//
//  `Scene.windowToolbarLabelStyle`: the window's bars draw their items' labels
//  in the style the scene states, which `\.toolbarLabelStyle` reads back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// The style the probe scene states, and what its page read, reachable from
/// an `App`.
private final class LabelProbe: @unchecked Sendable {
    static let shared = LabelProbe()
    var fixed: ToolbarLabelStyle?
    var bound: ToolbarLabelStyle?
    var read: ToolbarLabelStyle??
    var innerTitleOnly = false
}

/// A page reading the style, under a top bar holding a label.
private struct LabelPage: View {
    @Environment(\.toolbarLabelStyle) private var style

    var body: some View {
        LabelProbe.shared.read = .some(style)
        return Text("PAGE")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if LabelProbe.shared.innerTitleOnly {
                        Label(title: { Text("SAVE") }, icon: { Text("★") }).labelStyle(.titleOnly)
                    } else {
                        Label(title: { Text("SAVE") }, icon: { Text("★") })
                    }
                }
            }
    }
}

private struct FixedLabelApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { LabelPage() }
            .windowToolbarLabelStyle(fixed: LabelProbe.shared.fixed ?? .automatic)
            .windowToolbarStyle(.unifiedCompact)
    }
}

private struct BoundLabelApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { LabelPage() }
            .windowToolbarLabelStyle(
                Binding(get: { LabelProbe.shared.bound ?? .automatic }, set: { LabelProbe.shared.bound = $0 }))
            .windowToolbarStyle(.unifiedCompact)
    }
}

private struct UnstatedLabelApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { LabelPage() }
            .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Toolbar label style", .serialized)
struct ToolbarLabelStyleTests {

    private func reset() {
        LabelProbe.shared.fixed = nil
        LabelProbe.shared.bound = nil
        LabelProbe.shared.read = nil
        LabelProbe.shared.innerTitleOnly = false
    }

    /// The top bar's row, two frames in: one to declare, one to draw.
    private func topRow<A: App>(_ app: A) -> String {
        let app = HeadlessApp(app, width: 40, height: 5)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen.first?.stripped.trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("Icon only draws the labels' icons alone")
    func iconOnly() {
        reset()
        defer { reset() }
        let both = topRow(UnstatedLabelApp())
        #expect(both.contains("SAVE"), "\(both)")
        LabelProbe.shared.fixed = .iconOnly
        let icon = topRow(FixedLabelApp())
        #expect(!icon.contains("SAVE"), "\(icon)")
        #expect(!icon.isEmpty && both.hasPrefix(icon), "the icon, which leads the title and icon: \(icon) / \(both)")
        #expect(LabelProbe.shared.read == .some(.iconOnly), "\\.toolbarLabelStyle reads the scene's style")
    }

    @Test("Title only draws the labels' titles alone")
    func titleOnly() {
        reset()
        defer { reset() }
        LabelProbe.shared.fixed = .titleOnly
        #expect(topRow(FixedLabelApp()) == "SAVE")
    }

    @Test("A style the item states itself still wins")
    func itemStyleWins() {
        reset()
        defer { reset() }
        LabelProbe.shared.fixed = .iconOnly
        LabelProbe.shared.innerTitleOnly = true
        #expect(topRow(FixedLabelApp()) == "SAVE")
    }

    @Test("The bound form reads its binding")
    func bound() {
        reset()
        defer { reset() }
        LabelProbe.shared.bound = .titleOnly
        #expect(topRow(BoundLabelApp()) == "SAVE")
        #expect(LabelProbe.shared.read == .some(.titleOnly))
    }

    @Test("With no style stated the environment reads nil and the labels are as declared")
    func unstated() {
        reset()
        defer { reset() }
        let row = topRow(UnstatedLabelApp())
        #expect(row.contains("SAVE") && row.count > "SAVE".count, "\(row)")
        #expect(LabelProbe.shared.read == .some(nil))
    }
}
