//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabelledPanelToggleTests.swift
//
//  `DefaultToolbarItem(kind:placement:label:)`: a toggle's button draws its
//  label after the arrow, and the label's text names the panel in the button's
//  key hint and in the hints of the panel's own handles — the split view's ◀
//  divider and the inspector's ▶ divider.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitFoundation
import TUIkitNavigation
@testable import TUIkitTestSupport

/// A sidebar on each side, each with a labelled button, and the key hints in
/// the bottom bar.
private struct BothSidesApp: App {
    @MainActor static var showsInfo = true
    init() {}
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                Text("FOLDERS")
            } detail: {
                Text("EDITOR")
            }
            .inspector(
                isPresented: Binding(get: { Self.showsInfo }, set: { Self.showsInfo = $0 })
            ) { Text("INFO") }
            .toolbar {
                DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) { Text("Folders") }
                DefaultToolbarItem(kind: .inspectorToggle, placement: .primaryAction) { Text("Info") }
                ToolbarItem(placement: .bottomBar) { StatusBar() }
            }
        }
    }
}

@MainActor
@Suite("A toolbar toggle's label", .rendersEnglishUI)
struct LabelledPanelToggleTests {
    private func running<A: App>(_ app: A) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 72, height: 14)
        for index in 1...5 { headless.frame(atNanos: Int64(index) * 16_666_667) }
        return headless
    }

    private func rows<A: App>(_ app: HeadlessApp<A>) -> [String] {
        app.screen.map(\.stripped)
    }

    /// A still click at `column` on `row`, and two frames after it.
    private func click<A: App>(_ app: HeadlessApp<A>, row: Int, column: Int, frame: Int) {
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        _ = app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        for index in frame...(frame + 1) { app.frame(atNanos: Int64(index) * 16_666_667) }
    }

    @Test("Each button draws its label after its arrow")
    func labelsAfterArrows() throws {
        BothSidesApp.showsInfo = true
        let app = running(BothSidesApp())
        let bar = try #require(rows(app).first { $0.contains("Folders") }, "\(rows(app))")
        #expect(bar.contains("◀ Folders"), "\(bar)")
        #expect(bar.contains("▶ Info"), "\(bar)")
    }

    @Test("The split view's divider, focused, names the sidebar by the button's label")
    func splitDividerHint() throws {
        BothSidesApp.showsInfo = true
        let app = running(BothSidesApp())
        let screen = rows(app)
        let folders = try #require(screen.firstIndex { $0.hasPrefix("FOLDERS") }, "\(screen)")
        // A grip dot of the divider after the sidebar: a click there focuses it
        // and hides nothing (the ◀ is the middle row).
        let dotRow = try #require(screen.indices.first { $0 > folders && screen[$0].contains("◦") }, "\(screen)")
        let dotColumn = screen[dotRow].distance(
            from: screen[dotRow].startIndex, to: try #require(screen[dotRow].range(of: "◦")).lowerBound)
        click(app, row: dotRow, column: dotColumn, frame: 6)
        #expect(rows(app).contains { $0.contains("hide Folders") }, "\(rows(app))")
    }

    @Test("The inspector's divider, focused, names it by the button's label")
    func inspectorDividerHint() throws {
        BothSidesApp.showsInfo = true
        let app = running(BothSidesApp())
        let screen = rows(app)
        let info = try #require(screen.firstIndex { $0.contains("INFO") }, "\(screen)")
        // The rule's top row, before the inspector's text: a click there
        // focuses the divider and hides nothing (the ▶ is the middle row).
        let line = screen[info]
        let infoColumn = line.distance(from: line.startIndex, to: try #require(line.range(of: "INFO")).lowerBound)
        click(app, row: info, column: infoColumn - 1, frame: 6)
        #expect(BothSidesApp.showsInfo, "a click off the ▶ hides nothing")
        #expect(rows(app).contains { $0.contains("hide Info") }, "\(rows(app))")
    }
}
