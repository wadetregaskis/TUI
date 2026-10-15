//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollPagerContainerTests.swift
//
//  A two-axis pager's container and its step (scroll lane review 3, item 2):
//  a horizontal bar's row comes off the page `.paging` steps, so where the bar
//  is known up front it comes off the `containerRelativeFrame` container too,
//  and a container-sized page is the page that is stepped.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

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
}
