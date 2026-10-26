//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPagerContainerTests.swift
//
//  A two-axis pager's container and its step (scroll lane review 3, item 2):
//  a horizontal bar's row comes off the page `.paging` steps, so it comes off
//  the `containerRelativeFrame` container too — known up front under
//  `.visible`, decided first by a measure under `.automatic` (B-FU2-2) — and
//  a container-sized page is the page that is stepped.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A pager's container and its step")
struct ScrollPagerContainerTests {

    /// SwiftUI's paging idiom, wide enough to scroll across: pages as tall as
    /// the container, each marking its first and last line.
    private func widePages(_ count: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 0) {
                    Text("top \(index) " + String(repeating: "-", count: 40))
                    Spacer(minLength: 0)
                    Text("end \(index)")
                }
                .containerRelativeFrame(.vertical)
            }
        }
    }

    /// The review's drift: the step took the bar's row off the page and the
    /// container did not, so every page was a line taller than the step and
    /// each stop showed one line more of the page before it.
    @Test("With a horizontal bar always drawn, every stop shows one container-sized page whole")
    func pagesAreTheStepUnderAVisibleBar() {
        let frames = ScrollTargetFrames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) { widePages(5) }
            .scrollIndicators(.visible, axes: .horizontal)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        for page in 0..<4 {
            // Nine lines of content above the bar's row.
            let lines = frames.last.lines.map(\.stripped)
            #expect(lines[0].hasPrefix("top \(page)"), "page \(page): \(lines)")
            #expect(lines[8].hasPrefix("end \(page)"), "page \(page): \(lines)")
            frames.wheel(.scrollDown)
            frames.render(view)
        }
    }

    /// The bar the content's width brings is decided before the container is
    /// published (decisions FU2 B-FU2-2), so the pages lose its row too.
    @Test("With an automatic horizontal bar the content brings, every stop shows one container-sized page whole")
    func pagesAreTheStepUnderAnAutomaticBar() {
        let frames = ScrollTargetFrames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) { widePages(5) }
            .scrollIndicators(.automatic, axes: .horizontal)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        for page in 0..<4 {
            let lines = frames.last.lines.map(\.stripped)
            #expect(lines[0].hasPrefix("top \(page)"), "page \(page): \(lines)")
            #expect(lines[8].hasPrefix("end \(page)"), "page \(page): \(lines)")
            frames.wheel(.scrollDown)
            frames.render(view)
        }
    }

    /// Pages that fit across bring no bar, and keep the whole height.
    @Test("With an automatic horizontal bar and pages that fit across, the pages keep the whole height")
    func narrowPagesKeepTheBarsRow() {
        let frames = ScrollTargetFrames(width: 20, height: 10)
        let pages = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 0) {
                    Text("top \(index)")
                    Spacer(minLength: 0)
                    Text("end \(index)")
                }
                .containerRelativeFrame(.vertical)
            }
        }
        let view = ScrollView([.horizontal, .vertical]) { pages }
            .scrollIndicators(.automatic, axes: .horizontal)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        let lines = frames.last.lines.map(\.stripped)
        #expect(lines[0].hasPrefix("top 1") && lines[9].hasPrefix("end 1"), "\(lines)")
    }

    /// A carousel of cards as large as the scroll view: the bar the cards
    /// bring takes its row off them, so each card's last line is above it.
    @Test("A horizontal pager's container-sized cards end above the automatic bar they bring")
    func horizontalCardsEndAboveTheBar() {
        let frames = ScrollTargetFrames(width: 20, height: 6)
        let cards = LazyHStack(alignment: .top, spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 0) {
                    Text("card \(index)")
                    Spacer(minLength: 0)
                    Text("foot \(index)")
                }
                .containerRelativeFrame([.horizontal, .vertical])
            }
        }
        let view = ScrollView(.horizontal) { cards }
            .scrollIndicators(.automatic, axes: .horizontal)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        for card in 0..<3 {
            let lines = frames.last.lines.map(\.stripped)
            #expect(lines[0].contains("card \(card)") && lines[4].contains("foot \(card)"), "card \(card): \(lines)")
            frames.wheel(.scrollRight)
            frames.render(view)
        }
    }
}
