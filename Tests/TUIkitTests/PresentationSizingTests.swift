//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationSizingTests.swift
//
//  `presentationSizing(_:)`: the size a sheet's content is proposed, which its
//  box takes — `.form`, `.page`, `.fitted`, `.automatic`, a sizing of the
//  app's own, and the `fitted` and `sticky` modifications.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Proposes 40 by 12, and nothing else.
private struct FixedSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        ProposedSize(width: 40, height: 12)
    }
}

/// Proposes the content's own ideal width, plus ten, at its own height.
private struct RoomierSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        ProposedSize(width: root.sizeThatFits(.unspecified).width + 10, height: nil)
    }
}

/// How many rows a sheet's content draws, outside the view.
private final class Rows: @unchecked Sendable {
    var count = 6
}

@MainActor
@Suite("Presentation sizing")
struct PresentationSizingTests {
    private func context(width: Int = 120, height: Int = 40) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, _ in
            environment.mouseEventDispatcher = MouseEventDispatcher()
            environment.terminalWidth = width
            environment.overlayContentHeight = height
        }
    }

    /// The sheet's box — width by height — for `sheet` presented over a page.
    private func sheetSize(
        _ sheet: some View, width: Int = 120, height: Int = 40
    ) -> (width: Int, height: Int)? {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { sheet },
            context: context(width: width, height: height))
        return buffer.overlays.first.map { ($0.content.width, $0.content.height) }
    }

    private var box: some View { Panel("title") { Text("one line") } }

    @Test("Without a sizing, and with .automatic or .fitted, the sheet fits its content")
    func fittedIsTodaysSheet() {
        let plain = sheetSize(box)
        #expect(plain != nil)
        #expect(plain?.height == 3, "\(String(describing: plain))")
        for sized in [sheetSize(box.presentationSizing(.automatic)), sheetSize(box.presentationSizing(.fitted))] {
            #expect(sized?.width == plain?.width && sized?.height == plain?.height)
        }
    }

    @Test(".form is 64 columns by 25 rows, or less where the terminal is")
    func form() {
        let wide = sheetSize(box.presentationSizing(.form))
        #expect(wide?.width == 64 && wide?.height == 25, "\(String(describing: wide))")
        let narrow = sheetSize(box.presentationSizing(.form), width: 50, height: 20)
        #expect(narrow?.width == 50 && narrow?.height == 20, "\(String(describing: narrow))")
    }

    @Test(".page is 96 columns, or the terminal's width, by the content area's height")
    func page() {
        let wide = sheetSize(box.presentationSizing(.page))
        #expect(wide?.width == 96 && wide?.height == 40, "\(String(describing: wide))")
        let narrow = sheetSize(box.presentationSizing(.page), width: 80, height: 30)
        #expect(narrow?.width == 80 && narrow?.height == 30, "\(String(describing: narrow))")
    }

    @Test("The box encloses what the content leaves: every row has its walls")
    func theBoxEnclosesTheSlack() {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { box.presentationSizing(.form) },
            context: context())
        let lines = buffer.overlays.first?.content.lines.map(\.stripped) ?? []
        #expect(lines.count == 25)
        #expect(lines.dropFirst().dropLast().allSatisfy { $0.hasPrefix("│") && $0.hasSuffix("│") }, "\(lines)")
    }

    @Test("fitted(horizontal:vertical:) fits the content on the axes it names")
    func fittedAxes() {
        let plain = sheetSize(box)
        let formWidth = sheetSize(box.presentationSizing(.form.fitted(horizontal: false, vertical: true)))
        #expect(formWidth?.width == 64 && formWidth?.height == plain?.height, "\(String(describing: formWidth))")
        let formHeight = sheetSize(box.presentationSizing(.form.fitted(horizontal: true, vertical: false)))
        #expect(formHeight?.width == plain?.width && formHeight?.height == 25, "\(String(describing: formHeight))")
    }

    @Test("A sizing of the app's own proposes the size, measuring the content if it likes")
    func customSizings() {
        let fixed = sheetSize(box.presentationSizing(FixedSizing()))
        #expect(fixed?.width == 40 && fixed?.height == 12, "\(String(describing: fixed))")
        let plain = sheetSize(box)
        let roomier = sheetSize(box.presentationSizing(RoomierSizing()))
        #expect(roomier?.width == (plain?.width ?? 0) + 10 && roomier?.height == plain?.height)
    }

    @Test("A detent names the height, the sizing the width")
    func detentWinsTheHeight() {
        let sized = sheetSize(box.presentationSizing(.form).presentationDetents([.height(7)]))
        #expect(sized?.width == 64 && sized?.height == 7, "\(String(describing: sized))")
    }

    @Test("Content with no box keeps its own size")
    func boxlessContent() {
        let sized = sheetSize(Text("one line").presentationSizing(.form))
        #expect(sized?.width == 8 && sized?.height == 1, "\(String(describing: sized))")
    }

    /// Every box below the sheet was offered the sizing, and each took all of
    /// it: the first of two stacked panels the sheet's whole height, leaving
    /// the second none, and the first of two cards side by side the whole
    /// width. They share it now, as two flexible views share a stack.
    @Test("Two boxes in a sized sheet share its size", arguments: [false, true])
    func siblingBoxesShare(sideBySide: Bool) {
        let sheet = Group {
            if sideBySide {
                HStack(spacing: 0) {
                    Panel("Alpha") { Text("a") }
                    Panel("Beta") { Text("b") }
                }
            } else {
                VStack(spacing: 0) {
                    Panel("Alpha") { Text("a") }
                    Panel("Beta") { Text("b") }
                }
            }
        }
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { sheet.presentationSizing(.form) },
            context: context())
        let lines = buffer.overlays.first?.content.lines.map(\.stripped) ?? []
        let drawn = lines.joined(separator: "\n")
        #expect(drawn.contains("Alpha") && drawn.contains("Beta"), "a box was squeezed out:\n\(drawn)")
        #expect(lines.count == 25, "\(lines.count) rows")
        #expect(lines.first.map(\.count) == 64, "\(lines.first.map(\.count) ?? 0) columns")
        if sideBySide {
            // Each card has a share of the width: neither is under a third.
            let topBorder = lines.first ?? ""
            let split = topBorder.distance(
                from: topBorder.startIndex, to: topBorder.range(of: "Beta")?.lowerBound ?? topBorder.startIndex)
            #expect(split > 20 && split < 44, "Beta's title at column \(split) of \(topBorder)")
        } else {
            let betaRow = lines.firstIndex { $0.contains("Beta") } ?? 0
            #expect(betaRow > 8 && betaRow < 17, "Beta's title on row \(betaRow) of 25")
        }
    }

    @Test("Two stacked boxes share a detent's height as well")
    func siblingBoxesShareADetent() {
        let sheet = VStack(spacing: 0) {
            Panel("Alpha") { Text("a") }
            Panel("Beta") { Text("b") }
        }
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { sheet.presentationDetents([.height(12)]) },
            context: context())
        let lines = buffer.overlays.first?.content.lines.map(\.stripped) ?? []
        #expect(lines.count == 12, "\(lines.count) rows")
        let betaRow = lines.firstIndex { $0.contains("Beta") }
        #expect(betaRow == 6, "Beta's title on row \(String(describing: betaRow)) of 12: \(lines)")
    }

    @Test("sticky(horizontal:vertical:) marks its axes, through fitted, and fitted keeps them")
    func stickyAxesCompose() {
        func axes(_ sizing: some PresentationSizing) -> (Bool, Bool)? {
            (sizing as? any _StickyPresentationSizing).map { ($0.stickyAxes.horizontal, $0.stickyAxes.vertical) }
        }
        #expect(axes(FittedPresentationSizing.fitted.sticky(vertical: true)) ?? (true, true) == (false, true))
        #expect(
            axes(FormPresentationSizing.form.sticky(horizontal: true).fitted(horizontal: false, vertical: true))
                ?? (false, true) == (true, false))
        #expect(axes(FormPresentationSizing.form.sticky()) ?? (true, true) == (false, false))
        #expect(axes(PagePresentationSizing.page) == nil, "a plain sizing is sticky nowhere")
    }

    /// A sheet of `rows.count` lines in a box, fitted and sticky vertically.
    private func growing(_ rows: Rows, sticky: Bool) -> some View {
        Text("page").sheet(isPresented: .constant(true)) {
            Panel("t") {
                VStack(spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { Text("row \($0)") }
                }
            }
            .presentationSizing(sticky ? AnyStickyChoice.sticky : AnyStickyChoice.fitted)
        }
    }

    @Test("A sticky sheet presented again starts from its content, not the size it kept")
    func stickyStartsOverWhenPresentedAgain() {
        let rows = Rows()
        var isPresented = true
        let harness = InputChainHarness(width: 60, height: 30)
        func view() -> some View {
            Text("page").sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                Panel("t") {
                    VStack(spacing: 0) {
                        ForEach(0..<rows.count, id: \.self) { Text("row \($0)") }
                    }
                }
                .presentationSizing(AnyStickyChoice.sticky)
            }
        }
        #expect(harness.frame(view()).overlays.first?.content.height == 8)
        rows.count = 2
        #expect(harness.frame(view()).overlays.first?.content.height == 8, "precondition: it kept its size")
        isPresented = false
        #expect(harness.frame(view()).overlays.isEmpty)
        isPresented = true
        let height = harness.frame(view()).overlays.first?.content.height
        #expect(height == 4, "presented again at \(String(describing: height)) rows, not its content's 4")
    }

    @Test("A sticky axis grows with the content and does not shrink while presented")
    func stickyKeepsTheLargest() {
        let rows = Rows()
        let harness = InputChainHarness(width: 60, height: 30)
        func height(sticky: Bool) -> Int? {
            harness.frame(growing(rows, sticky: sticky)).overlays.first?.content.height
        }
        let tall = height(sticky: true)
        #expect(tall == 8, "\(String(describing: tall))")
        rows.count = 2
        #expect(height(sticky: true) == 8, "a sticky sheet shrank")
        rows.count = 9
        #expect(height(sticky: true) == 11, "a sticky sheet did not grow")
        rows.count = 2
        #expect(height(sticky: false) == 4, "a fitted sheet did not shrink")
    }
}

/// The two sizings the sticky test switches between, as one type, so the
/// sheet's content keeps its identity — and the presenter its state — across
/// the switch.
private enum AnyStickyChoice {
    static var sticky: _AnyChoiceSizing { _AnyChoiceSizing(isSticky: true) }
    static var fitted: _AnyChoiceSizing { _AnyChoiceSizing(isSticky: false) }
}

/// `.fitted`, or `.fitted.sticky(vertical: true)`, behind one type.
private struct _AnyChoiceSizing: PresentationSizing, _StickyPresentationSizing {
    let isSticky: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedSize {
        .unspecified
    }

    var stickyAxes: (horizontal: Bool, vertical: Bool) { (false, isSticky) }
}
