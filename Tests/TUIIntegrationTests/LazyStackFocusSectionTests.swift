//  🖥️ TUI — A Terminal UI framework for Swift
//  LazyStackFocusSectionTests.swift
//
//  Tab, Shift-Tab and the arrows through a `LazyVStack` a `ScrollView`
//  windows, against the same rows in an eager `VStack`: plain rows, rows each
//  in a `focusSection()`, and the stack itself a section beside another. A
//  windowed stack draws only the rows on screen, the rows beside the focus and
//  the next focusable past a run that registers nothing
//  (`StackFocusReach.swift`), so a row the focus steps into off the band is
//  drawn for the ring that frame and scrolled in; these hold that the walk is
//  the eager one, step for step, and that every control it lands on is on
//  screen. Sections change nothing here: each shape walks as its eager twin
//  does, but for two known issues. LAZY-EDGE: the focus coming into the
//  stack from outside its scroll view lands on the band's edge row, not the
//  stack's (SwiftUI's lazy stack does the same, measured in
//  `Tools/SwiftUIProbes/Focus sections in a lazy stack (1117L)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("Tab and the arrows through a windowed lazy stack's focus sections")
struct LazyStackFocusSectionTests {
    /// Where the sections are.
    enum Shape: String, CaseIterable, CustomTestStringConvertible {
        /// No section in the stack.
        case plain
        /// Each row `.focusSection()`.
        case rowSections
        /// The stack `.focusSection()`, beside a section of two buttons.
        case stackSection
        var testDescription: String { rawValue }
    }

    /// How the rows' controls are named.
    enum Naming: String, CaseIterable, CustomTestStringConvertible {
        /// The identity-path focus ids every control has by default.
        case automatic
        /// Each button `.focusID(_:)` (a text field has no such modifier).
        case explicit
        var testDescription: String { rawValue }
    }

    static let rowCount = 40

    private static func pad(_ index: Int) -> String { index < 10 ? "0\(index)" : "\(index)" }

    private struct Row: View {
        let index: Int
        let shape: Shape
        let naming: Naming
        @State private var text: String

        init(_ index: Int, shape: Shape, naming: Naming) {
            self.index = index
            self.shape = shape
            self.naming = naming
            _text = State(initialValue: "t\(LazyStackFocusSectionTests.pad(index))")
        }

        @ViewBuilder private var controls: some View {
            let name = LazyStackFocusSectionTests.pad(index)
            switch naming {
            case .automatic:
                HStack(spacing: 1) {
                    Button("b\(name)") {}
                    TextField("", text: $text).frame(width: 6)
                }
            case .explicit:
                HStack(spacing: 1) {
                    Button("b\(name)") {}.focusID("b\(name)")
                    TextField("", text: $text).frame(width: 6)  // a text field takes no focusID
                }
            }
        }

        var body: some View {
            if shape == .rowSections {
                controls.focusSection()
            } else {
                controls
            }
        }
    }

    private struct Page: View {
        let lazy: Bool
        let shape: Shape
        let naming: Naming

        @ViewBuilder private var rows: some View {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<LazyStackFocusSectionTests.rowCount, id: \.self) {
                        Row($0, shape: shape, naming: naming)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<LazyStackFocusSectionTests.rowCount, id: \.self) {
                        Row($0, shape: shape, naming: naming)
                    }
                }
            }
        }

        @ViewBuilder private var stack: some View {
            if shape == .stackSection {
                rows.focusSection()
            } else {
                rows
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if shape == .stackSection {
                    HStack(spacing: 1) {
                        Button("side0") {}.focusID("side0")
                        Button("side1") {}.focusID("side1")
                    }
                    .focusSection()
                } else {
                    Button("top") {}.focusID("top")
                }
                ScrollView { stack }.frame(height: 6)
                Button("bottom") {}.focusID("bottom")
            }
        }
    }

    /// What a focus id names, the same for the lazy page and its eager twin:
    /// `b07` / `t07` for a row's button and field, the scroll view, or the
    /// control outside the stack by its explicit id.
    static func name(_ id: String?) -> String {
        guard let id else { return "nothing" }
        if id.hasPrefix("scrollview") { return "scroll" }
        if ["top", "bottom", "side0", "side1"].contains(id) { return id }
        if id.wholeMatch(of: /[bt]\d\d/) != nil { return id }
        guard let match = id.matches(of: /\[(\d+)\]/).last, let index = Int(match.1) else { return id }
        let kind = id.lowercased().contains("textfield") || id.lowercased().contains("text-field") ? "t" : "b"
        return kind + pad(index)
    }

    private func app(lazy: Bool, _ shape: Shape, _ naming: Naming, arrows: ArrowFocus = .tabOrder) -> TestApp {
        let app = TestApp(width: 40, height: 14) { Page(lazy: lazy, shape: shape, naming: naming) }
        app.arrowFocus = arrows
        app.frame(atNanos: 16_666_667)
        return app
    }

    /// The controls `key` lands on, `times` presses, each marked `!` when a
    /// row's control it lands on is not on screen.
    private func walk(_ app: TestApp, _ key: Key, modifiers: EventModifiers = [], times: Int) -> [String] {
        var seen: [String] = []
        for _ in 0..<times {
            _ = app.press(key, modifiers: modifiers)
            let name = Self.name(app.focusedID)
            let isRow = name.wholeMatch(of: /[bt]\d\d/) != nil
            let shown = !isRow || app.screen.lines.contains { $0.contains(name) }
            seen.append(shown ? name : name + "!")
        }
        return seen
    }

    private static func diff(_ lazy: [String], _ eager: [String]) -> String {
        guard let first = zip(lazy, eager).enumerated().first(where: { $0.element.0 != $0.element.1 }) else {
            return lazy.count == eager.count ? "same" : "lengths \(lazy.count) vs \(eager.count)"
        }
        let from = max(0, first.offset - 3)
        return "step \(first.offset): lazy \(lazy[from..<min(lazy.count, first.offset + 4)])"
            + " eager \(eager[from..<min(eager.count, first.offset + 4)])"
    }

    /// The steps of a Tab walk from the page's first control that run through
    /// the stack once: into it, every row, and out.
    private static let throughSteps = 2 * rowCount + 3

    @Test("Tab walks every row of the lazy stack, drawn or not, as the eager one, and lands on screen",
          arguments: Shape.allCases)
    func tabWalk(_ shape: Shape) {
        let steps = 2 * Self.rowCount + 8
        let lazy = walk(app(lazy: true, shape, .automatic), .tab, times: steps)
        let eager = walk(app(lazy: false, shape, .automatic), .tab, times: steps)
        let through = Array(lazy.prefix(Self.throughSteps))
        let eagerThrough = Array(eager.prefix(Self.throughSteps))
        #expect(through == eagerThrough, "\(Self.diff(through, eagerThrough))\nlazy: \(lazy)\neager: \(eager)")
        #expect(!lazy.contains { $0.hasSuffix("!") }, "lazy focused off screen: \(lazy.filter { $0.hasSuffix("!") })")
        // Round past the end and into the stack again from the control above
        // its scroll view, the band now at the stack's end: the lazy stack is
        // entered at the band's first row (b33), the eager one at b00.
        withKnownIssue("LAZY-EDGE: Tab into the stack from outside its scroll view lands on the band's first row") {
            #expect(lazy == eager, "\(Self.diff(lazy, eager))")
        }
    }

    @Test("Shift-Tab into the lazy stack from below its scroll view enters at its last row, as the eager one",
          arguments: Shape.allCases)
    func shiftTabWalk(_ shape: Shape) {
        let steps = 2 * Self.rowCount + 8
        // From the first control, round to the last and up into the stack:
        // the lazy one is entered at the band's last row (t06), and Shift-Tab
        // then goes round rows 6 to 0 and the controls outside, never further.
        let lazy = walk(app(lazy: true, shape, .automatic), .tab, modifiers: .shift, times: steps)
        let eager = walk(app(lazy: false, shape, .automatic), .tab, modifiers: .shift, times: steps)
        #expect(!lazy.contains { $0.hasSuffix("!") }, "lazy focused off screen: \(lazy.filter { $0.hasSuffix("!") })")
        withKnownIssue("LAZY-EDGE: Shift-Tab into the stack lands on the band's last row, and goes round the band") {
            #expect(lazy == eager, "\(Self.diff(lazy, eager))\nlazy: \(lazy)\neager: \(eager)")
        }
    }

    @Test("Tab down, Shift-Tab back up past the rows scrolled off above, as the eager stack",
          arguments: Shape.allCases, Naming.allCases)
    func downThenUp(_ shape: Shape, _ naming: Naming) {
        let lazyApp = app(lazy: true, shape, naming)
        let eagerApp = app(lazy: false, shape, naming)
        let lazy = walk(lazyApp, .tab, times: 30) + walk(lazyApp, .tab, modifiers: .shift, times: 30)
        let eager = walk(eagerApp, .tab, times: 30) + walk(eagerApp, .tab, modifiers: .shift, times: 30)
        #expect(lazy == eager, "\(Self.diff(lazy, eager))\nlazy: \(lazy)\neager: \(eager)")
        #expect(!lazy.contains { $0.hasSuffix("!") }, "lazy focused off screen: \(lazy.filter { $0.hasSuffix("!") })")
    }

    @Test("Arrow Down and Up walk the lazy stack as the eager one, in either arrow mode",
          arguments: Shape.allCases, [ArrowFocus.tabOrder, .geometric])
    func arrowWalk(_ shape: Shape, _ arrows: ArrowFocus) {
        let lazyApp = app(lazy: true, shape, .automatic, arrows: arrows)
        let eagerApp = app(lazy: false, shape, .automatic, arrows: arrows)
        // Into the stack first: one Tab (two past the side section).
        let into = shape == .stackSection ? 2 : 1
        let lazy = walk(lazyApp, .tab, times: into) + walk(lazyApp, .down, times: 50)
            + walk(lazyApp, .up, times: 50)
        let eager = walk(eagerApp, .tab, times: into) + walk(eagerApp, .down, times: 50)
            + walk(eagerApp, .up, times: 50)
        #expect(!lazy.contains { $0.hasSuffix("!") }, "lazy focused off screen: \(lazy.filter { $0.hasSuffix("!") })")
        #expect(lazy == eager, "\(Self.diff(lazy, eager))\nlazy: \(lazy)\neager: \(eager)")
        // Geometric Up from the row at the viewport's top edge goes on to the
        // row above it, out of sight, not to the button above the scroll view,
        // which lies level with that row on screen (GEO-SCROLL-EDGE): the walk
        // up reaches the stack's first row before it leaves.
        if shape == .plain, arrows == .geometric {
            let up = lazy.suffix(50).prefix { $0 != "top" }
            #expect(up.contains("b00"), "Up left the scroll view before its first row: \(lazy.suffix(50))")
        }
    }
}
