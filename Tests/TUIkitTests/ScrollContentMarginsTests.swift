//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollContentMarginsTests.swift
//
//  `contentMargins`: space a scroll view keeps around its content, inside the
//  scrollable area. The SwiftUI behaviours pinned here were measured on macOS
//  15 (Documentation/SwiftUI-API-completion-decisions.md names the
//  probes).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Scroll content margins")
struct ScrollContentMarginsTests {

    private func lines<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> [String] {
        var environment = EnvironmentValues()
        environment.verticalScrollIndicatorVisibility = .hidden
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    /// Renders frames the way the run loop does, so the handler persists.
    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    private func rows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { Text("row \($0)") }
        }
    }

    // MARK: - Drawing

    @Test("Vertical margins are blank lines that scroll with the content")
    func verticalMarginsScroll() {
        let frames = Frames()
        let view = ScrollView { rows(20) }.contentMargins(.vertical, 2)
        let top = frames.render(view)
        #expect(top[0].trimmingCharacters(in: .whitespaces).isEmpty, "\(top)")
        #expect(top[1].trimmingCharacters(in: .whitespaces).isEmpty, "\(top)")
        #expect(top[2].hasPrefix("row 0"), "\(top)")

        frames.handler?.userScrollToBottom()
        let bottom = frames.render(view)
        // The last row, then the bottom margin: two lines of it.
        #expect(bottom[3].hasPrefix("row 19"), "\(bottom)")
        #expect(bottom[4].trimmingCharacters(in: .whitespaces).isEmpty, "\(bottom)")
        #expect(bottom[5].trimmingCharacters(in: .whitespaces).isEmpty, "\(bottom)")

        // Scrolled two lines, the top margin has gone with the content.
        frames.handler?.scrollToTop()
        frames.handler?.userScrollFine(by: 2)
        let scrolled = frames.render(view)
        #expect(scrolled[0].hasPrefix("row 0"), "\(scrolled)")
    }

    @Test("Horizontal margins inset the content, which is laid out in what is left")
    func horizontalMarginsInset() {
        let drawn = lines(
            ScrollView { Text("abcd efgh") }.contentMargins(.horizontal, 3), width: 10)
        // Ten columns, three either side: four left, so the text wraps at four.
        #expect(drawn[0] == "   abcd   ", "\(drawn)")
        #expect(drawn[1] == "   efgh   ", "\(drawn)")
    }

    @Test("A horizontal scroll view's margins scroll with its content")
    func horizontalScrollMargins() {
        let drawn = lines(
            ScrollView(.horizontal) { Text(String(repeating: "x", count: 30)) }
                .scrollIndicators(.hidden)
                .contentMargins(.leading, 2),
            width: 10, height: 3)
        #expect(drawn[0] == "  xxxxxxxx", "\(drawn)")
    }

    @Test("A margin is never wider than the space, which keeps a column for the content")
    func oversizedMarginsKeepAColumn() {
        let drawn = lines(ScrollView { Text("ab") }.contentMargins(.horizontal, 30), width: 8)
        #expect(drawn.allSatisfy { $0.count == 8 }, "no line is wider than the view: \(drawn)")
        #expect(drawn[0].contains { $0 != " " }, "the content still draws: \(drawn)")
    }

    @Test("No margins, or nil, draw exactly what no modifier draws")
    func zeroMarginsChangeNothing() {
        let plain = lines(ScrollView { rows(3) })
        #expect(lines(ScrollView { rows(3) }.contentMargins(0)) == plain)
        #expect(lines(ScrollView { rows(3) }.contentMargins(.all, nil)) == plain)
    }

    // MARK: - Combining

    @Test("Margins combine edge by edge, and a specific placement beats automatic either way round")
    func marginResolution() {
        var margins = ContentMargins()
        // Applied outer first, as the environment flows: outer horizontal 10,
        // inner top 20.
        margins.state(.horizontal, EdgeInsets(all: 10), for: .automatic)
        margins.state(.top, EdgeInsets(all: 20), for: .automatic)
        #expect(margins.content == EdgeInsets(top: 20, leading: 10, bottom: 0, trailing: 10))

        var specificOuter = ContentMargins()
        specificOuter.state(.all, EdgeInsets(all: 20), for: .scrollContent)
        specificOuter.state(.all, EdgeInsets(all: 5), for: .automatic)
        #expect(specificOuter.content == EdgeInsets(all: 20))
        #expect(specificOuter.indicators == EdgeInsets(all: 5))

        var specificInner = ContentMargins()
        specificInner.state(.all, EdgeInsets(all: 5), for: .automatic)
        specificInner.state(.all, EdgeInsets(all: 20), for: .scrollContent)
        #expect(specificInner.content == EdgeInsets(all: 20))

        var indicatorsOnly = ContentMargins()
        indicatorsOnly.state(.all, EdgeInsets(all: 4), for: .scrollIndicators)
        #expect(indicatorsOnly.content.isZero)
    }

    @Test("Indicator margins leave the content where it was")
    func indicatorMarginsLeaveContent() {
        let plain = lines(ScrollView { rows(3) })
        #expect(lines(ScrollView { rows(3) }.contentMargins(2, for: .scrollIndicators)) == plain)
    }

    /// The default style's bar, with its arrows, over content that overflows.
    private func barred<V: View>(_ view: V, width: Int = 12, height: Int = 6) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: EnvironmentValues(), tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    @Test("A vertical bar is shortened by the top and bottom margins and moved in by the trailing one")
    func verticalBarMargins() {
        let plain = barred(ScrollView { rows(20) }).lines.map(\.stripped)
        #expect(plain[0].last == "▲" && plain[5].last == "▼", "precondition: \(plain)")

        let buffer = barred(
            ScrollView { rows(20) }.contentMargins(.vertical, 1, for: .scrollIndicators))
        let drawn = buffer.lines.map(\.stripped)
        #expect(drawn[0].last == " " && drawn[1].last == "▲", "\(drawn)")
        #expect(drawn[4].last == "▼" && drawn[5].last == " ", "\(drawn)")
        // The bar's hit region is where it is drawn.
        #expect(
            buffer.hitTestRegions.contains { $0.offsetX == 11 && $0.width == 1 && $0.offsetY == 1 && $0.height == 4 },
            "\(buffer.hitTestRegions)")

        let inset = barred(ScrollView { rows(20) }.contentMargins(.trailing, 2, for: .scrollIndicators))
            .lines.map(\.stripped)
        #expect(inset[0].hasSuffix("▲  "), "\(inset)")
        #expect(inset.allSatisfy { $0.count == 12 }, "\(inset)")

        // `.automatic` insets the bar as well as the content.
        let automatic = barred(ScrollView { rows(20) }.contentMargins(.top, 1)).lines.map(\.stripped)
        #expect(automatic[0].trimmingCharacters(in: .whitespaces).isEmpty && automatic[1].last == "▲", "\(automatic)")
    }

    @Test("A horizontal bar is shortened by the leading and trailing margins and lifted by the bottom one")
    func horizontalBarMargins() {
        let wide = ScrollView(.horizontal) { Text(String(repeating: "x", count: 40)) }
        let plain = barred(wide, height: 4).lines.map(\.stripped)
        let barRow = plain.firstIndex { $0.hasPrefix("◀") }
        #expect(barRow != nil, "precondition: \(plain)")

        let buffer = barred(
            wide.contentMargins(.leading, 2, for: .scrollIndicators)
                .contentMargins(.bottom, 1, for: .scrollIndicators),
            height: 4)
        let drawn = buffer.lines.map(\.stripped)
        let lifted = drawn.firstIndex { $0.contains("◀") }
        #expect(lifted.map { drawn[$0].hasPrefix("  ◀") } == true, "\(drawn)")
        #expect(lifted == drawn.count - 2, "\(drawn)")
        #expect(drawn.last?.trimmingCharacters(in: .whitespaces).isEmpty == true, "\(drawn)")
        #expect(
            buffer.hitTestRegions.contains {
                $0.offsetX == 2 && $0.width == 10 && $0.height == 1 && $0.offsetY == drawn.count - 2
            },
            "\(buffer.hitTestRegions)")
    }

    @Test("Margins that leave no room still leave a one-cell bar")
    func oversizedIndicatorMargins() {
        let drawn = barred(ScrollView { rows(20) }.contentMargins(.vertical, 10, for: .scrollIndicators))
            .lines.map(\.stripped)
        #expect(drawn.count == 6)
        #expect(drawn.allSatisfy { $0.count == 12 }, "\(drawn)")
    }

    @Test("A scroll view in the content does not inherit the margins")
    func nestedScrollViewDoesNotInherit() {
        let drawn = lines(
            ScrollView {
                ScrollView(.horizontal) { Text("inner") }
                    .scrollIndicators(.hidden)
                    .frame(height: 1)
            }
            .contentMargins(.leading, 2),
            width: 12, height: 3)
        // Two columns from the outer view's margin, and none from the inner.
        #expect(drawn[0].hasPrefix("  inner"), "\(drawn)")
    }

    // MARK: - What rides the content

    @Test("A lazy stack under a top margin still windows, seeks and reports its row")
    func lazyStackUnderMargins() {
        let frames = Frames()
        var position = ScrollPosition(idType: Int.self)
        let binding = Binding(get: { position }, set: { position = $0 })
        var appeared = Set<Int>()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<2_000, id: \.self) { index in
                    Text("row \(index)").onAppear { appeared.insert(index) }
                }
            }
        }
        .scrollPosition(binding)
        .contentMargins(.top, 3)

        let first = frames.render(view)
        #expect(first[3].hasPrefix("row 0"), "\(first)")
        #expect(position.viewID(type: Int.self) == 0)
        // Windowed: a screenful appeared, not two thousand rows.
        #expect(appeared.count < 50, "\(appeared.count) rows appeared")

        position.scrollTo(id: 1_000, anchor: .top)
        let landed = frames.render(view)
        #expect(landed[0].hasPrefix("row 1000"), "\(landed)")
        #expect(appeared.count < 100, "\(appeared.count) rows appeared")
    }

    @Test("A focused control in the content is revealed where the margins put it")
    func revealAccountsForMargins() {
        let frames = Frames()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { index in
                    Button("button \(index)") {}.focusID("b\(index)")
                }
            }
        }
        .contentMargins(.top, 2)
        frames.render(view)
        frames.focusManager.focus(id: "b15")
        frames.render(view)
        let revealed = frames.render(view)
        #expect(revealed.contains { $0.contains("button 15") }, "\(revealed)")
    }

    @Test("containerRelativeFrame sizes against the viewport less the margins")
    func containerExcludesMargins() {
        var measured: Int?
        _ = lines(
            ScrollView {
                Text("x").containerRelativeFrame(.horizontal)
                    .onGeometryChange(for: Int.self) { $0.size.width } action: { measured = $0 }
            }
            .contentMargins(.horizontal, 3),
            width: 20)
        #expect(measured == 14)
    }

    @Test("The content keeps its state when margins come and go")
    func contentIdentityIsStable() {
        let frames = Frames()
        struct Counter: View {
            @State private var count = 0
            var body: some View {
                Button("count \(count)") { count += 1 }.focusID("counter")
            }
        }
        frames.render(ScrollView { Counter() })
        frames.focusManager.focus(id: "counter")
        frames.render(ScrollView { Counter() })
        _ = frames.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        let before = frames.render(ScrollView { Counter() })
        #expect(before.contains { $0.contains("count 1") }, "\(before)")
        let after = frames.render(ScrollView { Counter() }.contentMargins(.leading, 1))
        #expect(after.contains { $0.contains(" count 1") }, "\(after)")
    }

    // MARK: - Other views

    @Test("A grouped Form is padded by its content margins; a columns Form and a List are not")
    func formAndListMargins() {
        func indent(_ drawn: [String]) -> Int? {
            drawn.first { $0.contains("field") }.map { line in
                line.distance(from: line.startIndex, to: line.firstIndex(of: "f")!)
            }
        }
        let grouped = lines(
            Form { Text("field") }.formStyle(.grouped).contentMargins(.leading, 4), width: 30)
        let groupedPlain = lines(Form { Text("field") }.formStyle(.grouped), width: 30)
        #expect(indent(groupedPlain) != nil, "\(groupedPlain)")
        #expect(indent(grouped) == indent(groupedPlain).map { $0 + 4 }, "\(groupedPlain) vs \(grouped)")

        #expect(
            lines(Form { Text("field") }.contentMargins(.leading, 4), width: 30)
                == lines(Form { Text("field") }, width: 30))
        #expect(
            lines(List { Text("a"); Text("b") }.contentMargins(.leading, 4), width: 30)
                == lines(List { Text("a"); Text("b") }, width: 30))
    }

    // MARK: - The framework's own scrollers

    @Test("A tall inline menu takes none of the page's margins: its rows draw as they do without them")
    func chromeScrollerTakesNoMargins() {
        func menu(margin: Int) -> [String] {
            lines(
                VStack {
                    Menu("Pick") {
                        ForEach(0..<60, id: \.self) { index in Button("item \(index)") {} }
                    }
                    .menuStyle(.inline)
                }
                .contentMargins(margin),
                width: 30, height: 14)
        }
        let plain = menu(margin: 0)
        #expect(plain.contains { $0.contains("item 9") }, "the menu scrolls inside its box: \(plain)")
        // Inset inside a width planned without the margins, the labels wrapped.
        #expect(menu(margin: 1) == plain, "\(menu(margin: 1))")
    }

    @Test("A dialog's scroller passes the page's margins on to the scroll view inside it")
    func chromeScrollerPassesMarginsOn() {
        func dialog(margin: Int) -> [String] {
            lines(
                Dialog(title: "T") {
                    ScrollView { rows(30) }.frame(height: 5)
                }
                .contentMargins(.top, margin),
                width: 30, height: 14)
        }
        func rowLines(_ drawn: [String]) -> Int { drawn.count { $0.contains("row ") } }
        func boxHeight(_ drawn: [String]) -> Int {
            drawn.count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        let plain = dialog(margin: 0)
        #expect(rowLines(plain) == 5, "\(plain)")
        // The inner scroll view keeps the two lines inside its own five, as it
        // would with no dialog around it; the dialog's scroller adds none.
        let margined = dialog(margin: 2)
        #expect(rowLines(margined) == 3, "\(margined)")
        #expect(boxHeight(margined) == boxHeight(plain), "\(plain) vs \(margined)")
    }
}
