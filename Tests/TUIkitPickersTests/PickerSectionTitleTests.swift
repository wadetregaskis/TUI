//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSectionTitleTests.swift
//
//  A `Section`'s header inside a `Picker`: a menu picker's drop-down draws it
//  as a title over the section's options, under the rule that sets the
//  section apart, as a macOS menu picker draws an `NSMenuItem.sectionHeader`
//  there (`Tools/SwiftUIProbes/Picker sections/pickersection.out`). It was
//  read only for the rule, and the header itself was not drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitPickers
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("A section's header in a picker")
struct PickerSectionTitleTests {
    private enum Fruit: Hashable { case apple, pear, kale }

    /// A picker's entries, spelled: an option by its tag, a rule as "—", a
    /// title as "title".
    private func entries<Content: View>(@ViewBuilder _ content: () -> Content) -> [String] {
        _PickerOptionsReader<Fruit, _, EmptyView>(content: content()) { _, _ in EmptyView() }
            .entries(in: makeRenderContext(width: 40, height: 12))
            .map { entry in
                switch entry {
                case .option(let tag, _): "\(tag)"
                case .divider: "—"
                case .title: "title"
                }
            }
    }

    @Test("A section's header is its group's title, under the rule")
    func titleUnderTheRule() {
        let spelled = entries {
            Text("Loose").tag(Fruit.kale)
            Section("Fruit") {
                Text("Apple").tag(Fruit.apple)
                Text("Pear").tag(Fruit.pear)
            }
        }
        #expect(spelled == ["kale", "—", "title", "apple", "pear"], "\(spelled)")
    }

    @Test("A section with no header has a rule and no title")
    func noHeaderNoTitle() {
        let spelled = entries {
            Text("Apple").tag(Fruit.apple)
            Section { Text("Pear").tag(Fruit.pear) }
        }
        #expect(spelled == ["apple", "—", "pear"], "\(spelled)")
    }

    /// Fruit's citrus section, its one option shown only when `showCitrus`,
    /// and an option outside it.
    private func citrus(showCitrus: Bool) -> [String] {
        entries {
            Section("Citrus") {
                if showCitrus { Text("Lemon").tag(Fruit.kale) }
            }
            Text("Apple").tag(Fruit.apple)
        }
    }

    /// A macOS menu picker keeps the header of a section a condition empties,
    /// between its separators, over no options (`pickersection.out`,
    /// `emptied`); the leading rule is an edge rule, collapsed here.
    @Test("A section a condition empties keeps its title, set apart by a rule")
    func emptiedSectionKeepsItsTitle() {
        #expect(citrus(showCitrus: true) == ["title", "kale", "—", "apple"])
        let spelled = citrus(showCitrus: false)
        #expect(spelled == ["title", "—", "apple"], "\(spelled)")
    }

    /// The open drop-down of a menu picker over two sections, composited as
    /// the render loop composites it.
    private func openMenu(
        selection: Binding<Fruit> = .constant(.pear)
    ) -> (screen: [String], press: (KeyEvent) -> Void) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = Picker("Choose", selection: selection) {
            Section("Fruit") {
                Text("Apple").tag(Fruit.apple)
                Text("Pear").tag(Fruit.pear)
            }
            Section("Greens") { Text("Kale").tag(Fruit.kale) }
        }
        .pickerStyle(.menu)
        var palette: (any Palette)?
        func frame() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            palette = environment.palette
            let context = RenderContext(
                availableWidth: 40, availableHeight: 14, environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            return buffer
        }
        _ = frame()
        _ = frame()
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .enter)), "Enter opens the picker")
        let buffer = frame()
        return (
            buffer.compositingOverlays(maxWidth: 40, maxHeight: 14, palette: palette!).lines.map(\.stripped),
            { event in
                _ = focusManager.dispatchKeyEvent(event)
                _ = frame()
            }
        )
    }

    @Test("A menu picker's drop-down draws each header as a title over its options, on their left edge")
    func dropDownDrawsTitles() throws {
        let screen = openMenu().screen
        let fruit = try #require(screen.firstIndex { $0.contains("Fruit") }, "\(screen)")
        let apple = try #require(screen.firstIndex { $0.contains("Apple") }, "\(screen)")
        let greens = try #require(screen.firstIndex { $0.contains("Greens") }, "\(screen)")
        let kale = try #require(screen.firstIndex { $0.contains("Kale") }, "\(screen)")
        #expect(fruit + 1 == apple, "the title sits right over its first option: \(screen)")
        #expect(greens + 1 == kale, "\(screen)")
        let rule = screen[greens - 1].trimmingCharacters(in: .whitespaces)
        #expect(rule.contains("─"), "a rule sets the second section apart, above its title: \(screen)")
        #expect(
            screen[fruit].firstIndex(of: "F").map { screen[fruit].distance(from: screen[fruit].startIndex, to: $0) }
                == screen[apple].firstIndex(of: "A").map { screen[apple].distance(from: screen[apple].startIndex, to: $0) },
            "the title starts on the options' left edge: \(screen)")
    }

    @Test("Down from a section's last option steps over the next section's title")
    func arrowsStepOverTitles() {
        var choice = Fruit.pear
        let press = openMenu(selection: Binding(get: { choice }, set: { choice = $0 })).press
        press(KeyEvent(key: .down))
        press(KeyEvent(key: .enter))
        #expect(choice == .kale, "the title is no option the highlight can rest on")
    }
}
