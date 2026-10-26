//  🖥️ TUI — A Terminal UI framework for Swift
//  TabContentTests.swift
//
//  SwiftUI's tab API: `TabContent` and its builder, `Tab`'s labels and roles,
//  `TabSection`, `AnyTabContent`, a tab view without a selection, and the tab
//  modifiers — a badge, hiding, disabling, and a sidebar-only placement.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITabs
@testable import TUITestSupport

/// Tab content of an app's own, written the way SwiftUI's is.
private struct MailTabs: TabContent {
    var body: some TabContent<Int> {
        Tab("Inbox", value: 0) { Text("INBOX BODY") }
        Tab("Sent", value: 1) { Text("SENT BODY") }
    }
}

@MainActor
@Suite("Tab content")
struct TabContentTests {
    private func lines(_ view: some View, context: RenderContext? = nil) -> [String] {
        renderToBuffer(view, context: context ?? makeRenderContext(width: 90, height: 8)).lines.map(\.stripped)
    }

    private func strip(_ lines: [String]) -> String {
        lines.first ?? ""
    }

    // MARK: - Without a selection

    @Test("A tab view without a selection shows its first tab, and the keys select by position")
    func implicitSelection() {
        let context = makeRenderContext(width: 50, height: 8)
        let view = TabView {
            Tab("Alpha", systemImage: "a.circle") { Text("ALPHA BODY") }
            Tab("Beta", systemImage: "b.circle") { Text("BETA BODY") }
        }
        let first = lines(view, context: context)
        #expect(first.contains { $0.contains("ALPHA BODY") }, "\(first)")
        #expect(strip(first).contains("Alpha") && strip(first).contains("Beta"), "\(first)")
        #expect(context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .right)) == true)
        let second = lines(view, context: context)
        #expect(second.contains { $0.contains("BETA BODY") }, "\(second)")
        #expect(!second.contains { $0.contains("ALPHA BODY") }, "\(second)")
    }

    @Test("A section's tabs take an optional selection's promoted values")
    func optionalSelectionInASection() {
        let out = lines(
            TabView(selection: .constant(Int?.some(2))) {
                Tab("One", value: 1) { Text("ONE BODY") }
                TabSection("More") {
                    Tab("Two", value: 2) { Text("TWO BODY") }
                }
            })
        #expect(out.contains { $0.contains("TWO BODY") }, "\(out)")
    }

    // MARK: - Composition

    @Test("Tab content composes: a type of the app's own, a section, a loop, a group, conditionals, erasure")
    func composition() {
        let showExtra = true
        let out = lines(
            TabView(selection: .constant(3)) {
                MailTabs()
                TabSection("Folders") {
                    ForEach([2, 3], id: \.self) { n in
                        Tab("Folder\(n)", value: n) { Text("FOLDER \(n) BODY") }
                    }
                }
                Group {
                    if showExtra {
                        Tab("Extra", value: 4) { Text("EXTRA") }
                    } else {
                        Tab("Other", value: 5) { Text("OTHER") }
                    }
                }
                AnyTabContent(Tab("Erased", value: 6) { Text("ERASED") })
            })
        let titles = strip(out)
        for title in ["Inbox", "Sent", "Folder2", "Folder3", "Extra", "Erased"] {
            #expect(titles.contains(title), "\(title) in \(titles)")
        }
        #expect(!titles.contains("Other") && !titles.contains("Folders"), "\(titles)")
        #expect(out.contains { $0.contains("FOLDER 3 BODY") }, "\(out)")
    }

    // MARK: - Labels and roles

    @Test("A search tab with no title is labelled Search; a label of the app's own draws its text")
    func labels() {
        let titles = strip(
            lines(
                TabView(selection: .constant(0)) {
                    Tab(value: 0) { Text("BODY") } label: { Text("Custom") }
                    Tab(value: 1, role: .search) { Text("SEARCH BODY") }
                    Tab(value: 2) { Text("UNLABELLED") }
                }))
        #expect(titles.contains("Custom"), "\(titles)")
        #expect(titles.contains("Search"), "\(titles)")
    }

    // MARK: - Modifiers

    @Test("A badge follows its tab's title in the strip; zero hides it")
    func badge() {
        let titles = strip(
            lines(
                TabView(selection: .constant(0)) {
                    Tab("Inbox", value: 0) { Text("BODY") }.badge(7)
                    Tab("Sent", value: 1) { Text("BODY") }.badge(0)
                    Tab("Drafts", value: 2) { Text("BODY") }.badge("new")
                }))
        #expect(titles.contains("Inbox 7"), "\(titles)")
        #expect(titles.contains("Drafts new"), "\(titles)")
        #expect(!titles.contains("Sent 0"), "\(titles)")
    }

    @Test("A hidden tab and a sidebar-only one are left out of the strip")
    func hiddenAndSidebarOnly() {
        let titles = strip(
            lines(
                TabView(selection: .constant(0)) {
                    Tab("Shown", value: 0) { Text("BODY") }
                    Tab("Gone", value: 1) { Text("BODY") }.hidden()
                    Tab("Sidebar", value: 2) { Text("BODY") }.tabPlacement(.sidebarOnly)
                    Tab("Kept", value: 3) { Text("BODY") }.hidden(false)
                }))
        #expect(titles.contains("Shown") && titles.contains("Kept"), "\(titles)")
        #expect(!titles.contains("Gone") && !titles.contains("Sidebar"), "\(titles)")
    }

    @Test("The arrow keys step over a disabled tab, which stays in the strip")
    func disabledTabIsSkipped() {
        final class Box { var value = 0 }
        let box = Box()
        let context = makeRenderContext(width: 50, height: 8)
        let out = lines(
            TabView(selection: Binding(get: { box.value }, set: { box.value = $0 })) {
                Tab("One", value: 0) { Text("BODY") }
                Tab("Two", value: 1) { Text("BODY") }.disabled(true)
                Tab("Three", value: 2) { Text("BODY") }
            },
            context: context)
        #expect(strip(out).contains("Two"), "\(out)")
        #expect(context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .right)) == true)
        #expect(box.value == 2)
    }

    // MARK: - Types

    @Test("Each kind of tab content names its value type, and the builder ties it to the selection's")
    func valueTypes() {
        #expect(Tab<Int, Text, EmptyView>.TabValue.self == Int.self)
        #expect(TabSection<Text, Tab<Int, Text, EmptyView>, EmptyView, Int>.TabValue.self == Int.self)
        #expect(Group<Tab<Int, Text, EmptyView>>.TabValue.self == Int.self)
        #expect(Tab<String, Text, EmptyView>?.TabValue.self == String.self)
        #expect(AnyTabContent<Int>.TabValue.self == Int.self)
        #expect(MailTabs.TabValue.self == Int.self)
    }
}
