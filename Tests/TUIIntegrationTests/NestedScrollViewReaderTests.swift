//  🖥️ TUI — A Terminal UI framework for Swift
//  NestedScrollViewReaderTests.swift
//
//  A `ScrollViewReader` inside a scroll view's content scrolls the nearest
//  scroll view around it that scrolls, as in SwiftUI: the scroll view itself,
//  or, when that is a vertical scroll view nested in a vertical one's content
//  and forwards its content to it (SCROLL-FIT P7, `ScrollView+Nested.swift`),
//  the outer one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Holds the proxy the reader hands its content, for the test to call.
@MainActor private final class ProxyBox { var proxy: ScrollViewProxy? }

/// A title, a reader's rows (in a scroll view of their own, or not), and a
/// line below them, in a scroll view.
private struct ReaderPage: View {
    let nested: Bool
    let box: ProxyBox

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                if nested {
                    ScrollView { reader }
                } else {
                    reader
                }
                Text("below")
            }
        }
    }

    private var reader: some View {
        ScrollViewReader { proxy in
            // swiftlint:disable:next redundant_discardable_let
            let _ = box.proxy = proxy
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<400, id: \.self) { Text(verbatim: "r\($0)") }
            }
        }
    }
}

@MainActor
@Suite("A ScrollViewReader inside a scroll view scrolls the nearest one that scrolls")
struct NestedScrollViewReaderTests {
    @Test("scrollTo from a reader in the scroll view's content, or in a nested one it forwards", arguments: [false, true])
    func readerInsideScrolls(_ nested: Bool) {
        let box = ProxyBox()
        let app = TestApp(width: 30, height: 12) { ReaderPage(nested: nested, box: box) }
        #expect(app.screen.contains("title"), "\(app.screen)")
        box.proxy?.scrollTo(300, anchor: .top)
        app.advance(by: .zero)
        #expect(app.screen.lines.first?.hasPrefix("r300") == true, "\(app.screen)")
        box.proxy?.scrollTo(399)
        app.advance(by: .zero)
        #expect(app.screen.contains("r399"), "\(app.screen)")
        #expect(!app.screen.contains("r300"), "\(app.screen)")
    }
}
