//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PinnedSectionChromeTests.swift
//
//  `LazyVStack(pinnedViews:)`: a section's header stays at the scroll view's
//  top edge while its content is under it and is pushed off by the content's
//  last row; a footer stays at the bottom edge, never above the content's
//  first row (SwiftUI's rule, measured on macOS 15.8).
//
//  The oracle is the same stack unpinned, scrolled to the same line: pinning
//  draws a one-line header over the line at the top edge exactly when that
//  line is a row of its section, and a footer over the line at the bottom
//  edge on the same condition, and changes nothing else. So whatever path the
//  stack's rows take — the uniform window, the exact walk, the anchored
//  window, or none, under a title — each pinned screen is its twin's with at
//  most those two lines replaced.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The path the pinned stack's rows take.
enum PinnedStackPath: CaseIterable, CustomTestStringConvertible {
    /// Three hundred sections of two rows: every row of the stack four lines
    /// tall, the uniform window.
    case uniform
    /// Forty sections of one to three rows: the exact walk under 256 rows.
    case exactWalk
    /// Three hundred sections of one to three rows: the anchored window.
    case anchored
    /// Forty sections under a title line: not at the content's origin, so
    /// drawn whole, with no window at all.
    case nested
    /// Forty sections of two to four views in a two-column `LazyVGrid`: a
    /// section's views take one or two lines.
    case grid

    var testDescription: String { "\(self)" }

    var count: Int { self == .uniform || self == .anchored ? 300 : 40 }

    func rows(in section: Int) -> Int {
        switch self {
        case .uniform: 2
        case .grid: section % 3 + 2
        default: section % 3 + 1
        }
    }
}

/// Holds a scroll position for a test to move at "event time".
final class PinnedPositionBox: @unchecked Sendable {
    var position = ScrollPosition()
}

/// The sections, one header, rows and one footer each, in a lazy stack that
/// pins `pinnedViews`.
private struct PinnedSections: View {
    let path: PinnedStackPath
    let pinnedViews: PinnedScrollableViews

    var body: some View {
        if path == .nested {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                stack
            }
        } else if path == .grid {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                pinnedViews: pinnedViews
            ) {
                sections
            }
        } else {
            stack
        }
    }

    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinnedViews) { sections }
    }

    private var sections: some View {
        ForEach(0..<path.count, id: \.self) { section in
            Section {
                ForEach(0..<path.rows(in: section), id: \.self) { Text("row \(section).\($0)") }
            } header: {
                Text("Header \(section)")
            } footer: {
                Text("Footer \(section)")
            }
        }
    }
}

/// A scroll view eight lines tall over `content`.
private struct PinnedPage<Content: View>: View {
    let box: PinnedPositionBox
    let style: ScrollIndicatorStyle
    let content: Content

    var body: some View {
        ScrollView { content }
            .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
            .scrollIndicatorStyle(style)
            .frame(height: 8)
    }
}

/// The section a screen line is a ROW of, or `nil` for a header, a footer, a
/// title or an indicator line.
private func section(ofRow line: String) -> Int? {
    line.firstMatch(of: /^row (\d+)\./).flatMap { Int($0.1) }
}

/// What the pinned stack shows where its unpinned twin shows `screen`: the
/// lines at the top and bottom edges — under the "N more" lines, when drawn —
/// replaced by their section's header and footer when they are its rows.
private func pinned(_ screen: [String], pinning views: PinnedScrollableViews) -> [String] {
    var expected = screen
    let top = screen.first == "<more>" ? 1 : 0
    let bottom = screen.last == "<more>" ? screen.count - 2 : screen.count - 1
    if views.contains(.sectionHeaders), let section = section(ofRow: screen[top]) {
        expected[top] = "Header \(section)"
    }
    if views.contains(.sectionFooters), let section = section(ofRow: screen[bottom]) {
        expected[bottom] = "Footer \(section)"
    }
    return expected
}

@MainActor
@Suite("A lazy stack pins its sections' headers and footers to the scroll view's edges")
struct PinnedSectionChromeTests {
    static let pinnings: [PinnedScrollableViews] = [
        .sectionHeaders, .sectionFooters, [.sectionHeaders, .sectionFooters],
    ]

    @Test(
        "Each screen is the unpinned stack's, its edge rows replaced by their section's header and footer",
        arguments: PinnedStackPath.allCases, [ScrollIndicatorStyle.scrollbar, .text])
    func edgesShowTheirSectionsChrome(path: PinnedStackPath, style: ScrollIndicatorStyle) {
        // Lines into the content: a header at the top, one row in, the last
        // row of a section, its footer, the next header, deep in, the end.
        let lines = [0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 13, 50, 51, 52, 53, 54, 100_000, 3, 0]
        for views in Self.pinnings {
            let pinnedBox = PinnedPositionBox()
            let twinBox = PinnedPositionBox()
            let page = PinnedPage(
                box: pinnedBox, style: style, content: PinnedSections(path: path, pinnedViews: views))
            let twin = PinnedPage(
                box: twinBox, style: style, content: PinnedSections(path: path, pinnedViews: []))
            let (pinnedTUI, pinnedFocus) = (TUIContext(), FocusManager())
            let (twinTUI, twinFocus) = (TUIContext(), FocusManager())
            _ = scrollFrame(page, tui: pinnedTUI, focusManager: pinnedFocus)
            _ = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus)
            var differing: [String] = []
            var pinnedAny = false
            for line in lines {
                pinnedBox.position.scrollTo(y: line)
                twinBox.position.scrollTo(y: line)
                let shown = scrollFrame(page, tui: pinnedTUI, focusManager: pinnedFocus)
                let unpinned = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus)
                let expected = pinned(unpinned, pinning: views)
                if expected != unpinned { pinnedAny = true }
                if shown != expected { differing.append("y \(line): \(shown) vs \(expected)") }
            }
            #expect(pinnedAny, "\(views.rawValue): the script never put a row at an edge")
            #expect(
                differing.isEmpty,
                "\(views.rawValue): \(differing.count) screens differ: \(differing.prefix(2))")
        }
    }

    @Test("Outside a scroll view nothing is pinned, and nothing pinned reaches the screen")
    func noScrollViewNoPinning() {
        // The stack draws its rows whole in the frame; the section copies it
        // emits reach the root unconsumed, where they must be dropped rather
        // than drawn again — over the label a `ZStack` draws on the first
        // header, which the root would otherwise cover with the header's copy.
        func screen(_ views: PinnedScrollableViews) -> [String] {
            let view = ZStack(alignment: .topLeading) {
                PinnedSections(path: .exactWalk, pinnedViews: views)
                Text("OVER")
            }
            .frame(height: 8)
            let (tui, focusManager) = (TUIContext(), FocusManager())
            _ = scrollFrame(view, tui: tui, focusManager: focusManager)
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            #expect(
                views.isEmpty || buffer.overlays.contains { $0.scrollPin != nil },
                "precondition: the sections emit their pinned copies")
            return buffer.compositingOverlays(maxWidth: 30, maxHeight: 8, palette: context.environment.palette)
                .lines.map(\.stripped)
        }
        #expect(screen([]).first?.hasPrefix("OVERer 0") == true, "precondition: \(screen([]))")
        #expect(screen(.sectionHeaders) == screen([]))
        #expect(screen([.sectionHeaders, .sectionFooters]) == screen([]))
    }

    @Test("A stack's relationship with its children stays inside an existential's inline buffer")
    func containerRelationshipFitsInline() {
        // Every stack core writes it on every render; past three words it
        // would be boxed on the heap each time.
        #expect(MemoryLayout<ContainerRelationship>.size <= 3 * MemoryLayout<Int>.size)
    }

    @Test(
        "A section in one of the stack's rows scrolls with its row; a section of its own pins however wrapped",
        arguments: [false, true])
    func onlyTheStacksOwnSectionsPin(inRow: Bool) {
        // SwiftUI pins the stack's own sections — written in its content or
        // made there by a `ForEach`, however wrapped — and not one that is part
        // of a row (measured: a `VStack` of sections inside a pinned stack). The
        // two shapes differ by one sibling step: the row's `VStack` child.
        let pinnedBox = PinnedPositionBox()
        let twinBox = PinnedPositionBox()
        let page = PinnedPage(
            box: pinnedBox, style: .scrollbar,
            content: WrappedSections(inRow: inRow, pinnedViews: .sectionHeaders))
        let twin = PinnedPage(
            box: twinBox, style: .scrollbar, content: WrappedSections(inRow: inRow, pinnedViews: []))
        let (pinnedTUI, pinnedFocus) = (TUIContext(), FocusManager())
        let (twinTUI, twinFocus) = (TUIContext(), FocusManager())
        _ = scrollFrame(page, tui: pinnedTUI, focusManager: pinnedFocus)
        _ = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus)
        pinnedBox.position.scrollTo(y: 2)
        twinBox.position.scrollTo(y: 2)
        let shown = scrollFrame(page, tui: pinnedTUI, focusManager: pinnedFocus)
        let unpinned = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus)
        #expect(unpinned.first == "row 0.1", "precondition: a row of the first section is at the top")
        #expect(shown == (inRow ? unpinned : pinned(unpinned, pinning: .sectionHeaders)))
    }
}

/// Sections of four rows, each in a row's `VStack` (`inRow`) or wrapped in a
/// modifier and so still the stack's own.
private struct WrappedSections: View {
    let inRow: Bool
    let pinnedViews: PinnedScrollableViews

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinnedViews) {
            ForEach(0..<20, id: \.self) { index in
                if inRow {
                    VStack(alignment: .leading, spacing: 0) { section(index) }
                } else {
                    section(index).padding(.trailing, 1)
                }
            }
        }
    }

    private func section(_ index: Int) -> some View {
        Section("Header \(index)") {
            ForEach(0..<4, id: \.self) { Text("row \(index).\($0)") }
        }
    }
}
