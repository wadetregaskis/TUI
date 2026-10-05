//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PinnedRowSectionTests.swift
//
//  `LazyHStack(pinnedViews:)` and `LazyHGrid(pinnedViews:)`: a section in a
//  row lies along it — header, views, footer — and pinned, its header stays at
//  a horizontal scroll view's leading edge while its content is under it,
//  pushed off by the content's last column, and its footer at the trailing
//  edge; SwiftUI's vertical rule turned on its side (measured on macOS 15.8,
//  probes in the session notes, `w10b/probe/p2`). Decisions A44.
//
//  The oracle is the same row unpinned, scrolled to the same column: pinning
//  writes the header over the leading cells exactly while the section's
//  content is under them, and changes nothing else.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// One section of a two-cell header and four one-cell views.
@MainActor
private func rowSection(_ section: Int, footer: Bool) -> some View {
    Section {
        ForEach(0..<4, id: \.self) { Text(String(UnicodeScalar(UInt8(97 + section * 4 + $0)))) }
    } header: {
        Text("H\(section)")
    } footer: {
        if footer { Text("F\(section)") }
    }
}

/// Two sections of a two-cell header and four one-cell views, a column apart:
/// cells 0–9 and 11–20. Unpinned, the row takes each looped section apart
/// (decisions B15, B16); pinned, it keeps them whole to pin them, and each
/// lays itself out as the row would.
@MainActor
private func rowSections(_ pinned: PinnedScrollableViews, footers: Bool = false) -> some View {
    LazyHStack(spacing: 1, pinnedViews: pinned) {
        ForEach(0..<2, id: \.self) { rowSection($0, footer: footers) }
    }
}

@MainActor
@Suite("A lazy row lays its sections along it and pins their headers and footers")
struct PinnedRowSectionTests {

    private func lines(_ view: some View, width: Int = 30) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 4)).lines.map(\.stripped)
    }

    @Test("A section in a LazyHStack lies along the row, the stack's spacing between its views")
    func alongTheRow() {
        let drawn = lines(
            LazyHStack(spacing: 1) {
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("H")
                } footer: {
                    Text("F")
                }
            })
        #expect(drawn.first == "H a b F")
    }

    @Test("Pinned, a row's own sections lay out as the row would, and the header pins to the leading edge")
    func headersPinToTheLeadingEdge() {
        let (pinnedBox, twinBox) = (PinnedPositionBox(), PinnedPositionBox())
        func page(_ box: PinnedPositionBox, _ pinned: PinnedScrollableViews) -> some View {
            ScrollView(.horizontal) { rowSections(pinned) }
                .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
                .scrollIndicators(.hidden)
                .frame(width: 6, height: 1)
        }
        let (pinnedTUI, pinnedFocus) = (TUIContext(), FocusManager())
        let (twinTUI, twinFocus) = (TUIContext(), FocusManager())
        let pinned = page(pinnedBox, .sectionHeaders)
        let twin = page(twinBox, [])
        _ = scrollFrame(pinned, tui: pinnedTUI, focusManager: pinnedFocus, height: 1)
        _ = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus, height: 1)
        var differing: [String] = []
        var pinnedAny = false
        for column in 0...15 {
            pinnedBox.position.scrollTo(x: column)
            twinBox.position.scrollTo(x: column)
            let shown = scrollFrame(pinned, tui: pinnedTUI, focusManager: pinnedFocus, height: 1)
            var expected = Array(scrollFrame(twin, tui: twinTUI, focusManager: twinFocus, height: 1).first ?? "")
            while expected.count < 6 { expected.append(" ") }
            // Section 0's header (cells 0–1) pins while x is 1…8, the last of
            // it showing at x 9; section 1's (cells 11–12) while x is 12…19.
            let header: [Character]? =
                switch column {
                case 1...8: ["H", "0"]
                case 9: ["0"]
                case 12...19: ["H", "1"]
                default: nil
                }
            if let header {
                pinnedAny = true
                expected.replaceSubrange(0..<header.count, with: header)
            }
            let expectedLine = String(String(expected).reversed().drop { $0 == " " }.reversed())
            if shown != [expectedLine] { differing.append("x \(column): \(shown) vs \(expectedLine)") }
        }
        #expect(pinnedAny)
        #expect(differing.isEmpty, "\(differing.count) screens differ: \(differing.prefix(3))")
    }

    @Test("A pinned footer stays at the trailing edge, never before its section's first view")
    func footersPinToTheTrailingEdge() {
        // With footers: H0 a b c d F0 — cells 0–12, F0 at 11–12 — then H1.
        // At x 0 the viewport (0–5) shows H0 a b; section 0's content is under
        // its trailing edge, so F0 is drawn there, over the cells 4–5.
        let box = PinnedPositionBox()
        let page = ScrollView(.horizontal) { rowSections(.sectionFooters, footers: true) }
            .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
            .scrollIndicators(.hidden)
            .frame(width: 6, height: 1)
        let (tui, focus) = (TUIContext(), FocusManager())
        _ = scrollFrame(page, tui: tui, focusManager: focus, height: 1)
        box.position.scrollTo(x: 0)
        #expect(scrollFrame(page, tui: tui, focusManager: focus, height: 1) == ["H0 aF0"])
        // At x 7 the viewport (7–12) ends on F0 itself: drawn where it is.
        box.position.scrollTo(x: 7)
        #expect(scrollFrame(page, tui: tui, focusManager: focus, height: 1) == ["c d F0"])
    }

    @Test(
        "A LazyHGrid lays a section's header down its rows, its views after, its footer after them",
        arguments: [PinnedScrollableViews(), .sectionHeaders])
    func gridSections(pinned: PinnedScrollableViews) {
        // Outside a scroll view nothing pins, so only the layout shows, and it
        // is the same pinned or not.
        let drawn = lines(
            LazyHGrid(
                rows: [GridItem(.fixed(1), spacing: 0), GridItem(.fixed(1))], alignment: .top, spacing: 1,
                pinnedViews: pinned
            ) {
                Section {
                    Text("a")
                    Text("b")
                    Text("c")
                } header: {
                    Text("H")
                } footer: {
                    Text("F")
                }
            }
        ).prefix(2).map { String($0.reversed().drop { $0 == " " }.reversed()) }
        #expect(drawn == ["H a c F", "  b"])
    }
}
