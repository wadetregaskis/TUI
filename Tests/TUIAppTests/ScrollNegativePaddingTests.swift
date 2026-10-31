//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollNegativePaddingTests.swift
//
//  A negative `padding` between a scroll view and the stack that is its
//  content (NEG-PADDING): the stack's rows and columns are where the inset
//  draws them, so what a scroll view reads back and seeks takes the inset into
//  account as it does a positive one's, and a lazy stack shows what an eager
//  one does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

// `let _ = box.proxy = proxy` captures the proxy inside a `@ViewBuilder`
// closure, where `_ =` is not a statement the builder accepts.
// swiftlint:disable redundant_discardable_let

private final class ProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

@MainActor
@Suite("A negative padding on a scroll view's content")
struct ScrollNegativePaddingTests {
    @discardableResult
    private func renderFrame<V: View>(_ view: V, tui: TUIContext, focusManager: FocusManager) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Across

    /// Forty columns of three cells and one between, lazy or eager, under a
    /// leading inset of -2: column `i` at `4i - 2` in the scroll view's content.
    @ViewBuilder
    private func carousel(lazy: Bool) -> some View {
        let columns = ForEach(0..<40, id: \.self) { i in Text("c" + (i < 10 ? "0" : "") + "\(i)") }
        ScrollView(.horizontal) {
            if lazy {
                LazyHStack(spacing: 1) { columns }.padding(.leading, -2)
            } else {
                HStack(spacing: 1) { columns }.padding(.leading, -2)
            }
        }
        .frame(width: 30, height: 4)
    }

    private func columnLine(_ screen: [String]) -> String? { screen.first { $0.contains("c") } }

    @Test("scrollTo places a column under a negative leading inset", arguments: [false, true])
    func columnSeek(lazy: Bool) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            carousel(lazy: lazy)
        }
        renderFrame(view, tui: tui, focusManager: focusManager)

        box.proxy?.scrollTo(20, anchor: .leading)
        let leading = renderFrame(view, tui: tui, focusManager: focusManager)
        #expect(columnLine(leading)?.hasPrefix("c20") == true, ".leading puts c20 first: \(leading)")

        box.proxy?.scrollTo(30, anchor: .trailing)
        let trailing = renderFrame(view, tui: tui, focusManager: focusManager)
        #expect(columnLine(trailing)?.hasSuffix("c30") == true, ".trailing puts c30 last: \(trailing)")
    }

    /// At offset 77 the edge is the blank after column 19 (`4 × 19 - 2` to
    /// `+ 2`), which the row's rule reads as the column after it, 20. Sampled
    /// without the inset, at the stack's 77, it is column 19.
    @Test("The column read back under a negative leading inset is the one at the edge", arguments: [false, true])
    func columnReadBack(lazy: Bool) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition(idType: Int.self)
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = carousel(lazy: lazy).scrollPosition(binding)
        renderFrame(view, tui: tui, focusManager: focusManager)
        position.scrollTo(x: 77)
        renderFrame(view, tui: tui, focusManager: focusManager)
        let screen = renderFrame(view, tui: tui, focusManager: focusManager)
        #expect(columnLine(screen)?.hasPrefix("c20") == true, "precondition: \(screen)")
        #expect(position.viewID(type: Int.self) == 20, "\(screen)")
    }

    // MARK: - Down

    /// 400 rows: past the 256 under which a lazy stack draws its whole canvas,
    /// so it draws a band, and the band is what an inset has to be relayed to.
    @ViewBuilder
    private func rows(lazy: Bool, insets: EdgeInsets) -> some View {
        let rows = ForEach(0..<400, id: \.self) { i in Text("r\(i)") }
        ScrollView {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 0) { rows }.padding(insets)
            } else {
                VStack(alignment: .leading, spacing: 0) { rows }.padding(insets)
            }
        }
        .frame(width: 12, height: 6)
    }

    private func screen(lazy: Bool, insets: EdgeInsets, offset: Int) -> [String] {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition(idType: Int.self)
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = rows(lazy: lazy, insets: insets).scrollPosition(binding)
        renderFrame(view, tui: tui, focusManager: focusManager)
        position.scrollTo(y: offset)
        renderFrame(view, tui: tui, focusManager: focusManager)
        return renderFrame(view, tui: tui, focusManager: focusManager)
    }

    @Test(
        "A lazy stack shows what an eager one does under a negative top or bottom inset",
        arguments: [
            EdgeInsets(top: -2, leading: 0, bottom: 0, trailing: 0),
            EdgeInsets(top: 0, leading: 0, bottom: -2, trailing: 0),
            EdgeInsets(top: -2, leading: 0, bottom: -2, trailing: 0),
        ], [0, 1, 5, 200, 390, 1000])
    func lazyMatchesEager(insets: EdgeInsets, offset: Int) {
        let lazy = screen(lazy: true, insets: insets, offset: offset)
        let eager = screen(lazy: false, insets: insets, offset: offset)
        #expect(lazy == eager, "offset \(offset)")
    }
}

// swiftlint:enable redundant_discardable_let
