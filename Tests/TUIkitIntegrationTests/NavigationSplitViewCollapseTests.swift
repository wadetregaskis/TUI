//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewCollapseTests.swift
//
//  A split view in a horizontally compact size class collapses into a stack
//  (decisions A21, B3). SwiftUI's side is its own documentation, macOS never
//  being compact: "the navigation split view collapses all of its columns into
//  a stack, and shows the last column that displays useful information … the
//  list of departments to start, the employees in the department after someone
//  selects a department"; `preferredCompactColumn` "controls which column
//  appears on top when the view collapses", and back writes `.sidebar` to it;
//  "the split view ignores the visibility control when it collapses".
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What the pages read and the tests write.
@Observable
private final class SplitModel: @unchecked Sendable {
    var horizontal: UserInterfaceSizeClass = .compact
    var column: NavigationSplitViewColumn = .sidebar
    var visibility: NavigationSplitViewVisibility = .all
    var planet: String?
    var moon: String?
}

@MainActor
@Suite("A split view in a compact size class collapses into a stack")
struct NavigationSplitViewCollapseTests {
    // MARK: - Pages

    private struct TwoColumns: View {
        let model: SplitModel
        var body: some View {
            NavigationSplitView(
                columnVisibility: Binding(get: { model.visibility }, set: { model.visibility = $0 }),
                preferredCompactColumn: Binding(get: { model.column }, set: { model.column = $0 })
            ) {
                List(selection: Binding(get: { model.planet }, set: { model.planet = $0 })) {
                    ForEach(["Mercury", "Venus", "Earth"], id: \.self) { Text($0) }
                }
                .navigationTitle("Planets")
            } detail: {
                Detail(planet: model.planet)
            }
            .environment(\.horizontalSizeClass, model.horizontal)
        }
    }

    /// The detail column: its planet, and a button that dismisses.
    private struct Detail: View {
        let planet: String?
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            VStack {
                Text("about \(planet ?? "nothing")")
                Button("Done") { dismiss() }
            }
            .navigationTitle(planet ?? "")
        }
    }

    private struct ThreeColumns: View {
        let model: SplitModel
        var body: some View {
            NavigationSplitView(preferredCompactColumn: Binding(get: { model.column }, set: { model.column = $0 })) {
                List(selection: Binding(get: { model.planet }, set: { model.planet = $0 })) {
                    ForEach(["Mars", "Jupiter"], id: \.self) { Text($0) }
                }
                .navigationTitle("Planets")
            } content: {
                List(selection: Binding(get: { model.moon }, set: { model.moon = $0 })) {
                    ForEach(["Phobos", "Deimos"], id: \.self) { Text("moon \($0)") }
                }
                .navigationTitle(model.planet ?? "")
            } detail: {
                Text("about \(model.moon ?? "nothing")").navigationTitle(model.moon ?? "")
            }
            .environment(\.horizontalSizeClass, model.horizontal)
        }
    }

    private struct Page: App {
        let content: AnyView
        init() { self.init(content: AnyView(EmptyView())) }
        init(content: AnyView) { self.content = content }
        var body: some Scene { WindowGroup { content } }
    }

    /// A headless app over `view`, with its frames 1/60 s apart.
    private final class Driver {
        let app: HeadlessApp<Page>
        private var now: Int64 = 0

        @MainActor
        init(_ view: some View, width: Int = 50, height: Int = 12) {
            app = HeadlessApp(Page(content: AnyView(view)), width: width, height: height)
            frame()
            frame()
        }

        @MainActor
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        /// Sends `key`, then draws twice: one frame for the key's write, one
        /// for what it showed.
        @MainActor
        func press(_ key: Key) {
            app.send(KeyEvent(key: key))
            frame()
            frame()
        }

        @MainActor
        func shows(_ text: String) -> Bool {
            app.screen.contains { $0.stripped.contains(text) }
        }
    }

    // MARK: - The column on top

    @Test("Collapsed, the sidebar is on top alone, at the full width; regular, both columns show")
    func sidebarOnTop() {
        let model = SplitModel()
        let driver = Driver(TwoColumns(model: model))
        #expect(driver.shows("Mercury"))
        #expect(!driver.shows("about"), "the detail is drawn in a collapsed split: \(driver.app.screen)")
        model.horizontal = .regular
        driver.frame()
        driver.frame()
        #expect(driver.shows("Mercury") && driver.shows("about nothing"), "\(driver.app.screen)")
    }

    @Test("Choosing a row selects it and shows the next column under a bar, writing the binding")
    func choosingShowsTheDetail() {
        let model = SplitModel()
        let driver = Driver(TwoColumns(model: model))
        driver.press(.down)
        driver.press(.enter)
        #expect(model.planet == "Venus")
        #expect(model.column == .detail)
        #expect(driver.shows("about Venus"), "\(driver.app.screen)")
        #expect(!driver.shows("Mercury"), "the sidebar is drawn over the detail: \(driver.app.screen)")
        // The bar names the way back: the trail of the columns' titles.
        #expect(driver.shows("Planets › Venus"), "\(driver.app.screen)")
    }

    @Test("Escape goes back a column, writing .sidebar, and the row chosen before is chosen again, not cleared")
    func escapeGoesBack() {
        let model = SplitModel()
        let driver = Driver(TwoColumns(model: model))
        driver.press(.down)
        driver.press(.enter)
        driver.press(.escape)
        #expect(model.column == .sidebar)
        #expect(driver.shows("Mercury") && !driver.shows("about"), "\(driver.app.screen)")
        // The list kept its cursor on Venus, and Return goes there again.
        driver.press(.enter)
        #expect(model.planet == "Venus")
        #expect(model.column == .detail)
        #expect(driver.shows("about Venus"), "\(driver.app.screen)")
    }

    @Test("The binding puts a column on top from the start")
    func bindingDecides() {
        let model = SplitModel()
        model.planet = "Earth"
        model.column = .detail
        let driver = Driver(TwoColumns(model: model))
        #expect(driver.shows("about Earth") && !driver.shows("Mercury"), "\(driver.app.screen)")
    }

    @Test("\\.dismiss in the column on top goes back a column")
    func dismissGoesBack() {
        let model = SplitModel()
        let driver = Driver(TwoColumns(model: model))
        driver.press(.enter)
        #expect(model.column == .detail)
        // The detail's section holds the keyboard; its one button has the focus.
        driver.press(.enter)
        #expect(model.column == .sidebar, "\(driver.app.screen)")
    }

    @Test("Column visibility is ignored while collapsed, and the chords do not change it")
    func visibilityIgnored() {
        let model = SplitModel()
        model.visibility = .detailOnly
        let driver = Driver(TwoColumns(model: model))
        #expect(driver.shows("Mercury"), "\(driver.app.screen)")
        driver.app.send(KeyEvent(key: .character("s"), ctrl: true))
        driver.frame()
        #expect(model.visibility == .detailOnly)
    }

    @Test("Three columns: the sidebar, then the content, then the detail, and back one at a time")
    func threeColumns() {
        let model = SplitModel()
        let driver = Driver(ThreeColumns(model: model))
        #expect(driver.shows("Mars") && !driver.shows("moon"), "\(driver.app.screen)")
        driver.press(.enter)
        #expect(model.column == .content)
        #expect(driver.shows("moon Phobos") && !driver.shows("Jupiter"), "\(driver.app.screen)")
        driver.press(.down)
        driver.press(.enter)
        #expect(model.column == .detail)
        #expect(driver.shows("about Deimos"), "\(driver.app.screen)")
        #expect(driver.shows("Planets › Mars › Deimos"), "\(driver.app.screen)")
        driver.press(.escape)
        #expect(model.column == .content)
        #expect(driver.shows("moon Deimos"), "\(driver.app.screen)")
        driver.press(.escape)
        #expect(model.column == .sidebar)
        #expect(driver.shows("Jupiter"), "\(driver.app.screen)")
    }

    @Test("The columns keep their state across a change of size class")
    func stateAcrossAChange() {
        let model = SplitModel()
        model.horizontal = .regular
        let driver = Driver(TwoColumns(model: model))
        // Regular: the list's cursor moves to Venus, and Space selects it.
        driver.press(.down)
        model.horizontal = .compact
        driver.frame()
        driver.frame()
        // The list collapsed with its cursor where it was.
        driver.press(.enter)
        #expect(model.planet == "Venus", "the sidebar list was made anew when the split collapsed")
        #expect(model.column == .detail)
    }

    /// A row of the table in the sidebar.
    private struct Dwarf: Identifiable, Sendable {
        let id: String
    }

    private struct TableSidebar: View {
        let model: SplitModel
        var body: some View {
            NavigationSplitView(preferredCompactColumn: Binding(get: { model.column }, set: { model.column = $0 })) {
                Table(
                    [Dwarf(id: "Ceres"), Dwarf(id: "Pluto")],
                    selection: Binding(get: { model.planet }, set: { model.planet = $0 })
                ) {
                    TableColumn("Name", value: \Dwarf.id)
                }
            } detail: {
                Text("about \(model.planet ?? "nothing")")
            }
            .environment(\.horizontalSizeClass, .compact)
        }
    }

    @Test("A table's row is chosen the same way")
    func tableChooses() {
        let model = SplitModel()
        let driver = Driver(TableSidebar(model: model))
        driver.press(.down)
        driver.press(.enter)
        #expect(model.planet == "Pluto")
        #expect(model.column == .detail)
        #expect(driver.shows("about Pluto"), "\(driver.app.screen)")
    }

    private struct Unselectable: View {
        let model: SplitModel
        var body: some View {
            NavigationSplitView(preferredCompactColumn: Binding(get: { model.column }, set: { model.column = $0 })) {
                List { Text("row") }
            } detail: {
                Text("detail")
            }
            .environment(\.horizontalSizeClass, .compact)
        }
    }

    @Test("A list with no selection goes nowhere")
    func noSelectionNoAdvance() {
        let model = SplitModel()
        let driver = Driver(Unselectable(model: model))
        driver.press(.enter)
        driver.press(.space)
        #expect(model.column == .sidebar)
    }
}
