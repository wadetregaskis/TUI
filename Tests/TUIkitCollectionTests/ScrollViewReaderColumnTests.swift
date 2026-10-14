//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewReaderColumnTests.swift
//
//  `scrollTo` on a purely horizontal `ScrollView`, which seeks a column of
//  the horizontal stack that is its content (DEVS #4; the semantic audit's
//  item 45). Apart from `ScrollViewReaderTests`, which seeks rows, for the
//  file-length guideline.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// `let _ = box.proxy = proxy` captures the proxy inside a `@ViewBuilder`
// closure, where `_ =` is not a statement the builder accepts.
// swiftlint:disable redundant_discardable_let

private final class ProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

@MainActor
@Suite("ScrollViewReader / scrollTo a column")
struct ScrollViewReaderColumnTests {
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(availableWidth: 30, availableHeight: 4, environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// A purely horizontal scroll view seeks COLUMNS: the horizontal stack at
    /// its origin finds the one the id names, and the anchor's `x` places it
    /// (the semantic audit's item 45; DEVS #4).
    @Test("scrollTo on a purely horizontal ScrollView seeks a column", arguments: [false, true])
    func horizontalOnlyScrollToSeeksAColumn(lazy: Bool) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let box = ProxyBox()
        // Three cells a column and one between: column i starts at 4i.
        let columns = ForEach(0..<40, id: \.self) { i in Text("c" + (i < 10 ? "0" : "") + "\(i)") }
        let view = ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            ScrollView(.horizontal) {
                if lazy {
                    LazyHStack(spacing: 1) { columns }
                } else {
                    HStack(spacing: 1) { columns }
                }
            }
            .frame(width: 30, height: 2)
        }
        let first = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(first.first?.hasPrefix("c00") == true, "starts at the start: \(first)")

        box.proxy?.scrollTo(20, anchor: .leading)
        let leading = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(leading.first?.hasPrefix("c20") == true, ".leading puts c20 first: \(leading)")

        box.proxy?.scrollTo(5)
        let minimal = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(minimal.first?.hasPrefix("c05") == true, "no anchor moves only as far as c05: \(minimal)")

        box.proxy?.scrollTo(30, anchor: .trailing)
        let trailing = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(trailing.first?.hasSuffix("c30") == true, ".trailing puts c30 last: \(trailing)")

        box.proxy?.scrollTo(999, anchor: .leading)
        let unknown = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        #expect(unknown.first == trailing.first, "an unknown id moves nothing: \(unknown)")
    }
}

// swiftlint:enable redundant_discardable_let
