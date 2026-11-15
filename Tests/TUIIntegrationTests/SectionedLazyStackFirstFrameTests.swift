//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionedLazyStackFirstFrameTests.swift
//
//  A lazy stack of a few sections, each a long loop, in a scroll view —
//  `LazyVStack { Section { ForEach(0..<10_000) } }`, two such sections, or a
//  title above one — builds only the rows on screen from its first frame,
//  pinning its sections' headers or not, and draws what the same content in
//  an eager `VStack` draws, the header of the section under the top edge
//  pinned there when the stack pins.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUI
import TUITesting

/// Counts row bodies built.
@MainActor private final class Builds { var count = 0 }

@MainActor
@Suite("A lazy stack of a few long sections builds only what shows, from its first frame")
struct SectionedLazyStackFirstFrameTests {
    enum Shape: CaseIterable { case one, two, titled }

    /// A row of section `section`.
    private static func row(_ section: Int, _ index: Int) -> Text {
        Text(verbatim: index.isMultiple(of: 3) ? "s\(section) row \(index)" : "s\(section) r\(index)")
    }

    /// `shape`'s content, its loops `rows` long, in a lazy stack pinning its
    /// sections' headers or not, or in an eager `VStack` as wide as the scroll
    /// view (a lazy stack fills its width).
    private static func app(
        _ shape: Shape, rows: Int, lazy: Bool = true, pinned: Bool = false, spacing: Int = 0,
        alignment: HorizontalAlignment = .leading, builds: Builds = Builds()
    ) -> TestApp {
        func section(_ index: Int) -> some View {
            Section {
                ForEach(0..<rows, id: \.self) { row in
                    builds.count += 1
                    return Self.row(index, row)
                }
            } header: {
                Text(verbatim: "Header \(index)")
            }
        }
        @ViewBuilder func content() -> some View {
            switch shape {
            case .one: section(0)
            case .two: section(0); section(1)
            case .titled: Text("a title"); section(0)
            }
        }
        // Each shape's own stack: a `switch` inside the stack's builder would
        // make its content a conditional, not the shape.
        let stack: AnyView
        switch (shape, lazy) {
        case (.one, true):
            stack = AnyView(LazyVStack(alignment: alignment, spacing: spacing, pinnedViews: pinned ? .sectionHeaders : []) {
                section(0)
            })
        case (.two, true):
            stack = AnyView(LazyVStack(alignment: alignment, spacing: spacing, pinnedViews: pinned ? .sectionHeaders : []) {
                section(0)
                section(1)
            })
        case (.titled, true):
            stack = AnyView(LazyVStack(alignment: alignment, spacing: spacing, pinnedViews: pinned ? .sectionHeaders : []) {
                Text("a title")
                section(0)
            })
        case (_, false):
            stack = AnyView(
                VStack(alignment: alignment, spacing: spacing) { content() }
                    .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading))
        }
        return TestApp(width: 30, height: 12) { ScrollView { stack } }
    }

    /// The rows built on the first frame and on each of three page-downs.
    private static func built(_ shape: Shape, rows: Int, pinned: Bool) -> [Int] {
        let builds = Builds()
        let app = app(shape, rows: rows, pinned: pinned, builds: builds)
        _ = app.screen
        var counts = [builds.count]
        for _ in 0..<3 {
            builds.count = 0
            _ = app.press(.pageDown)
            counts.append(builds.count)
        }
        return counts
    }

    @Test(
        "The rows built on the first frame and each page do not grow with the row count",
        arguments: Shape.allCases, [false, true])
    func firstFrameBuildsWhatShows(_ shape: Shape, _ pinned: Bool) {
        let small = Self.built(shape, rows: 1_000, pinned: pinned)
        let tall = Self.built(shape, rows: 10_000, pinned: pinned)
        // Before: 30,035 (one section), 60,035 (two) and 30,032 (titled)
        // unpinned, and 110,000 (two) and 60,000 (titled) pinned, on the
        // first frame: every row built for each measure of the stack.
        #expect(tall.allSatisfy { $0 < 150 }, "\(tall)")
        #expect(tall == small, "\(tall) \(small)")
    }

    /// The screen without the scroll bar's column.
    private static func content(_ app: TestApp) -> [String] { app.screen.lines.map { String($0.prefix(29)) } }

    /// The places the twins are compared at: the top, paged down through the
    /// first section into the second, the end, and paged up from it.
    private static func positions(_ apps: [TestApp], check: (String) -> Void) {
        check("top")
        for page in 1...30 {
            for app in apps { _ = app.press(.pageDown) }
            check("page \(page)")
        }
        for app in apps { _ = app.press(.end) }
        check("end")
        for page in 1...2 {
            for app in apps { _ = app.press(.pageUp) }
            check("end, page up \(page)")
        }
    }

    @Test(
        "Unpinned, it draws what the same content drawn whole draws, at its alignment and spacing",
        arguments: Shape.allCases, [(HorizontalAlignment.leading, 1), (.trailing, 0)])
    func drawsWhatTheWholeContentDraws(_ shape: Shape, _ layout: (HorizontalAlignment, Int)) {
        let lazy = Self.app(shape, rows: 280, spacing: layout.1, alignment: layout.0)
        let whole = Self.app(shape, rows: 280, lazy: false, spacing: layout.1, alignment: layout.0)
        Self.positions([lazy, whole]) { step in
            #expect(Self.content(lazy) == Self.content(whole), "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
    }

    @Test(
        "Pinned, it draws the same, the header of the section under the top edge on the first line",
        arguments: Shape.allCases, [HorizontalAlignment.leading, .trailing])
    func pinnedHeaders(_ shape: Shape, _ alignment: HorizontalAlignment) {
        let lazy = Self.app(shape, rows: 280, pinned: true, alignment: alignment)
        let whole = Self.app(shape, rows: 280, lazy: false, alignment: alignment)
        Self.positions([lazy, whole]) { step in
            let drawn = Self.content(lazy)
            var expected = Self.content(whole)
            // The eager column pins nothing: where its first line is a row,
            // the pinned stack draws that row's section's header over it.
            let first = expected[0].trimmingCharacters(in: .whitespaces)
            if first.hasPrefix("s"), let section = first.dropFirst().split(separator: " ").first {
                let header = "Header \(section)"
                let pad = String(repeating: " ", count: max(0, 29 - header.count))
                expected[0] = alignment == .trailing ? pad + header : header + pad
            }
            #expect(drawn == expected, "\(step):\n\(lazy.screen)\n---\n\(whole.screen)")
        }
    }

    @Test("Pinning its sections' footers, the footer of the section under the bottom edge is on the last line")
    func pinnedFooters() {
        let app = TestApp(width: 30, height: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionFooters) {
                    ForEach(0..<2, id: \.self) { section in
                        Section {
                            ForEach(0..<300, id: \.self) { Self.row(section, $0) }
                        } footer: {
                            Text(verbatim: "Footer \(section)")
                        }
                    }
                }
            }
        }
        for page in 0..<30 {
            if page > 0 { _ = app.press(.pageDown) }
            let lines = app.screen.lines.map { String($0.prefix(29)).trimmingCharacters(in: .whitespaces) }
            guard let beside = lines.dropLast().last(where: { $0.hasPrefix("s") }),
                let section = beside.dropFirst().split(separator: " ").first
            else { continue }
            #expect(lines.last == "Footer \(section)", "page \(page):\n\(app.screen)")
        }
    }
}
