//  🖥️ TUI — A Terminal UI framework for Swift
//  PresentationItemIdentityTests.swift
//
//  What the `item:` form of a presentation promises over the `isPresented:`
//  form: the presented content is ABOUT something, and when that something
//  changes the content is a DIFFERENT view — fresh `@State`, fresh lifecycle.
//  And, by the owner's ruling SHEET-ITEM-STATE (2026-11-16), each item's
//  content keeps its own state while the presentation stays up: switched back
//  to an item, its content is as it was left; dismissed, all of it goes.
//  These renders drive `StateStorage`'s pass boundaries the way the run loop
//  does (as `ModalBackdropStateTests` does), because the prune at the end of a
//  pass is what makes a dismissed presentation forget; without the bracketing
//  the question of what survives an item change is invisible.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// The thing a presentation is about.
private struct Row: Identifiable, Equatable {
    let id: Int
}

/// The three `item:` forms, for the tests that hold of each.
enum ItemForm: CaseIterable, CustomTestStringConvertible {
    case sheet, cover, popover
    var testDescription: String { "\(self)" }
}

/// The presented content: a draft that only its own Button writes to. The
/// draft is the state an editing sheet holds — a half-typed rename — and
/// `row=` beside it says which item the content was BUILT for, so one line
/// carries both halves of the question.
private struct DraftEditor: View {
    let row: Row
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("row=\(row.id) draft=[\(draft)]")
            Button("Type") { draft = "edit-\(row.id)" }.focusID("draft")
        }
    }
}

@MainActor
@Suite("Presentation: item identity")
struct PresentationItemIdentityTests {

    private final class ItemBox {
        var value: Row?
        var binding: Binding<Row?> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    /// One frame, bracketed the way the run loop brackets it, returning every
    /// line drawn — the page's own plus each overlay's, recursively, since a
    /// sheet, a cover and a popover all land in an overlay (a popover's panel
    /// carries a dismiss backdrop of its own).
    ///
    /// The view is rebuilt for every frame — hence `@autoclosure`, which is
    /// here for re-evaluation, not for brevity — because that is what a real
    /// render does: the page's `body` re-runs and the presentation rebuilds its
    /// content from the CURRENT item. Built once and reused, the presented
    /// content would be frozen at whatever the item was when the test
    /// constructed the view, and every one of these tests would present
    /// nothing at all.
    private func frame(
        _ view: @autoclosure () -> some View, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = fm
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.overlayContentHeight = 14
        let context = RenderContext(
            availableWidth: 40, availableHeight: 14, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view(), context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        return Self.allLines(of: buffer)
    }

    private static func allLines(of buffer: FrameBuffer) -> [String] {
        buffer.lines.map(\.stripped) + buffer.overlays.flatMap { allLines(of: $0.content) }
    }

    /// The drafted line, stripped of the chrome around it — a popover draws its
    /// content inside a bordered panel, so the same assertion can serve all
    /// three presentations.
    private static func draftLine(_ lines: [String]) -> String? {
        lines.first { $0.contains("draft=") }?
            .drop { $0 == " " || $0 == "│" }
            .reversed().drop { $0 == " " || $0 == "│" }.reversed()
            .map(String.init).joined()
    }

    /// Drives the presented editor's Button, so its `@State` holds something
    /// other than its default when the item changes underneath it.
    private func typeIntoTheDraft(
        _ view: @escaping @autoclosure () -> some View, tui: TUIContext, fm: FocusManager
    ) {
        _ = frame(view(), tui: tui, fm: fm)
        fm.focus(id: "draft")
        _ = frame(view(), tui: tui, fm: fm)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .enter))
    }

    @Test("A sheet re-presented for a different item does not inherit the first item's state")
    func sheetItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").sheet(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        // The list selection moves to another row while the sheet is up — the
        // `item:` form's whole reason to exist. SwiftUI re-creates the content.
        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's sheet opened holding row 1's draft: \(switched)")
    }

    @Test("A full-screen cover re-presented for a different item starts fresh")
    func coverItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").fullScreenCover(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's cover opened holding row 1's draft: \(switched)")
    }

    @Test("A popover re-presented for a different item starts fresh")
    func popoverItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").popover(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's popover opened holding row 1's draft: \(switched)")
    }

    /// The same item must NOT be re-keyed on every frame: an identity that
    /// changed while the item stood still would throw the draft away between
    /// keystrokes, which is the opposite defect.
    @Test("A sheet kept open for one item holds its state across frames")
    func sheetKeepsStateForTheSameItem() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").sheet(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        _ = frame(view(), tui: tui, fm: fm)
        let later = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(later) == "row=1 draft=[edit-1]",
            "the draft survived the frames after it was typed: \(later)")
    }

    // MARK: - Each item keeps its own state while presented (SHEET-ITEM-STATE)

    /// The presenter under a view that keeps its subtree's state, as a `List`
    /// or `Table` row is: there, nothing the presentation stops keeping is
    /// pruned by the end of the pass, so what it drops — on dismissal, or
    /// past the cap — it must drop itself, and these tests see whether it did.
    private func presenter(_ form: ItemForm, item: ItemBox) -> some View {
        let page = Text("page")
        return Group {
            switch form {
            case .sheet: page.sheet(item: item.binding) { row in DraftEditor(row: row) }
            case .cover: page.fullScreenCover(item: item.binding) { row in DraftEditor(row: row) }
            case .popover: page.popover(item: item.binding) { row in DraftEditor(row: row) }
            }
        }
        .keepsStateWhileHidden()
    }

    /// Presents `row`, types its draft, and says what the editor shows.
    private func typeDraft(
        for row: Int, _ form: ItemForm, item: ItemBox, tui: TUIContext, fm: FocusManager
    ) -> String? {
        item.value = Row(id: row)
        typeIntoTheDraft(presenter(form, item: item), tui: tui, fm: fm)
        return Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
    }

    @Test("Switched back to an item, its content is as it was left; the other item's is its own", arguments: ItemForm.allCases)
    func switchedBackKeepsState(_ form: ItemForm) {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        #expect(typeDraft(for: 1, form, item: item, tui: tui, fm: fm) == "row=1 draft=[edit-1]", "sanity")

        item.value = Row(id: 2)
        let fresh = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(fresh == "row=2 draft=[]", "row 2 opened holding another row's draft")
        #expect(typeDraft(for: 2, form, item: item, tui: tui, fm: fm) == "row=2 draft=[edit-2]", "sanity")

        item.value = Row(id: 1)
        let back = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(back == "row=1 draft=[edit-1]", "row 1's draft was lost while row 2 was shown")
        item.value = Row(id: 2)
        let backToTwo = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(backToTwo == "row=2 draft=[edit-2]", "row 2's draft was lost while row 1 was shown")
    }

    @Test("Dismissed, every item's kept state goes: presented again, it starts fresh", arguments: ItemForm.allCases)
    func dismissalDropsKeptState(_ form: ItemForm) {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        // The baseline: what a presentation for one item leaves behind once
        // dismissed — the presenter's own records, whatever they are.
        item.value = Row(id: 9)
        _ = frame(presenter(form, item: item), tui: tui, fm: fm)
        item.value = nil
        _ = frame(presenter(form, item: item), tui: tui, fm: fm)
        _ = frame(presenter(form, item: item), tui: tui, fm: fm)
        let before = Self.stateValues(tui)
        for row in 1...3 {
            #expect(typeDraft(for: row, form, item: item, tui: tui, fm: fm) == "row=\(row) draft=[edit-\(row)]")
        }
        item.value = nil
        _ = frame(presenter(form, item: item), tui: tui, fm: fm)
        _ = frame(presenter(form, item: item), tui: tui, fm: fm)
        #expect(Self.stateValues(tui) == before, "kept item state outlived the dismissal")

        item.value = Row(id: 1)
        let again = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(again == "row=1 draft=[]", "presented again, row 1 came back with its old draft")
    }

    @Test("Beyond the cap, the item shown longest ago starts fresh; the rest keep theirs", arguments: [ItemForm.sheet, .popover])
    func keptItemsAreCapped(_ form: ItemForm) {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        let rows = KeptItemContents.capacity + 2
        for row in 1...rows {
            #expect(typeDraft(for: row, form, item: item, tui: tui, fm: fm) == "row=\(row) draft=[edit-\(row)]")
        }
        // Kept: the `capacity` items left most recently — 2 through rows - 1.
        item.value = Row(id: 2)
        let kept = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(kept == "row=2 draft=[edit-2]", "an item within the cap lost its state")
        item.value = Row(id: 1)
        let dropped = Self.draftLine(frame(presenter(form, item: item), tui: tui, fm: fm))
        #expect(dropped == "row=1 draft=[]", "the item left longest ago was kept beyond the cap")
    }

    private static func stateValues(_ tui: TUIContext) -> Int? {
        tui.stateStorage.entryCounts.first { $0.name == "state.values" }?.count
    }
}
