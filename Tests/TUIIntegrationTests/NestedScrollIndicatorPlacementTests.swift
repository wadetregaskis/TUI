//  🖥️ TUI — A Terminal UI framework for Swift
//  NestedScrollIndicatorPlacementTests.swift
//
//  Scroll views inside scroll views, placed `.overContent` (the default): a
//  scroll view's indicators are beside its content while the focus is
//  anywhere inside it — on it, on a control in it, on a scroll view in it —
//  so moving the focus around inside it, by Tab or by the pointer, never
//  lays its content out again. Only entering it and leaving it do, once each.
//  The owner found the content jumping, and an inner scroll view moving out
//  from under the pointer, as the focus went in and out (2026-11-10).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

/// The widths each scroll view's content was laid out at, in order, a new
/// entry only when one changed.
@MainActor
private final class WidthLog {
    var outer: [Int] = []
    var inner: [Int] = []
}

/// Whether the sheet is up, outside the view.
@MainActor
private final class SheetFlag {
    var isUp = false
}

@MainActor
@Suite("A scroll view keeps its layout while the focus moves inside it")
struct NestedScrollIndicatorPlacementTests {
    private struct Page: View {
        let log: WidthLog

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("Before") {}.focusID("before")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Button("Top") {}.focusID("top")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Button("Inner A") {}.focusID("innerA")
                                Button("Inner B") {}.focusID("innerB")
                                ForEach(0..<12, id: \.self) { Text("inner line \($0)") }
                            }
                            .onGeometryChange(for: Int.self, of: { $0.size.width }, action: { log.inner.append($0) })
                        }
                        .focusID("inner")
                        .frame(height: 4)
                        Button("Bottom") {}.focusID("bottom")
                        ForEach(0..<20, id: \.self) { Text("outer line \($0)") }
                    }
                    .onGeometryChange(for: Int.self, of: { $0.size.width }, action: { log.outer.append($0) })
                }
                .focusID("outer")
                .frame(width: 30, height: 10)
                Button("After") {}.focusID("after")
            }
        }
    }

    private struct FollowingApp: App {
        let log: WidthLog
        init() { log = WidthLog() }
        init(log: WidthLog) { self.log = log }

        var body: some Scene {
            WindowGroup { Page(log: log) }
                .focusFollowsPointer()
        }
    }

    @Test("Tabbing through the controls inside lays the outer content out once going in and once coming out")
    func tabbing() {
        let log = WidthLog()
        let app = TestApp(width: 40, height: 14) { Page(log: log) }
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "before")
        let outside = log.outer.last
        // The width each content was laid out at with the focus on each stop.
        var walk: [(stop: String, outer: Int?, inner: Int?)] = []
        for _ in 0..<8 {
            app.press(.tab)
            walk.append((app.focusedID ?? "nil", log.outer.last, log.inner.last))
            if app.focusedID == "after" { break }
        }
        let stops = walk.map(\.stop)
        #expect(
            Set(stops).isSuperset(of: ["top", "inner", "innerA", "innerB", "bottom"]) && stops.last == "after",
            "the walk: \(stops)")
        let inside = walk.filter { $0.stop != "after" }
        // In the outer view, wherever the focus is: one width, narrower than outside it.
        #expect(Set(inside.map(\.outer)).count == 1, "the outer content moved: \(walk)")
        #expect(inside.first?.outer != outside, "the outer bar did not come beside the content: \(walk)")
        #expect(walk.last?.outer == outside, "the outer content did not get its room back: \(walk)")
        // In the inner view, wherever the focus is: one width.
        let inner = walk.filter { ["inner", "innerA", "innerB"].contains($0.stop) }
        #expect(Set(inner.map(\.inner)).count == 1, "the inner content moved: \(walk)")
    }

    @Test("Moving the pointer in and out lays each content out once per entry")
    func pointer() throws {
        let log = WidthLog()
        let app = TestApp(FollowingApp(log: log), width: 40, height: 14)
        app.advance(by: .milliseconds(20))
        let outerLine = try #require(app.screen.location(of: "outer line 0"))
        let innerA = try #require(app.screen.location(of: "Inner A"))
        let innerLine = try #require(app.screen.location(of: "inner line 0"))
        let atRest = log.outer.count

        // Into the outer view, then into the inner one, about inside it, and out to the outer again.
        app.hover(at: outerLine)
        #expect(app.focusedID == "outer")
        let enteredOuter = log.outer.count
        app.hover(at: innerLine)
        #expect(app.focusedID == "inner")
        app.hover(at: innerA)
        #expect(app.focusedID == "innerA")
        app.hover(at: CellPoint(x: innerLine.x + 1, y: innerLine.y))
        app.hover(at: CellPoint(x: outerLine.x + 1, y: outerLine.y))
        #expect(app.focusedID == "outer")
        #expect(enteredOuter - atRest <= 1, "entering the outer view: \(log.outer)")
        #expect(log.outer.count == enteredOuter, "the outer content moved while the focus stayed inside: \(log.outer)")
        // The inner one: in, and out — no more.
        #expect(log.inner.count <= 3, "the inner content was laid out at \(log.inner)")
    }

    /// A page drawn under a modal is drawn with a focus manager of its own that
    /// holds no focus: asked of it, the page's scroll view would have put its
    /// bar over its content as the sheet came up and back beside it as it went.
    private struct SheetPage: View {
        let log: WidthLog
        let isUp: Binding<Bool>

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Open") { isUp.wrappedValue = true }.focusID("open")
                    ForEach(0..<30, id: \.self) { Text("page line \($0)") }
                }
                .onGeometryChange(for: Int.self, of: { $0.size.width }, action: { log.outer.append($0) })
            }
            .sheet(isPresented: isUp) {
                Button("Done") { isUp.wrappedValue = false }.focusID("done")
            }
        }
    }

    @Test("A page under a sheet keeps its layout while the sheet is up and after it goes")
    func underASheet() throws {
        let log = WidthLog()
        let flag = SheetFlag()
        let binding = Binding(get: { flag.isUp }, set: { flag.isUp = $0 })
        let app = TestApp(width: 40, height: 14) { SheetPage(log: log, isUp: binding) }
        app.advance(by: .milliseconds(20))
        #expect(app.focusedID == "open")
        let settled = log.outer
        // The page's top row, its bar's top arrow at its end: above the sheet,
        // drawn dimmed behind it, as it was.
        let top = app.screen.lines.first
        #expect(top?.hasSuffix("▲") == true, "the bar is beside the page: \(app.screen)")
        app.press(.enter)
        app.advance(by: .milliseconds(500))
        #expect(app.focusedID == "done", "the sheet took the focus")
        #expect(app.screen.lines.first == top, "the page behind the sheet was laid out again: \(app.screen)")
        app.press(.enter)
        app.advance(by: .milliseconds(500))
        #expect(app.focusedID == "open", "the page got the focus back")
        #expect(log.outer == settled, "the page was laid out again: \(log.outer)")
    }
}
