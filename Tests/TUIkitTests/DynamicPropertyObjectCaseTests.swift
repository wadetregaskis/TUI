//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicPropertyObjectCaseTests.swift
//
//  The `@State` inside an enum's case inside a class property is the
//  object's too: it lives in the payload's own backings, so nothing a view
//  keeps decides it — no record of the case at a holder, no box under a
//  holder's key (decisions-DYNVFIX B-DYNVFIX-3, lane DYNVCLAIM). Under the
//  claim it replaced, the case's record and boxes were kept at the claimant,
//  so a holder moving between objects lost or shared them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// What each body hands out, by the name of the view that handed it.
@MainActor
private final class CaseTaps {
    var values: [String: Binding<Int>] = [:]
}

/// A class property passed through a view that does not hold it as one.
private struct Passed<Object: AnyObject> {
    let object: Object
}

/// A document's cursor, while it is edited.
private struct Cursor: DynamicProperty {
    @State var line = 0
}

/// A document's zoom, while it is viewed.
private struct Zoom: DynamicProperty {
    @State var level = 1
}

/// What a document is doing: each case's state is the case's payload's.
private enum Mode: DynamicProperty {
    case editing(Cursor)
    case viewing(Zoom)
}

/// A class app property whose state is in an enum's case.
private final class Doc: DynamicProperty {
    var mode: Mode

    init(_ mode: Mode) {
        self.mode = mode
    }
}

/// A view showing a document's case and its state, `padding` dashes wide
/// after it.
private struct DocLine: View {
    let name: String
    var padding = 0
    let doc: Doc
    let taps: CaseTaps

    var body: some View {
        let dashes = String(repeating: "-", count: padding)
        switch doc.mode {
        case .editing(let cursor):
            taps.values[name] = cursor.$line
            return Text(verbatim: "\(name) line \(cursor.line)\(dashes)")
        case .viewing(let zoom):
            taps.values[name] = zoom.$level
            return Text(verbatim: "\(name) zoom \(zoom.level)\(dashes)")
        }
    }
}

/// `DocLine`, served from the memo while its name and generation are.
private struct MemoDocLine: View, Equatable {
    let name: String
    let generation: Int
    let doc: Doc
    let taps: CaseTaps

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.generation == rhs.generation
    }

    var body: some View {
        DocLine(name: name, doc: doc, taps: taps)
    }
}

/// A detail view of the document at `selection`: an array is not looked
/// into, so the detail view is the first to reach each document.
private struct DocSelection: View {
    let docs: [Doc]
    let selection: Int
    let taps: CaseTaps

    var body: some View {
        DocLine(name: "detail", doc: docs[selection], taps: taps)
    }
}

/// The ways a document's holder changes.
enum DocHolderChange: CaseIterable, Sendable {
    /// A `ViewThatFits` switches candidate on a resize.
    case viewThatFits
    /// The first holder's row is removed.
    case rowRemoved
    /// An `if`/`else` below the branch's root swaps the holder.
    case conditional
    /// The first holder leaves while the other is served from the memo.
    case memoServed
}

/// One document shown by two candidates of a `ViewThatFits`, the first too
/// wide for a narrow terminal.
private struct DocCandidates: View {
    let doc: Passed<Doc>
    let taps: CaseTaps

    var body: some View {
        ViewThatFits {
            DocLine(name: "wide", padding: 40, doc: doc.object, taps: taps)
            DocLine(name: "narrow", doc: doc.object, taps: taps)
        }
    }
}

/// A row's name, and the frame it is drawn in, so that no frame serves the
/// row from the memo.
private struct TickedDocRow: Identifiable, Equatable {
    let id: String
    let tick: Int
}

/// One document shown by a row per name.
private struct DocRows: View {
    let rows: [TickedDocRow]
    let doc: Passed<Doc>
    let taps: CaseTaps

    var body: some View {
        VStack {
            ForEach(rows) { row in
                DocLine(name: row.id, doc: doc.object, taps: taps)
            }
        }
    }
}

/// One document shown by an editor or a summary, an `if`/`else` choosing,
/// each inside a stack.
private struct DocScreen: View {
    let editing: Bool
    let doc: Passed<Doc>
    let taps: CaseTaps

    @ViewBuilder var body: some View {
        if editing {
            VStack { DocLine(name: "editor", doc: doc.object, taps: taps) }
        } else {
            VStack { DocLine(name: "summary", doc: doc.object, taps: taps) }
        }
    }
}

/// One document shown by two memoised rows, the first of which can be
/// removed.
private struct TwoMemoDocRows: View {
    let showsFirst: Bool
    let generation: Int
    let doc: Passed<Doc>
    let taps: CaseTaps

    var body: some View {
        VStack {
            if showsFirst {
                MemoDocLine(name: "a", generation: generation, doc: doc.object, taps: taps).equatable().frame(height: 1)
            }
            MemoDocLine(name: "b", generation: generation, doc: doc.object, taps: taps).equatable().frame(height: 1)
        }
    }
}

@MainActor
@Suite("DynamicProperty objects' enum cases")
struct DynamicPropertyObjectCaseTests {

    /// One frame as the render loop draws it: invalidations drained, the pass
    /// begun, the view made and drawn in it (`StateStorage.inRenderPass(_:)`),
    /// what was not drawn pruned.
    private func frame<V: View>(
        _ view: @autoclosure () -> V, _ tui: TUIContext, width: Int = 20, height: Int = 1
    ) -> [String] {
        let context = RenderContext(availableWidth: width, availableHeight: height, tuiContext: tui)
        tui.renderCache.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        defer {
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        return tui.stateStorage.inRenderPass { renderToBuffer(view(), context: context) }.lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// The detail view moved to a document in the same case, never drawn
    /// before, whose cursor bound the box the detail view's key kept for the
    /// first document's: the two documents shared one cursor (review4 of
    /// DYNVFIX, 4df65e5ef(1)). Each payload's state is its own.
    @Test("Documents shown one after the other by one view keep a cursor each")
    func windowedDocsKeepTheirOwnCursors() {
        let tui = TUIContext()
        let taps = CaseTaps()
        let docs = [Doc(.editing(Cursor())), Doc(.editing(Cursor()))]
        let view = { (selection: Int) in DocSelection(docs: docs, selection: selection, taps: taps) }
        #expect(frame(view(0), tui) == ["detail line 0"])
        taps.values["detail"]?.wrappedValue = 5
        #expect(frame(view(0), tui) == ["detail line 5"])
        #expect(frame(view(1), tui) == ["detail line 0"])
        taps.values["detail"]?.wrappedValue = 9
        #expect(frame(view(1), tui) == ["detail line 9"])
        #expect(frame(view(0), tui) == ["detail line 5"])
        #expect(frame(view(1), tui) == ["detail line 9"])
    }

    /// The record of the case was kept at the detail view: moving to a
    /// document in another case dropped the first document's state in its
    /// case, which was back at its default when the view returned (review5
    /// of DYNVFIX, S2).
    @Test("A view moving between documents in different cases keeps each document's state in its case")
    func detailMovingBetweenDocsInDifferentCasesKeepsEachCase() {
        let tui = TUIContext()
        let taps = CaseTaps()
        let docs = [Doc(.editing(Cursor())), Doc(.viewing(Zoom()))]
        let view = { (selection: Int) in DocSelection(docs: docs, selection: selection, taps: taps) }
        #expect(frame(view(0), tui) == ["detail line 0"])
        taps.values["detail"]?.wrappedValue = 42
        #expect(frame(view(0), tui) == ["detail line 42"])
        #expect(frame(view(1), tui) == ["detail zoom 1"])
        taps.values["detail"]?.wrappedValue = 3
        #expect(frame(view(1), tui) == ["detail zoom 3"])
        #expect(frame(view(0), tui) == ["detail line 42"])
        #expect(frame(view(1), tui) == ["detail zoom 3"])
    }

    /// The state of a case inside the object was kept at its claimant, and
    /// dropped with it when the holder changed, though the object and its
    /// case stayed (review4 of DYNVFIX, deac1c31f(4); fix3's stated
    /// exception). Kept while the object lives and its case stays, whichever
    /// view draws it.
    @Test("The @State in a class property's enum case survives a change of the view holding it", arguments: DocHolderChange.allCases)
    func inCaseStateSurvivesAHolderChange(change: DocHolderChange) {
        let tui = TUIContext()
        let taps = CaseTaps()
        let doc = Passed(object: Doc(.editing(Cursor())))
        switch change {
        case .viewThatFits:
            #expect(frame(DocCandidates(doc: doc, taps: taps), tui, width: 80).first?.hasPrefix("wide line 0-") == true)
            taps.values["wide"]?.wrappedValue = 3
            #expect(frame(DocCandidates(doc: doc, taps: taps), tui, width: 80).first?.hasPrefix("wide line 3-") == true)
            #expect(frame(DocCandidates(doc: doc, taps: taps), tui) == ["narrow line 3"])
        case .rowRemoved:
            var tick = 0
            let rows = { (names: [String]) -> DocRows in
                tick += 1
                return DocRows(rows: names.map { TickedDocRow(id: $0, tick: tick) }, doc: doc, taps: taps)
            }
            #expect(frame(rows(["a", "b"]), tui, height: 2) == ["a line 0", "b line 0"])
            taps.values["a"]?.wrappedValue = 3
            #expect(frame(rows(["a", "b"]), tui, height: 2) == ["a line 3", "b line 3"])
            #expect(frame(rows(["b"]), tui) == ["b line 3"])
        case .conditional:
            #expect(frame(DocScreen(editing: true, doc: doc, taps: taps), tui) == ["editor line 0"])
            taps.values["editor"]?.wrappedValue = 3
            #expect(frame(DocScreen(editing: true, doc: doc, taps: taps), tui) == ["editor line 3"])
            #expect(frame(DocScreen(editing: false, doc: doc, taps: taps), tui) == ["summary line 3"])
        case .memoServed:
            let view = { (showsFirst: Bool, generation: Int) in
                TwoMemoDocRows(showsFirst: showsFirst, generation: generation, doc: doc, taps: taps)
            }
            #expect(frame(view(true, 0), tui, height: 2) == ["a line 0", "b line 0"])
            taps.values["a"]?.wrappedValue = 3
            #expect(frame(view(true, 1), tui, height: 2) == ["a line 3", "b line 3"])
            #expect(frame(view(false, 1), tui, height: 2).first == "b line 3")
            taps.values["b"]?.wrappedValue = 7
            #expect(frame(view(false, 2), tui, height: 2).first == "b line 7")
        }
    }

    /// A box moved to the next holder's key was not in that holder's record
    /// of the case, so when the case left and came back it brought its old
    /// state with it (review4 of DYNVFIX, 4df65e5ef(3); review5 S4). A case
    /// set anew starts with a new payload, at its defaults; a payload the app
    /// kept and puts back brings its state back, as the object stored it.
    @Test("A class property's enum case set anew starts at its defaults after its holder changed")
    func objectsCaseComesBackAtItsDefaults() {
        let tui = TUIContext()
        let taps = CaseTaps()
        let doc = Passed(object: Doc(.editing(Cursor())))
        let view = { (showsFirst: Bool, generation: Int) in
            TwoMemoDocRows(showsFirst: showsFirst, generation: generation, doc: doc, taps: taps)
        }
        #expect(frame(view(true, 0), tui, height: 2) == ["a line 0", "b line 0"])
        taps.values["a"]?.wrappedValue = 5
        #expect(frame(view(true, 1), tui, height: 2) == ["a line 5", "b line 5"])
        #expect(frame(view(false, 2), tui, height: 2).first == "b line 5")
        doc.object.mode = .viewing(Zoom())
        #expect(frame(view(false, 3), tui, height: 2).first == "b zoom 1")
        doc.object.mode = .editing(Cursor())
        #expect(frame(view(false, 4), tui, height: 2).first == "b line 0")
        // A payload kept and put back.
        taps.values["b"]?.wrappedValue = 8
        #expect(frame(view(false, 5), tui, height: 2).first == "b line 8")
        let kept = doc.object.mode
        doc.object.mode = .viewing(Zoom())
        #expect(frame(view(false, 6), tui, height: 2).first == "b zoom 1")
        doc.object.mode = kept
        #expect(frame(view(false, 7), tui, height: 2).first == "b line 8")
    }
}
