//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowHoldTests.swift
//
//  `ScrollWindowHold` (`Documentation/Layout and scrolling/Scroll anchoring.md`
//  §5): with nothing else holding it, a scroll view keeps the row at the top
//  of its viewport — and the rows on screen with it — where it is as rows are
//  inserted, removed or resized above it, as SwiftUI's lazy stacks do
//  (`Tools/SwiftUIProbes/Scroll anchoring/hold.out`); `.scrollWindowHold(.offset)`
//  keeps the offset in lines instead. Every case runs on each of a lazy
//  stack's three windowed paths, which hold the row each in its own way, and
//  on `List` and on both of `Table`'s row composers, which share
//  `ItemListHandler.holdTopRow()` but wire it each from its own place.
//
//  Harness note: a real `ScrollView` is rendered and its VISIBLE lines read,
//  because the hold moves the offset and only the scroll view adopts it (see
//  `DesignatedRowAnchorTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
import TUIkitTables
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("Scroll window hold")
struct ScrollWindowHoldTests {

    /// The three windowed paths of a `LazyVStack`: arithmetic over equal rows,
    /// and over rows of three heights the exact walk (up to 256 rows) and the
    /// anchored walk (more).
    enum StackPath: String, CaseIterable, Sendable {
        case uniform, exactWalk, anchoredWalk

        var count: Int { self == .anchoredWalk ? 300 : 60 }
    }

    /// A row, and how many lines it has been made taller. Carried in the data
    /// rather than read from beside it, so a change of it is a change of what
    /// the `ForEach` is handed.
    struct Row: Hashable, Identifiable, Sendable {
        let id: Int
        var extra = 0
        var name: String { "row \(id)" }
        var tallName: String { Array(repeating: name, count: 4).joined(separator: " ") }
    }

    /// One scroll view over a lazy stack, rendered frame by frame as its rows
    /// change.
    @MainActor
    final class Scroller {
        let path: StackPath
        var items: [Row]
        var hold: ScrollWindowHold?
        var declared: UnitPoint?
        var position = ScrollPosition()
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        init(_ path: StackPath) {
            self.path = path
            items = (0..<path.count).map { Row(id: $0) }
        }

        /// Inserts rows `ids` before the first row.
        func insert(_ ids: Range<Int>) { items.insert(contentsOf: ids.map { Row(id: $0) }, at: 0) }

        private var scrollView: some View {
            let path = path
            return ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.id) { row in
                        Text("row \(row.id)").frame(height: (path == .uniform ? 1 : row.id % 3 + 1) + row.extra)
                    }
                }
            }
            .scrollPosition(Binding(get: { self.position }, set: { self.position = $0 }))
            .defaultScrollAnchor(declared)
        }

        @discardableResult
        func frame(_ transaction: Transaction = Transaction()) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.transaction = transaction
            if let hold { environment.scrollWindowHold = hold }
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: 8, environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(scrollView, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }

        /// Scrolls to line `y` and lets the view settle there.
        @discardableResult
        func scrolled(to y: Int) -> [String] {
            frame()
            position.scrollTo(y: y)
            frame()
            return frame()
        }
    }

    /// The rows a frame shows, top to bottom.
    func rows(_ lines: [String]) -> [Int] {
        lines.compactMap { $0.hasPrefix("row ") ? Int($0.dropFirst(4)) : nil }
    }

    // MARK: - The default holds

    @Test("Rows inserted above the top row leave the rows on screen where they are", arguments: StackPath.allCases)
    func insertionAboveIsHeld(path: StackPath) {
        let scroller = Scroller(path)
        let before = scroller.scrolled(to: 30)
        #expect(rows(before).first.map { $0 > 5 } == true, "precondition: scrolled away from the top \(before)")
        scroller.insert(1_000..<1_005)
        let after = scroller.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
        // And it stays held: the next frame moves nothing.
        #expect(scroller.frame() == before)
    }

    @Test("Rows removed above the top row leave the rows on screen where they are", arguments: StackPath.allCases)
    func removalAboveIsHeld(path: StackPath) {
        let scroller = Scroller(path)
        let before = scroller.scrolled(to: 30)
        scroller.items.removeSubrange(0..<5)
        let after = scroller.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
    }

    /// The exact walk alone: it measures every row each frame, so it is the
    /// one path that sees a row off screen above grow. The other two price
    /// such a row as they last measured it — by the hypothesis's pitch, or not
    /// at all, the anchored walk placing rows from the top row down — so the
    /// rows on screen do not move there either way.
    @Test("A row above the top row growing leaves the rows on screen where they are")
    func growthAboveIsHeld() {
        let path = StackPath.exactWalk
        let scroller = Scroller(path)
        let before = scroller.scrolled(to: 30)
        scroller.items[2].extra = 3
        let after = scroller.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
    }

    @Test("When the top row itself goes, the row after it takes its place", arguments: StackPath.allCases)
    func removedTopRowIsReplacedByTheNext(path: StackPath) {
        let scroller = Scroller(path)
        // A line that starts a row, so the row at the top is whole.
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)" else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        // The row at the top and the five above it go.
        scroller.items.removeAll { (top - 5)...top ~= $0.id }
        let after = scroller.frame()
        #expect(rows(after).first == top + 1, "before: \(before)\nafter:  \(after)")
    }

    // MARK: - Where it holds nothing

    /// A sort moves the row at the top away from the rows around it. Followed,
    /// the view would scroll to wherever it went; SwiftUI holds no row through
    /// a reorder (`Tools/SwiftUIProbes/Scroll anchoring/reorder.out`), and the
    /// offset stays.
    @Test("Rows reordered around the top row are not followed: a sorted stack keeps its offset", arguments: StackPath.allCases)
    func reorderIsNotFollowed(path: StackPath) {
        let scroller = Scroller(path)
        let before = scroller.scrolled(to: 12)
        guard let top = rows(before).first else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        scroller.items.reverse()
        let after = scroller.frame()
        #expect(!rows(after).contains(top), "row \(top) was followed: before \(before)\nafter \(after)")
    }

    /// A row whose id changes where it is — `ForEach(names, id: \.self)` with
    /// the name at the top edited — is a row gone and another in its place:
    /// nothing above it changed, so nothing on screen moves. Taken for the top
    /// row removed, the row after it was put where the top row was, and the
    /// view jumped down a row.
    @Test("A top row whose id changes in place leaves the rows on screen where they are", arguments: StackPath.allCases)
    func renamedTopRowKeepsItsPlace(path: StackPath) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top })
        else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        // Three thousand on, so a row of three heights keeps its own.
        scroller.items[index] = Row(id: top + 3_000)
        let after = scroller.frame()
        #expect(after.map { $0 == "row \(top + 3_000)" ? "row \(top)" : $0 } == before, "before: \(before)\nafter:  \(after)")
    }

    /// Rows inserted above the top row in the same change as a row inserted
    /// just after it, or the row after it removed: the row before it is still
    /// beside it, so this is no sort, and it is held. Asked of the row after
    /// it alone, the hold took the change for a sort and let the rows move.
    @Test(
        "Rows inserted above the top row are held through a change beside it in the same update",
        arguments: StackPath.allCases, [true, false])
    func insertionAboveWithAChangeBesideTheTopRow(path: StackPath, inserting: Bool) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top })
        else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        if inserting {
            scroller.items.insert(Row(id: 2_000), at: index + 1)
        } else {
            scroller.items.remove(at: index + 1)
        }
        scroller.insert(1_000..<1_005)
        let after = scroller.frame()
        #expect(after.first == "row \(top)", "before: \(before)\nafter:  \(after)")
    }

    /// The top row renamed in the change that inserts rows above it: the rows
    /// before and after it are still either side of one place, so the row in
    /// it changed and the rows above arrived, and the arrivals are held as any
    /// are. SwiftUI holds nothing here, the row it would hold gone
    /// (`Tools/SwiftUIProbes/Scroll anchoring/beside.out` case 2; decisions
    /// B-SCROLLANCHOR-6).
    @Test("A top row renamed as rows arrive above it keeps its place", arguments: StackPath.allCases)
    func renamedTopRowKeepsItsPlaceAsRowsArrive(path: StackPath) {
        let scroller = Scroller(path)
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        guard let top = rows(before).first, before.first == "row \(top)",
            let index = scroller.items.firstIndex(where: { $0.id == top })
        else {
            Issue.record("precondition: a whole row at the top \(before)")
            return
        }
        scroller.items[index] = Row(id: top + 3_000)
        scroller.insert(1_000..<1_005)
        let after = scroller.frame()
        #expect(after.map { $0 == "row \(top + 3_000)" ? "row \(top)" : $0 } == before, "before: \(before)\nafter:  \(after)")
    }

    /// The exact walk draws up to 256 rows of different heights and the
    /// anchored walk more; a change that takes the count across holds the
    /// row at the top as any other does — rows inserted above it ("load
    /// earlier"), and rows trimmed from the top of a capped log. Each path
    /// kept the row in its own memory, so the hold was lost crossing over, or
    /// taken from a frame long gone.
    @Test("Rows inserted above the top row are held as the stack crosses from the exact walk to the anchored")
    func heldAcrossIntoTheAnchoredWalk() {
        let scroller = Scroller(.exactWalk)
        scroller.items = (0..<250).map { Row(id: $0) }
        var before = scroller.scrolled(to: 30)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 31) }
        scroller.insert(1_000..<1_020)
        let after = scroller.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
        #expect(scroller.frame() == before)
    }

    @Test("Rows removed above the top row are held as the stack crosses from the anchored walk to the exact")
    func heldAcrossIntoTheExactWalk() {
        let scroller = Scroller(.anchoredWalk)
        scroller.items = (0..<270).map { Row(id: $0) }
        // Scrolled once, with the exact walk drawing, then grown onto the
        // anchored walk at the end and scrolled on: the exact walk's memory of
        // its top row is the first scroll's.
        scroller.items = (0..<250).map { Row(id: $0) }
        scroller.scrolled(to: 30)
        scroller.items += (250..<270).map { Row(id: $0) }
        var before = scroller.scrolled(to: 100)
        if before.first?.isEmpty != false { before = scroller.scrolled(to: 101) }
        scroller.items.removeSubrange(0..<20)
        let after = scroller.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
        #expect(scroller.frame() == before)
    }

    @Test("At its top, a view shows rows inserted above, as SwiftUI's does", arguments: StackPath.allCases)
    func atTheTopTheNewRowsShow(path: StackPath) {
        let scroller = Scroller(path)
        scroller.frame()
        scroller.frame()
        scroller.insert(1_000..<1_005)
        let after = scroller.frame()
        #expect(rows(after).first == 1_000, "\(after)")
    }

    @Test("Under .scrollWindowHold(.offset) the rows on screen move with the rows inserted above", arguments: StackPath.allCases)
    func offsetHoldMovesTheRows(path: StackPath) {
        let scroller = Scroller(path)
        scroller.hold = .offset
        let before = scroller.scrolled(to: 30)
        scroller.insert(1_000..<1_005)
        let after = scroller.frame()
        guard let first = rows(before).first, let moved = rows(after).first else {
            Issue.record("precondition: rows on screen \(before) \(after)")
            return
        }
        #expect(moved < first, "the same lines now show earlier rows: before \(before)\nafter \(after)")
    }

    @Test("A change made under no adjustment is not held, and the next one is", arguments: StackPath.allCases)
    func disabledAdjustmentIsNotHeld(path: StackPath) {
        let scroller = Scroller(path)
        let before = scroller.scrolled(to: 30)
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        scroller.insert(1_000..<1_005)
        let released = scroller.frame(disabled)
        #expect(released != before, "not held: \(released)")
        scroller.insert(2_000..<2_003)
        #expect(scroller.frame() == released, "held from where the change left it")
    }

    @Test("A bottom-anchored view following its tail follows it through rows inserted above")
    func followingTheTailIsUnaffected() {
        let scroller = Scroller(.uniform)
        scroller.declared = .bottom
        scroller.frame()
        let before = scroller.frame()
        #expect(rows(before).last == 59, "precondition: at the tail \(before)")
        scroller.insert(1_000..<1_005)
        scroller.items.append(Row(id: 60))
        #expect(rows(scroller.frame()).last == 60, "the follow, not the hold, places it")
    }

    @Test("A bottom-anchored view scrolled up from its tail is held, as SwiftUI's is", arguments: StackPath.allCases)
    func releasedBottomAnchorIsHeld(path: StackPath) {
        let scroller = Scroller(path)
        scroller.declared = .bottom
        let before = scroller.scrolled(to: 30)
        scroller.insert(1_000..<1_005)
        #expect(scroller.frame() == before, "before: \(before)")
    }

    /// The hold moves the offset at no one's request, so a focus move in the
    /// same frame is revealed as on any other: Tab onto the row below the
    /// screen as rows arrive above. Reported as a seek's offset is, the hold
    /// turned the reveal off for its frame, and the focused row stayed off
    /// screen.
    @Test("Focus moved off screen in the frame that holds the top row is revealed")
    func focusIsRevealedOnAHoldingFrame() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<60)
        var position = ScrollPosition()
        func frame() -> [String] {
            let view = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { Button("row \($0)") {} }
                }
            }
            .scrollPosition(Binding(get: { position }, set: { position = $0 }))
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: 8, environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped }
        }
        func shown(_ lines: [String]) -> [Int] {
            lines.compactMap { line in line.firstMatch(of: /row (\d+)/).flatMap { Int($0.1) } }
        }
        func focusedRow() -> Int? {
            focusManager.currentFocusedID.flatMap { $0.matches(of: /\[(\d+)\]/).last }.flatMap { Int($0.1) }
        }
        _ = frame()
        position.scrollTo(y: 30)
        _ = frame()
        _ = frame()
        // The last row on screen focused, and revealed if it was not.
        let onScreen = shown(frame())
        guard let last = onScreen.last,
            let id = focusManager.registeredFocusIDsInActiveSection().first(where: { $0.contains("[\(last)]") })
        else {
            Issue.record("precondition: rows on screen \(onScreen)")
            return
        }
        focusManager.focus(id: id)
        let before = frame()
        #expect(focusedRow() == last && shown(before).contains(last), "precondition: \(before)")
        // Then, in one frame, rows inserted above and focus moved to the row
        // below the screen.
        items.insert(contentsOf: 1_000..<1_005, at: 0)
        focusManager.focusNext()
        let after = frame()
        guard let focused = focusedRow() else {
            Issue.record("precondition: a row focused")
            return
        }
        #expect(focused == last + 1, "precondition: focus moved on")
        #expect(shown(after).contains(focused), "before: \(before)\nafter:  \(after)")
        #expect(shown(after).contains(last), "the rows on screen held: \(after)")
    }

    // MARK: - List and Table

    enum ListKind: String, CaseIterable, Sendable { case list, table, multiLineTable }

    /// One `List` or `Table`, rendered frame by frame as its rows change.
    @MainActor
    final class Lister {
        let kind: ListKind
        var items = (0..<40).map { Row(id: $0) }
        var anchor: ScrollAnchor<Int>?
        var hold: ScrollWindowHold?
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        init(_ kind: ListKind) { self.kind = kind }

        /// Inserts rows `ids` before the first row.
        func insert(_ ids: Range<Int>) { items.insert(contentsOf: ids.map { Row(id: $0) }, at: 0) }

        private var height: Int { kind == .multiLineTable ? 20 : 8 }

        private var view: AnyView {
            let anchor = Binding.constant(self.anchor)
            switch kind {
            case .list:
                return AnyView(List(items) { Text($0.name) }.anchorPosition(anchor))
            case .table:
                return AnyView(
                    Table(items, selection: .constant(Int?.none)) { TableColumn("Name", value: \Row.name) }
                        .anchorPosition(anchor))
            case .multiLineTable:
                return AnyView(
                    Table(items, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \Row.tallName).lineLimit(2)
                    }
                    .anchorPosition(anchor))
            }
        }

        @discardableResult
        func frame(_ transaction: Transaction = Transaction()) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.transaction = transaction
            if let hold { environment.scrollWindowHold = hold }
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 28, availableHeight: height, environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view.frame(height: height), context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }

        /// Scrolls down by designating row 25 from off screen, which brings it
        /// into view, and then letting the designation go.
        @discardableResult
        func scrolledDown() -> [String] {
            anchor = .row(25)
            frame()
            frame()
            anchor = nil
            frame()
            return frame()
        }
    }

    /// The first row each line shows, top to bottom (a line of a `Table` row
    /// that wraps names it more than once).
    func listedRows(_ lines: [String]) -> [Int] {
        lines.compactMap { line in line.firstMatch(of: /row (\d+)/).flatMap { Int($0.1) } }
    }

    @Test("A List's or Table's rows inserted above the top row leave the rows on screen where they are", arguments: ListKind.allCases)
    func listInsertionAboveIsHeld(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        #expect(listedRows(before).first.map { $0 > 5 } == true, "precondition: scrolled down \(before)")
        lister.insert(1_000..<1_005)
        let after = lister.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
        #expect(lister.frame() == before)
    }

    @Test("A List's or Table's rows removed above the top row leave the rows on screen where they are", arguments: ListKind.allCases)
    func listRemovalAboveIsHeld(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        lister.items.removeSubrange(0..<5)
        let after = lister.frame()
        #expect(after == before, "before: \(before)\nafter:  \(after)")
    }

    @Test("A List's or Table's rows reordered around the top row are not followed", arguments: ListKind.allCases)
    func listReorderIsNotFollowed(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        lister.items.reverse()
        let after = lister.frame()
        #expect(listedRows(after).first != listedRows(before).first, "followed: before \(before)\nafter \(after)")
    }

    @Test("A List's or Table's top row whose id changes in place leaves the rows on screen where they are", arguments: ListKind.allCases)
    func listRenamedTopRowKeepsItsPlace(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }) else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        lister.items[index] = Row(id: top + 3_000)
        let after = lister.frame()
        let renamed = listedRows(after).map { $0 == top + 3_000 ? top : $0 }
        #expect(renamed == listedRows(before), "before: \(before)\nafter:  \(after)")
    }

    @Test(
        "A List's or Table's rows inserted above the top row are held through a change beside it in the same update",
        arguments: ListKind.allCases, [true, false])
    func listInsertionAboveWithAChangeBesideTheTopRow(kind: ListKind, inserting: Bool) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }) else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        if inserting {
            lister.items.insert(Row(id: 2_000), at: index + 1)
        } else {
            lister.items.remove(at: index + 1)
        }
        lister.insert(1_000..<1_005)
        let after = lister.frame()
        #expect(listedRows(after).first == top, "before: \(before)\nafter:  \(after)")
    }

    @Test("A List's or Table's top row renamed as rows arrive above it keeps its place", arguments: ListKind.allCases)
    func listRenamedTopRowKeepsItsPlaceAsRowsArrive(kind: ListKind) {
        let lister = Lister(kind)
        let before = lister.scrolledDown()
        guard let top = listedRows(before).first, let index = lister.items.firstIndex(where: { $0.id == top }) else {
            Issue.record("precondition: rows on screen \(before)")
            return
        }
        lister.items[index] = Row(id: top + 3_000)
        lister.insert(1_000..<1_005)
        let after = lister.frame()
        let renamed = listedRows(after).map { $0 == top + 3_000 ? top : $0 }
        #expect(renamed == listedRows(before), "before: \(before)\nafter:  \(after)")
    }

    @Test("At its top, a List or Table shows rows inserted above", arguments: ListKind.allCases)
    func listAtTheTopTheNewRowsShow(kind: ListKind) {
        let lister = Lister(kind)
        lister.frame()
        lister.frame()
        lister.insert(1_000..<1_005)
        #expect(listedRows(lister.frame()).first == 1_000)
    }

    @Test("Under .scrollWindowHold(.offset) a List's or Table's rows move with the rows inserted above", arguments: ListKind.allCases)
    func listOffsetHoldMovesTheRows(kind: ListKind) {
        let lister = Lister(kind)
        lister.hold = .offset
        let before = lister.scrolledDown()
        lister.insert(1_000..<1_005)
        let after = lister.frame()
        guard let first = listedRows(before).first, let moved = listedRows(after).first else {
            Issue.record("precondition: rows on screen \(before) \(after)")
            return
        }
        #expect(moved < first, "the same lines now show earlier rows: before \(before)\nafter \(after)")
    }

    @Test("A change made under no adjustment is not held in a List, and the next one is")
    func listDisabledAdjustmentIsNotHeld() {
        let lister = Lister(.list)
        let before = lister.scrolledDown()
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        lister.insert(1_000..<1_005)
        let released = lister.frame(disabled)
        #expect(released != before, "not held: \(released)")
        lister.insert(2_000..<2_003)
        #expect(lister.frame() == released, "held from where the change left it")
    }

    /// The cursor is a row INDEX: left where it was, it would point at the row
    /// five above the one the user was on — drawn five lines up, or off screen
    /// above, where the next arrow key's reveal would scroll back to it and
    /// undo the hold.
    @Test("The focus cursor moves with the rows the hold keeps in place")
    func cursorMovesWithTheHeldRows() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        handler.itemIDs = Array(0..<40)
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 10
        handler.focusedIndex = 12
        settle()
        handler.itemIDs = Array(100..<105) + Array(0..<40)
        handler.itemCount = 45
        settle()
        #expect(handler.scrollOffset == 15)
        #expect(handler.id(at: handler.focusedIndex) == 12)
    }

    /// The list's own move — a row moved by a page with the keyboard, or
    /// dropped — places the cursor on the row it moved and reveals it. Moved
    /// onto the top row's place, the row pushed the top row down by one, and
    /// the hold took that for a row inserted above it: it scrolled the moved
    /// row out of view and moved the cursor onto the old top row, where the
    /// next chord acted.
    @Test("A row the list moves onto its top row's place stays on screen, with the cursor on it")
    func listOwnMoveIsNotHeld() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        var ids = Array(0..<40)
        handler.itemIDs = ids
        handler.onMove = { source, destination in
            ids.move(fromOffsets: source, toOffset: destination)
            handler.itemIDs = ids
        }
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 10
        handler.focusedIndex = 17
        settle()
        #expect(handler.scrollOffset == 10, "precondition")
        #expect(handler.nudgeFocusedRow(by: -handler.pageStep))
        #expect(handler.focusedIndex == 10, "precondition: moved onto the top row's place")
        settle()
        #expect(handler.scrollOffset == 10)
        #expect(handler.id(at: handler.focusedIndex) == 17)
    }

    /// Rows prepended to a long list scrolled deep: the top row is found where
    /// it went by a search outward from where it was, not by a scan from row
    /// 0 — an id can cost a build of its row (`ItemListHandler.id(at:)`), and
    /// this runs on every frame that inserts above.
    @Test("A List finds its top row near where it was, not by a scan from the first row")
    func listFindsItsTopRowNearby() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 5_000, viewportHeight: 8, selectionMode: .single, canBeFocused: true)
        var ids = Array(0..<5_000)
        var reads = 0
        handler.idAt = { index in
            reads += 1
            return ids[index]
        }
        func settle() {
            handler.settleScrollPosition(
                measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        }
        settle()
        handler.scrollOffset = 3_000
        handler.focusedIndex = 3_000
        settle()
        ids.insert(contentsOf: 10_000..<10_003, at: 0)
        handler.itemCount = 5_003
        reads = 0
        settle()
        #expect(handler.scrollOffset == 3_003, "held")
        #expect(reads < 100, "\(reads) ids read")
    }
}
