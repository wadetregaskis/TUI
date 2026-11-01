//  🖥️ TUI — A Terminal UI framework for Swift
//  InspectorToggleTests.swift
//
//  An inspector's toggles: the ▶ on the divider before it, which hides it, and
//  the button a `DefaultToolbarItem(kind: .inspectorToggle)` puts in a bar —
//  opt-in, as SwiftUI puts no inspector button in a toolbar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUINavigation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// Whether an inspector shows, by reference so the binding a frame built
/// reaches it. Each app has its own, so suites running side by side share
/// nothing.
private final class Presented: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
    var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

/// Where a page declares its inspector button.
private enum Arrangement {
    /// Round the view the inspector modifies.
    case aroundInspector
    /// In the view the inspector modifies.
    case inContent
    /// Round it, with the inspector's toggle removed.
    case removed
    /// No button: only an item of the page's in the top bar.
    case none
}

private struct Page: View {
    let arrangement: Arrangement
    let presented: Presented

    var body: some View {
        switch arrangement {
        case .aroundInspector:
            Text("EDITOR")
                .inspector(isPresented: presented.binding) { Text("TRAITS") }
                .toolbar { DefaultToolbarItem(kind: .inspectorToggle, placement: .primaryAction) }
        case .inContent:
            Text("EDITOR")
                .toolbar { DefaultToolbarItem(kind: .inspectorToggle, placement: .primaryAction) }
                .inspector(isPresented: presented.binding) { Text("TRAITS") }
        case .removed:
            Text("EDITOR")
                .inspector(isPresented: presented.binding) { Text("TRAITS") }
                .toolbar {
                    DefaultToolbarItem(kind: .inspectorToggle, placement: .primaryAction)
                    ToolbarItem(placement: .navigation) { Text("ITEM") }
                }
                .toolbar(removing: .inspectorToggle)
        case .none:
            Text("EDITOR")
                .inspector(isPresented: presented.binding) { Text("TRAITS") }
                .toolbar { ToolbarItem(placement: .primaryAction) { Text("ITEM") } }
        }
    }
}

private struct AroundApp: App {
    static let presented = Presented(true)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .aroundInspector, presented: Self.presented) } }
}

private struct InContentApp: App {
    static let presented = Presented(true)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .inContent, presented: Self.presented) } }
}

private struct RemovedApp: App {
    static let presented = Presented(true)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .removed, presented: Self.presented) } }
}

private struct NoButtonApp: App {
    static let presented = Presented(true)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .none, presented: Self.presented) } }
}

private struct DividerApp: App {
    static let presented = Presented(true)
    init() {}
    var body: some Scene { WindowGroup { Page(arrangement: .none, presented: Self.presented) } }
}

@MainActor
@Suite("An inspector's toggles", .rendersEnglishUI)
struct InspectorToggleTests {
    /// `app` after five frames: a bar is adopted a frame or two after its items
    /// are first declared.
    private func running<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 60, height: 12)
        for index in 1...5 { headless.frame(atNanos: Int64(index) * 16_666_667) }
        return headless
    }

    private func settle(_ app: TestApp, from frame: Int) {
        for index in frame...(frame + 1) { app.frame(atNanos: Int64(index) * 16_666_667) }
    }

    private func rows(_ app: TestApp) -> [String] {
        app.screen.lines
    }

    /// The row and column of the first `text` on screen at or after `row`.
    private func position(
        of text: String, in app: TestApp, from start: Int = 0
    ) -> (row: Int, column: Int)? {
        let screen = rows(app)
        guard let row = screen.indices.first(where: { $0 >= start && screen[$0].contains(text) }),
            let range = screen[row].range(of: text)
        else { return nil }
        return (row, screen[row].distance(from: screen[row].startIndex, to: range.lowerBound))
    }

    private func click(_ app: TestApp, at point: (row: Int, column: Int)) {
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: point.column, y: point.row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: point.column, y: point.row))
    }

    @Test("The divider before a shown inspector carries a ▶ that hides it")
    func dividerHides() throws {
        DividerApp.presented.value = true
        let app = running(DividerApp())
        let screen = rows(app)
        let editor = try #require(position(of: "EDITOR", in: app), "\(screen)")
        let arrow = try #require(position(of: "▶", in: app, from: editor.row), "\(screen)")
        let traits = try #require(position(of: "TRAITS", in: app), "\(screen)")
        #expect(arrow.column < traits.column, "the ▶ is on the divider, before the inspector: \(screen)")
        click(app, at: arrow)
        settle(app, from: 6)
        #expect(DividerApp.presented.value == false)
        #expect(position(of: "TRAITS", in: app) == nil, "\(rows(app))")
    }

    @Test("Declared round the inspector, the bar's button shows ▶, hides it, and turns to ◀")
    func aroundTheInspector() throws {
        AroundApp.presented.value = true
        let app = running(AroundApp())
        let screen = rows(app)
        let editor = try #require(position(of: "EDITOR", in: app), "\(screen)")
        let button = try #require(position(of: "▶", in: app), "\(screen)")
        #expect(button.row < editor.row, "the bar's: \(screen)")
        click(app, at: button)
        settle(app, from: 6)
        #expect(AroundApp.presented.value == false)
        let back = try #require(position(of: "◀", in: app), "\(rows(app))")
        #expect(back.row < editor.row)
        click(app, at: back)
        settle(app, from: 8)
        #expect(AroundApp.presented.value == true)
    }

    @Test("Declared in the view the inspector modifies, it toggles that inspector")
    func inTheContent() throws {
        InContentApp.presented.value = true
        let app = running(InContentApp())
        let editor = try #require(position(of: "EDITOR", in: app), "\(rows(app))")
        let button = try #require(
            rows(app).indices.first { $0 < editor.row && rows(app)[$0].contains("▶") }, "\(rows(app))")
        let line = rows(app)[button]
        click(app, at: (button, line.distance(from: line.startIndex, to: line.range(of: "▶")!.lowerBound)))
        settle(app, from: 6)
        #expect(InContentApp.presented.value == false)
    }

    @Test("toolbar(removing: .inspectorToggle) takes the divider's ▶ and the bar's button away")
    func removed() throws {
        RemovedApp.presented.value = true
        let app = running(RemovedApp())
        let screen = rows(app)
        #expect(position(of: "ITEM", in: app) != nil, "the bar is there: \(screen)")
        #expect(position(of: "TRAITS", in: app) != nil, "\(screen)")
        #expect(!screen.contains { $0.contains("▶") || $0.contains("◀") }, "\(screen)")
    }

    /// The bar measures its inspector button before the inspector has
    /// registered its toggle with the window, and again after, in one pass:
    /// the first measure finds no toggle and is 0 × 0. The per-pass measure
    /// memo served that to the second until the button's read of the window's
    /// chrome declared itself unkeyed. The measure verifier is the oracle: it
    /// re-measures every served size and lists each that disagrees.
    @Test("The bar's inspector button is never served a size measured before its inspector registered")
    func toggleSizeIsNotServedAcrossRegistration() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = true
        AroundApp.presented.value = true
        let app = TestApp(AroundApp(), width: 60, height: 12)
        for index in 1...3 { app.frame(atNanos: Int64(index) * 16_666_667) }
        #expect(app.renderCache.measureMemoMismatches.isEmpty, "\(app.renderCache.measureMemoMismatches)")
    }

    @Test("Without a placed item the bar has no inspector button: it is opt-in")
    func optIn() throws {
        NoButtonApp.presented.value = true
        let app = running(NoButtonApp())
        let screen = rows(app)
        let editor = try #require(position(of: "EDITOR", in: app), "\(screen)")
        #expect(!screen[..<editor.row].contains { $0.contains("▶") || $0.contains("◀") }, "\(screen)")
    }
}
