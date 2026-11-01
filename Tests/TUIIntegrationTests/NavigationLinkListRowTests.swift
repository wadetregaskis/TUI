//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationLinkListRowTests.swift
//
//  A `NavigationLink` as a row of a `List`. SwiftUI's side is measured:
//  `Tools/SwiftUIProbes/NavigationLink as a list row/links.out`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing
@testable import TUIAppTestSupport

import TUI
@testable import TUIApp
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// Identified by a string, and selected as itself.
private enum Category: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fruit, vegetables, nuts
    var id: String { "id-" + rawValue }
}

/// What the pages read and the tests write.
@Observable
private final class Model: @unchecked Sendable {
    var category: Category?
    var categories: Set<Category> = []
    var number: Int?
    var path: [Category] = []

    var categoryBinding: Binding<Category?> {
        Binding(get: { self.category }, set: { self.category = $0 })
    }
}

@MainActor
@Suite("A NavigationLink as a row of a List")
struct NavigationLinkListRowTests {
    private struct Page: App {
        let content: AnyView
        init() { self.init(content: AnyView(EmptyView())) }
        init(content: AnyView) { self.content = content }
        var body: some Scene { WindowGroup { content } }
    }

    /// A headless app over `view`, with its frames 1/60 s apart.
    private final class Driver {
        let app: TestApp
        private var now: Int64 = 0

        @MainActor
        init(_ view: some View, width: Int = 60, height: Int = 12) {
            app = TestApp(Page(content: AnyView(view)), width: width, height: height)
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

        /// Presses and releases the left button on the first cell showing `text`.
        @MainActor
        func click(_ text: String) {
            guard let y = app.screen.styledLines.firstIndex(where: { $0.stripped.contains(text) }),
                let range = app.screen.styledLines[y].stripped.range(of: text)
            else {
                Issue.record("\(text) is not on screen: \(app.screen.styledLines)")
                return
            }
            let x = app.screen.styledLines[y].stripped.distance(from: app.screen.styledLines[y].stripped.startIndex, to: range.lowerBound)
            app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
            frame()
            frame()
        }

        @MainActor
        func shows(_ text: String) -> Bool {
            app.screen.contains(text)
        }

        /// Whether a filled button's caps are on screen.
        @MainActor
        var showsButtons: Bool { shows("▐") }
    }

    // MARK: - A sidebar: the link's value is the row's

    private struct Sidebar: View {
        let model: Model
        var body: some View {
            NavigationSplitView {
                List(Category.allCases, selection: model.categoryBinding) { category in
                    NavigationLink(category.rawValue, value: category)
                }
            } content: {
                Text("showing \(model.category?.rawValue ?? "none")")
            } detail: {
                Text("detail")
            }
        }
    }

    @Test("Down and Return select the link's value in a sidebar, and the content column switches")
    func sidebarReturn() {
        let model = Model()
        let driver = Driver(Sidebar(model: model), width: 100)
        #expect(driver.shows("showing none"), "\(driver.app.screen.styledLines)")
        driver.press(.down)
        #expect(model.category == nil, "the cursor moved; nothing was chosen")
        driver.press(.enter)
        #expect(model.category == .vegetables)
        #expect(driver.shows("showing vegetables"), "\(driver.app.screen.styledLines)")
    }

    @Test("Space selects it too, and on the selected row clears it")
    func sidebarSpace() {
        let model = Model()
        let driver = Driver(Sidebar(model: model))
        driver.press(.space)
        #expect(model.category == .fruit)
        #expect(driver.shows("showing fruit"), "\(driver.app.screen.styledLines)")
        driver.press(.space)
        #expect(model.category == nil)
    }

    @Test("A click on the row selects it")
    func sidebarClick() {
        let model = Model()
        let driver = Driver(Sidebar(model: model))
        driver.click("nuts")
        #expect(model.category == .nuts, "\(driver.app.screen.styledLines)")
        #expect(driver.shows("showing nuts"), "\(driver.app.screen.styledLines)")
    }

    @Test("A row the list can select draws its link as a label")
    func sidebarDrawsLabels() {
        let driver = Driver(Sidebar(model: Model()))
        #expect(driver.shows("vegetables"))
        #expect(!driver.showsButtons, "\(driver.app.screen.styledLines)")
    }

    @Test("A hugging list is as wide with links as with the same words tagged")
    func hugMeasuresLabels() {
        let words = String(repeating: "w", count: 30)
        func column(of list: some View) -> Int? {
            let driver = Driver(HStack(spacing: 0) { list.fixedSize(horizontal: true, vertical: false); Text("next") }, width: 80)
            let row = driver.app.screen.styledLines.first { $0.stripped.contains("next") }?.stripped ?? ""
            return row.range(of: "next").map { row.distance(from: row.startIndex, to: $0.lowerBound) }
        }
        var selection: Int?
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let links = column(of: List(selection: binding) { NavigationLink(words, value: 1) })
        let tagged = column(of: List(selection: binding) { Text(words).tag(1) })
        #expect(links != nil)
        #expect(links == tagged)
    }

    @Test("No Tab stop inside the row: Tab leaves the list, rather than stopping on each link")
    func noTabStops() {
        let model = Model()
        let driver = Driver(
            VStack {
                List(Category.allCases, selection: model.categoryBinding) { category in
                    NavigationLink(category.rawValue, value: category)
                }
                Button("After") { model.number = 1 }
            })
        driver.press(.tab)
        driver.press(.enter)
        #expect(model.number == 1, "Return went to the button after the list: \(driver.app.screen.styledLines)")
        #expect(model.category == nil)
    }

    @Test("In a collapsed split, choosing a row shows the next column and pushes nothing")
    func collapsedSplit() {
        let model = Model()
        let driver = Driver(
            Sidebar(model: model).environment(\.horizontalSizeClass, .compact), width: 40)
        driver.press(.enter)
        #expect(model.category == .fruit)
        #expect(driver.shows("showing fruit"), "\(driver.app.screen.styledLines)")
        driver.press(.escape)
        #expect(driver.shows("nuts"), "one Escape comes back: \(driver.app.screen.styledLines)")
    }

    // MARK: - The other forms

    @Test("A multi-selection takes the link's value")
    func multiSelection() {
        let model = Model()
        let driver = Driver(
            List(selection: Binding(get: { model.categories }, set: { model.categories = $0 })) {
                ForEach(Category.allCases) { category in
                    NavigationLink(category.rawValue, value: category)
                }
            })
        driver.press(.enter)
        driver.press(.down)
        driver.press(.enter)
        #expect(model.categories == [.fruit, .vegetables])
    }

    @Test("Hand-written links name themselves, beside other rows")
    func handWrittenLinks() {
        let model = Model()
        let driver = Driver(
            List(selection: model.categoryBinding) {
                NavigationLink("first", value: Category.nuts)
                NavigationLink("second", value: Category.fruit)
            })
        driver.press(.down)
        driver.press(.enter)
        #expect(model.category == .fruit)
    }

    @Test("A modifier written on the link leaves its value naming the row")
    func modifierOutsideTheLink() {
        let model = Model()
        let driver = Driver(
            List(Category.allCases, selection: model.categoryBinding) { category in
                NavigationLink(category.rawValue, value: category).padding(.leading, 1)
            })
        driver.press(.enter)
        #expect(model.category == .fruit)
    }

    @Test("A .tag on a link outranks its value")
    func tagOutranksValue() {
        let model = Model()
        let driver = Driver(
            List(selection: Binding(get: { model.number }, set: { model.number = $0 })) {
                NavigationLink("first", value: "not a number").tag(7)
                NavigationLink("second", value: "not a number").tag(8)
            })
        driver.press(.down)
        driver.press(.enter)
        #expect(model.number == 8)
    }

    @Test("A link's value of another type leaves the row its element's id")
    func valueOfAnotherType() {
        let model = Model()
        let driver = Driver(
            NavigationStack {
                List(selection: model.categoryBinding) {
                    ForEach(Category.allCases, id: \.self) { category in
                        NavigationLink(category.rawValue, value: category.rawValue.count)
                    }
                }
                .navigationDestination(for: Int.self) { Text("count \($0)") }
            })
        #expect(!driver.showsButtons, "\(driver.app.screen.styledLines)")
        driver.press(.enter)
        #expect(model.category == .fruit)
        #expect(driver.shows("count 5"), "the row's link is followed too: \(driver.app.screen.styledLines)")
    }

    @Test("A row the list cannot select keeps its button, which still pushes")
    func unselectableKeepsTheButton() {
        let model = Model()
        let driver = Driver(
            NavigationStack {
                List(Category.allCases, selection: model.categoryBinding) { category in
                    NavigationLink(category.rawValue, value: category.rawValue)
                }
                .navigationDestination(for: String.self) { Text("pushed \($0)") }
            })
        #expect(driver.showsButtons, "\(driver.app.screen.styledLines)")
        driver.press(.tab)
        driver.press(.enter)
        #expect(driver.shows("pushed fruit"), "\(driver.app.screen.styledLines)")
        #expect(model.category == nil)
    }

    @Test("A nil value after a row that names itself draws, selects nothing, and does not crash")
    func nilValueAfterAValue() {
        let model = Model()
        let driver = Driver(
            List(Category.allCases, selection: model.categoryBinding) { category in
                NavigationLink(category.rawValue, value: category == .vegetables ? nil : category)
            })
        #expect(driver.shows("vegetables"), "\(driver.app.screen.styledLines)")
        driver.press(.down)
        driver.press(.enter)
        #expect(model.category == nil, "\(driver.app.screen.styledLines)")
        driver.press(.down)
        driver.press(.enter)
        #expect(model.category == .nuts)
    }

    // MARK: - In a stack

    private struct SelectingStack: View {
        let model: Model
        var body: some View {
            NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
                List(Category.allCases, selection: model.categoryBinding) { category in
                    NavigationLink(category.rawValue, value: category)
                }
                .navigationDestination(for: Category.self) { Text("pushed \($0.rawValue)") }
            }
        }
    }

    @Test("Choosing a row in a selecting list in a stack selects it and follows its link")
    func selectingInAStack() {
        let model = Model()
        let driver = Driver(SelectingStack(model: model))
        driver.press(.down)
        driver.press(.enter)
        #expect(model.category == .vegetables)
        #expect(model.path == [.vegetables])
        #expect(driver.shows("pushed vegetables"), "\(driver.app.screen.styledLines)")
    }

    @Test("Clearing the selection follows nothing")
    func clearingFollowsNothing() {
        let model = Model()
        model.category = .fruit
        let driver = Driver(SelectingStack(model: model))
        driver.press(.space)
        #expect(model.category == nil)
        #expect(model.path.isEmpty, "\(driver.app.screen.styledLines)")
    }

    @Test("A click on the row selects it and follows its link")
    func clickInAStack() {
        let model = Model()
        let driver = Driver(SelectingStack(model: model))
        driver.click("nuts")
        #expect(model.category == .nuts)
        #expect(model.path == [.nuts], "\(driver.app.screen.styledLines)")
    }

    // MARK: - A list without a selection

    private struct Plain: View {
        var body: some View {
            NavigationStack {
                List(Category.allCases) { category in
                    NavigationLink(category.rawValue, value: category)
                }
                .navigationDestination(for: Category.self) { Text("pushed \($0.rawValue)") }
            }
        }
    }

    @Test("Return on the cursor row follows its link, with no Tab first", arguments: [Key.enter, Key.space])
    func plainListFollows(key: Key) {
        let driver = Driver(Plain())
        #expect(driver.showsButtons, "the row keeps its button: \(driver.app.screen.styledLines)")
        driver.press(.down)
        #expect(!driver.shows("pushed"), "moving the cursor follows nothing")
        driver.press(key)
        #expect(driver.shows("pushed vegetables"), "\(driver.app.screen.styledLines)")
    }

    @Test("The report survives the row being served from its memo")
    func reportSurvivesMemo() {
        let driver = Driver(Plain())
        for _ in 0..<5 { driver.frame() }
        driver.press(.enter)
        #expect(driver.shows("pushed fruit"), "\(driver.app.screen.styledLines)")
    }

    @Test("Tab and Return reach the link's button as before")
    func plainListTab() {
        let driver = Driver(Plain())
        driver.press(.tab)
        driver.press(.enter)
        #expect(driver.shows("pushed fruit"), "\(driver.app.screen.styledLines)")
    }

    @Test("A link to a view is followed from the row")
    func viewDestination() {
        let driver = Driver(
            NavigationStack {
                List(Category.allCases) { category in
                    NavigationLink(category.rawValue) { Text("screen \(category.rawValue)") }
                }
            })
        driver.press(.enter)
        #expect(driver.shows("screen fruit"), "\(driver.app.screen.styledLines)")
    }

    @Test("The row follows nothing where no stack is around it")
    func plainListWithoutAStack() {
        let driver = Driver(
            List(Category.allCases) { category in
                NavigationLink(category.rawValue, value: category)
            })
        driver.press(.enter)
        #expect(driver.shows("fruit"), "\(driver.app.screen.styledLines)")
    }
}
