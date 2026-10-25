//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollPositionsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Scrolling to a place, and knowing where you are: `ScrollViewReader` and its
/// proxy's `scrollTo(_:anchor:)` — inside `withAnimation`, so it glides there
/// (decisions B27-ANIMATING), as the keys do under `.scrollKeyboardAnimation()`
/// — `.scrollPosition(id:)` reporting the row at
/// the top, `.safeAreaInset` pinning a line of its own under the rows, and
/// `.containerRelativeFrame` sizing cards to a share of the scroll view.
struct ScrollPositionsDemo: View {
    /// The row at the top of the viewport, written by the scroll view as it
    /// scrolls — and, written here, a place to scroll to.
    @State private var topRow: Int? = 0

    private static let rowCount = 50

    var body: some View {
        DemoSection("page.scrollView.positionsSection") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.scrollView.positionsBody")
                    .foregroundStyle(.palette.foregroundSecondary)
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Button("page.scrollView.positions.first") {
                                withAnimation { proxy.scrollTo(0, anchor: .top) }
                            }
                            Button("page.scrollView.positions.middle") {
                                withAnimation { proxy.scrollTo(Self.rowCount / 2, anchor: .center) }
                            }
                            Button("page.scrollView.positions.last") {
                                withAnimation { proxy.scrollTo(Self.rowCount - 1, anchor: .bottom) }
                            }
                            // Writing the binding scrolls too.
                            Button("page.scrollView.positions.ten") { topRow = 10 }
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(0..<Self.rowCount, id: \.self) { row in
                                    Text("\(L("page.scrollView.positions.row")) \(row)")
                                }
                            }
                        }
                        .scrollPosition(id: $topRow)
                        // Page Up/Down, Home and End glide too (TUI-specific).
                        .scrollKeyboardAnimation()
                        // A line of the scroll view's own, under its rows: the
                        // rows scroll above it and never behind it.
                        .safeAreaInset(edge: .bottom) {
                            Text("\(L("page.scrollView.positions.top")) \(topRow.map(String.init) ?? "—")")
                                .foregroundStyle(.palette.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 40, height: 9)
                        .border(.palette.border)
                    }
                }
                // Each card a third of the scroll view's width, whatever that is.
                Text("page.scrollView.positions.cards")
                    .foregroundStyle(.palette.foregroundSecondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 1) {
                        ForEach(1...7, id: \.self) { card in
                            Text("\(L("page.scrollView.positions.card")) \(card)")
                                .frame(maxWidth: .infinity)
                                .border(.palette.border)
                                .containerRelativeFrame(.horizontal, count: 3, spacing: 1)
                        }
                    }
                }
                .frame(width: 60, height: 4)
            }
        }
    }
}
