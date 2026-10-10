//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionPartsTests.swift
//
//  A `Section` outside a `List`, a `Form` and a `Table` is its header's,
//  content's and footer's views, laid out as the container's own children with
//  no styling of their own — as SwiftUI's is (measured on macOS 15.8, probes in
//  the session notes, `D1S/probe/b16`): a `VStack` spaces all of them apart,
//  an `HStack` lays them along its row, a `Grid` gives each a row, a `Layout`
//  sees each as a subview. Decisions B16.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// How many subviews a layout is handed.
@MainActor
private final class SubviewCount {
    var count = -1
}

private struct CountingLayout: Layout {
    let counted: SubviewCount

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        counted.count = subviews.count
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

@MainActor
@Suite("A section outside a list is its parts")
struct SectionPartsTests {

    private func buffer(_ view: some View, width: Int = 30, height: Int = 14) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
    }

    private func lines(_ view: some View, width: Int = 30, height: Int = 14) -> [String] {
        buffer(view, width: width, height: height).lines.map(\.stripped)
    }

    @Test("In a VStack the parts are the stack's children, its spacing between every two")
    func column() {
        let drawn = lines(
            VStack(alignment: .leading, spacing: 1) {
                Text("x")
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("h")
                } footer: {
                    Text("f")
                }
                Text("y")
            })
        #expect(drawn == ["x", "", "h", "", "a", "", "b", "", "f", "", "y"])
    }

    @Test("In an HStack the parts lie along the row")
    func row() {
        let drawn = lines(
            HStack(spacing: 1) {
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("h")
                } footer: {
                    Text("f")
                }
            })
        #expect(drawn == ["h a b f"])
    }

    @Test("A modifier written on the section reaches each part")
    func modifierReachesEachPart() {
        let drawn = lines(
            HStack(spacing: 1) {
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("h")
                }
                .padding(.leading, 1)
            })
        #expect(drawn == [" h  a  b"])
    }

    @Test("The header and footer are drawn as written, with no styling of the section's")
    func noStyling() {
        let section = buffer(
            VStack(alignment: .leading, spacing: 0) {
                Section { Text("a") } header: { Text("h") } footer: { Text("f") }
            })
        let plain = buffer(
            VStack(alignment: .leading, spacing: 0) {
                Text("h")
                Text("a")
                Text("f")
            })
        #expect(section.lines == plain.lines)
    }

    @Test("A collapsible section shows its header as written, with no triangle, and its content while expanded")
    func collapsible() {
        func drawn(_ expanded: Bool) -> [String] {
            lines(
                VStack(alignment: .leading, spacing: 0) {
                    Section("T", isExpanded: .constant(expanded)) { Text("a") }
                    Text("z")
                })
        }
        #expect(drawn(false) == ["T", "z"])
        #expect(drawn(true) == ["T", "a", "z"])
    }

    @Test("A Grid gives each part a row of its own")
    func grid() {
        let drawn = lines(
            Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 0) {
                GridRow {
                    Text("g0")
                    Text("g1")
                }
                Section { Text("a") } header: { Text("h") }
            }
        ).map { String($0.reversed().drop { $0 == " " }.reversed()) }
        #expect(drawn == ["g0 g1", "h", "a"])
    }

    @Test("A Layout sees each part as a subview, and a header-less section's missing header as none")
    func layoutSubviews() {
        let counted = SubviewCount()
        _ = lines(
            CountingLayout(counted: counted) {
                Section {
                    Text("a")
                    Text("b")
                } header: {
                    Text("h")
                } footer: {
                    Text("f")
                }
                Section { Text("c") }
            })
        #expect(counted.count == 5)
    }

    @Test("Drawn on its own a section stacks its parts, as a Group does")
    func alone() {
        #expect(lines(Section { Text("a") } header: { Text("h") } footer: { Text("f") }) == ["h", "a", "f"])
    }

    @Test("A header's view and a content view of one type keep apart identities")
    func partsKeepApartIdentities() {
        let parts = resolveChildViews(
            from: Section { Text("a") } header: { Text("h") },
            context: makeRenderContext(width: 10, height: 4))
        let identities = parts.compactMap(\.pinnedIdentity)
        #expect(identities.count == 2)
        let paths = Set(identities.map(\.path))
        #expect(paths.count == 2)
    }

    @Test("A pinned stack lays its own sections out as its children, and pins the header over the gaps too")
    func pinnedStackSpacing() {
        // Two sections of a header and four rows, one line apart: lines 0–8
        // and 10–18. Unpinned, the stack takes the sections apart; pinned, it
        // keeps them whole and each lays its parts out with the stack's
        // spacing, so the drawing is the same until a header pins. It pins
        // while any of its content — the gaps between its rows too — is under
        // the top edge, until its bottom meets the last row's (travel 8), as
        // SwiftUI's does with `spacing: 10` (measured on macOS 15.8).
        func stack(_ pinned: PinnedScrollableViews) -> some View {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: pinned) {
                Section {
                    ForEach(0..<4, id: \.self) { Text("row 0.\($0)") }
                } header: {
                    Text("Header 0")
                }
                Section {
                    ForEach(0..<4, id: \.self) { Text("row 1.\($0)") }
                } header: {
                    Text("Header 1")
                }
            }
        }
        let (pinnedBox, twinBox) = (PinnedPositionBox(), PinnedPositionBox())
        func page(_ box: PinnedPositionBox, _ pinned: PinnedScrollableViews) -> some View {
            ScrollView { stack(pinned) }
                .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
                .frame(height: 5)
        }
        let (pinnedTUI, pinnedFocus) = (TUIContext(), FocusManager())
        let (twinTUI, twinFocus) = (TUIContext(), FocusManager())
        let pinned = page(pinnedBox, .sectionHeaders)
        let twin = page(twinBox, [])
        _ = scrollFrame(pinned, tui: pinnedTUI, focusManager: pinnedFocus, height: 5)
        _ = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus, height: 5)
        var differing: [String] = []
        for line in 0...14 {
            pinnedBox.position.scrollTo(y: line)
            twinBox.position.scrollTo(y: line)
            let shown = scrollFrame(pinned, tui: pinnedTUI, focusManager: pinnedFocus, height: 5)
            var expected = scrollFrame(twin, tui: twinTUI, focusManager: twinFocus, height: 5)
            if (1...8).contains(line) { expected[0] = "Header 0" }
            if (11...18).contains(line) { expected[0] = "Header 1" }
            if shown != expected { differing.append("y \(line): \(shown) vs \(expected)") }
        }
        #expect(differing.isEmpty, "\(differing.count) screens differ: \(differing.prefix(3))")
    }

    @Test("A walk that keeps sections whole hands the section over as one child")
    func keptWhole() {
        let context = makeRenderContext(width: 10, height: 4)
        let section = Section { Text("a") } header: { Text("h") }
        #expect(resolveChildViews(from: section, context: context).count == 2)
        let whole = resolveChildViews(from: section, context: context.keepingSectionsWhole())
        #expect(whole.count == 1)
        #expect(whole.first?.wrappedView is Section<Text, Text, EmptyView>)
    }

    @Test("A ZStack or a Layout in a pinned stack's row takes its own sections apart")
    func containersInAPinnedRow() {
        // The pinned stack keeps ITS sections whole; a container in one of its
        // rows that publishes no axis — a `ZStack`, a `Layout` with no stack
        // orientation — is a new container, whose sections are its parts, as
        // a `VStack` there already took its own apart.
        let counted = SubviewCount()
        let drawn = lines(
            ScrollView {
                LazyVStack(alignment: .leading, pinnedViews: .sectionHeaders) {
                    ZStack(alignment: .topLeading) {
                        Section { Text("row") } header: { Text("H") }
                    }
                    CountingLayout(counted: counted) {
                        Section { Text("a") } header: { Text("h") }
                    }
                }
            }
            .frame(height: 6),
            height: 6)
        #expect(drawn.first?.hasPrefix("row") == true, "the ZStack overlays the header and the row: \(drawn)")
        #expect(counted.count == 2, "the Layout sees the header and the row")
    }
}
