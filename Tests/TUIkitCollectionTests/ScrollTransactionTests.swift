//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTransactionTests.swift
//
//  `Transaction.scrollTargetAnchor`, `.scrollContentOffsetAdjustmentBehavior`
//  and `.scrollPositionUpdatePreservesVelocity`: what a change made under a
//  transaction asks of the scroll views it moves. The run loop publishes the
//  transaction a change was made under for the frame that renders it; these
//  tests publish it the same way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

private struct TransactionRow: Identifiable, Sendable {
    let id: Int
    var name: String { "row \(id)" }
}

@MainActor
@Suite("Scroll transactions")
struct ScrollTransactionTests {

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, transaction: Transaction = Transaction(), height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.transaction = transaction
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func anchoredBottom(_ anchor: UnitPoint) -> Transaction {
        var transaction = Transaction()
        transaction.scrollTargetAnchor = anchor
        return transaction
    }

    @Test("The members read back, with SwiftUI's defaults")
    func values() {
        var transaction = Transaction()
        #expect(transaction.scrollTargetAnchor == nil)
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .automatic)
        #expect(!transaction.scrollPositionUpdatePreservesVelocity)
        transaction.scrollTargetAnchor = .bottom
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        transaction.scrollPositionUpdatePreservesVelocity = true
        #expect(transaction.scrollTargetAnchor == .bottom)
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .disabled)
        #expect(transaction.scrollPositionUpdatePreservesVelocity)
        #expect(transaction != Transaction())
    }

    @Test("The members share bytes without touching each other, and the anchor keeps hundredths")
    func packedStorage() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .automatic)
        #expect(!transaction.scrollPositionUpdatePreservesVelocity)
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        transaction.disablesAnimations = false
        #expect(transaction.scrollContentOffsetAdjustmentBehavior == .disabled)
        #expect(!transaction.disablesAnimations)

        transaction.scrollTargetAnchor = UnitPoint(x: 0.333, y: 0.7)
        #expect(transaction.scrollTargetAnchor == UnitPoint(x: 0.33, y: 0.7))
        transaction.scrollTargetAnchor = .zero
        #expect(transaction.scrollTargetAnchor == .zero, "zero is a point, not none")
        transaction.scrollTargetAnchor = nil
        #expect(transaction.scrollTargetAnchor == nil)
        // A Binding carries a transaction inline; the anchor costs two bytes.
        #expect(MemoryLayout<Transaction>.size == 84)
        #expect(interiorPadding(of: Transaction.self).isEmpty)
    }

    @Test("A transaction's anchor places the row an id binding asks for")
    func anchorForIDBinding() {
        let frames = Frames()
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(id: binding)
        frames.render(view)
        visible = 20
        let landed = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(landed.last == "row 20", "\(landed)")
    }

    @Test("A request's own anchor wins over the transaction's; without one, the transaction's applies")
    func anchorForPositionRequest() {
        let frames = Frames()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
        }
        .scrollPosition(binding)
        frames.render(view)
        position.scrollTo(id: 20)
        let unanchored = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(unanchored.last == "row 20", "\(unanchored)")
        position.scrollTo(id: 30, anchor: .top)
        let anchored = frames.render(view, transaction: anchoredBottom(.bottom))
        #expect(anchored.first == "row 30", "\(anchored)")
    }

    @Test("A disabled adjustment leaves a following ScrollView where it is, and releases the follow")
    func disabledAdjustmentReleasesScrollViewFollow() {
        let frames = Frames()
        var count = 10
        func view() -> some View {
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<count, id: \.self) { Text("row \($0)") } }
            }
            .defaultScrollAnchor(.bottom)
        }
        let opened = frames.render(view())
        #expect(opened.last == "row 9", "precondition: following the tail \(opened)")

        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        count = 13
        let held = frames.render(view(), transaction: disabled)
        #expect(held.last == "row 9", "not followed: \(held)")
        count = 14
        let after = frames.render(view())
        #expect(after.last == "row 9", "released, as a user scroll releases it: \(after)")

        // Control: without the transaction it follows.
        let control = Frames()
        count = 10
        control.render(view())
        count = 13
        #expect(control.render(view()).last == "row 12")
    }

    /// The three windowed paths a `LazyVStack` holds a designated row on, each
    /// with its own hold: arithmetic over equal rows, and over rows of three
    /// heights the exact walk (up to 256 rows) and the anchored walk (more).
    enum StackPath: String, CaseIterable, Sendable {
        case uniform, exactWalk, anchoredWalk

        var count: Int { self == .anchoredWalk ? 300 : 60 }
        func height(_ row: Int) -> Int { self == .uniform ? 1 : row % 3 + 1 }
    }

    @Test(
        "A disabled adjustment lets a lazy stack's held row go, and the next change holds it where it was left",
        arguments: StackPath.allCases)
    func disabledAdjustmentLetsStackRowGo(path: StackPath) {
        func run(disabling: Bool) -> (
            designated: Int, before: Int?, released: Int?, after: Int?, frames: [[String]]
        ) {
            let frames = Frames()
            var items = Array(0..<path.count)
            // Row 26 is designated from off screen, so the view scrolls to it;
            // then the first row the frame shows below its top line is held,
            // a line or more down, with room under it for the rows to move.
            var designated = 26
            func view() -> some View {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.self) { Text("row \($0)").frame(height: path.height($0)) }
                    }
                }
                .anchorPosition(.constant(ScrollAnchor<Int>.row(designated)))
            }
            func line(_ lines: [String]) -> Int? { lines.firstIndex { $0 == "row \(designated)" } }
            let revealed = frames.render(view(), height: 8)
            guard let held = revealed.dropFirst().first(where: { !$0.isEmpty }), let row = Int(held.dropFirst(4))
            else { return (designated, nil, nil, nil, [revealed]) }
            designated = row
            frames.render(view(), height: 8)
            let settled = frames.render(view(), height: 8)
            var disabled = Transaction()
            disabled.scrollContentOffsetAdjustmentBehavior = disabling ? .disabled : .automatic
            // One-line rows keep the equal-height arithmetic; the others add
            // three lines between them.
            items.insert(contentsOf: path == .uniform ? [1000, 1003] : [1000, 1002], at: 0)
            let released = frames.render(view(), transaction: disabled, height: 8)
            items.insert(path == .uniform ? 1006 : 1003, at: 0)
            let after = frames.render(view(), height: 8)
            return (designated, line(settled), line(released), line(after), [settled, released, after])
        }

        let suspended = run(disabling: true)
        guard let before = suspended.before, let released = suspended.released else {
            Issue.record("precondition: the held row is on screen \(suspended.frames)")
            return
        }
        // Not held: the row moves down by the lines the change put above it —
        // to the bottom line at most, the nearest in view. On the anchored walk
        // those are the lines of the two rows now at the ordinals it was drawn
        // from, the rows that were above it: the walk keeps its anchor's
        // ordinal (Scroll anchoring.md §5), and never measures the rows
        // inserted at the top.
        let lines: Int
        switch path {
        case .uniform: lines = 2
        case .exactWalk: lines = path.height(1000) + path.height(1002)
        case .anchoredWalk:
            lines = path.height(suspended.designated - 2) + path.height(suspended.designated - 1)
        }
        #expect(
            released == min(before + lines, 8 - path.height(suspended.designated)),
            "not held: the rows moved with the change \(suspended.frames)")
        #expect(suspended.after == released, "held again where the change left it \(suspended.frames)")

        // Control: without the transaction the row keeps its line throughout.
        let held = run(disabling: false)
        #expect(held.before == before && held.released == before && held.after == before, "\(held.frames)")
    }

    /// A change that pushes the row let go off screen leaves it on the line in
    /// view nearest where the change put it — the bottom line when rows were
    /// inserted above it, the top when they were removed — as a row designated
    /// off screen is brought into view, and on every path alike. The anchored
    /// walk put it on the top line either way once it was more than a screen
    /// of rows from where it was drawn.
    @Test(
        "A change under no adjustment that pushes a held row off screen leaves it on the nearest line in view",
        arguments: StackPath.allCases, [true, false])
    func disabledChangePushingTheHeldRowOffScreen(path: StackPath, inserting: Bool) {
        let frames = Frames()
        var items = Array(0..<path.count)
        var designated = 40
        func view() -> some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { Text("row \($0)").frame(height: path.height($0)) }
                }
            }
            .anchorPosition(.constant(ScrollAnchor<Int>.row(designated)))
        }
        func rows(_ lines: [String]) -> [Int] {
            lines.compactMap { $0.hasPrefix("row ") ? Int($0.dropFirst(4)) : nil }
        }
        // Row 40 is designated from off screen, so the view scrolls to it; then
        // a row three lines or so down is held.
        let revealed = frames.render(view(), height: 8)
        guard let held = revealed.dropFirst(3).first(where: { !$0.isEmpty }), let row = Int(held.dropFirst(4))
        else {
            Issue.record("precondition: rows on screen \(revealed)")
            return
        }
        designated = row
        frames.render(view(), height: 8)
        let settled = frames.render(view(), height: 8)
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        if inserting {
            items.insert(contentsOf: 1_000..<1_020, at: 0)
        } else {
            items.removeSubrange(0..<20)
        }
        let released = frames.render(view(), transaction: disabled, height: 8)
        let edge = inserting ? rows(released).last : rows(released).first
        #expect(edge == designated, "settled \(settled)\nreleased \(released)")
    }

    /// The row let go is adopted by a walk from the anchor as last drawn, which
    /// the change can leave past the end of the data: the last of 300 rows,
    /// held, with two rows above it removed. The walk asked for a row that is
    /// not there, and the app trapped.
    @Test("A lazy stack's held last row, let go as rows above it are removed, is adopted, not walked past the data")
    func disabledRemovalAboveTheHeldLastRow() {
        let frames = Frames()
        var items = Array(0..<300)
        func view() -> some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { Text("row \($0)").frame(height: $0 % 3 + 1) }
                }
            }
            .anchorPosition(.constant(ScrollAnchor<Int>.row(299)))
        }
        frames.render(view(), height: 8)
        let settled = frames.render(view(), height: 8)
        #expect(settled.contains("row 299"), "precondition: the last row held on screen \(settled)")
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        items.removeFirst(2)
        let released = frames.render(view(), transaction: disabled, height: 8)
        #expect(released.contains("row 299"), "\(released)")
    }

    enum ListKind: String, CaseIterable, Sendable { case list, table }

    @Test(
        "A disabled adjustment lets a List's or Table's held row go, and the next change holds it where it was left",
        arguments: ListKind.allCases)
    func disabledAdjustmentLetsListRowGo(kind: ListKind) {
        func run(disabling: Bool) -> (before: Int?, released: Int?, after: Int?, frames: [[String]]) {
            let frames = Frames()
            var items = Array(0..<40)
            // Row 12 is designated from off screen, so the view scrolls to it;
            // then a row nearer the top is held, with room under it to move.
            var designated = 12
            func view() -> AnyView {
                let anchor = Binding.constant(ScrollAnchor<Int>?.some(.row(designated)))
                switch kind {
                case .list:
                    return AnyView(List(items, id: \.self) { Text("row \($0)") }.anchorPosition(anchor))
                case .table:
                    return AnyView(
                        Table(items.map(TransactionRow.init), selection: .constant(Int?.none)) {
                            TableColumn("Name", value: \TransactionRow.name)
                        }
                        .anchorPosition(anchor))
                }
            }
            func row(_ line: String) -> Int? {
                line.firstMatch(of: /row (\d+)\b/).flatMap { Int($0.1) }
            }
            func line(_ lines: [String]) -> Int? { lines.firstIndex { row($0) == designated } }
            let revealed = frames.render(view(), height: 8)
            guard let held = revealed.dropFirst(2).lazy.compactMap(row).first else {
                return (nil, nil, nil, [revealed])
            }
            designated = held
            frames.render(view(), height: 8)
            let settled = frames.render(view(), height: 8)
            var disabled = Transaction()
            disabled.scrollContentOffsetAdjustmentBehavior = disabling ? .disabled : .automatic
            items.insert(contentsOf: [100, 101], at: 0)
            let released = frames.render(view(), transaction: disabled, height: 8)
            items.insert(102, at: 0)
            let after = frames.render(view(), height: 8)
            return (line(settled), line(released), line(after), [settled, released, after])
        }

        let suspended = run(disabling: true)
        guard let before = suspended.before, let released = suspended.released else {
            Issue.record("precondition: the held row is on screen \(suspended.frames)")
            return
        }
        #expect(released > before, "not held: the rows moved with the change \(suspended.frames)")
        #expect(suspended.after == released, "held again where the change left it \(suspended.frames)")

        let held = run(disabling: false)
        #expect(held.before == before && held.released == before && held.after == before, "\(held.frames)")
    }

    @Test("A disabled adjustment leaves a following List where it is, and releases the follow")
    func disabledAdjustmentReleasesListFollow() {
        let frames = Frames()
        var count = 10
        func view() -> some View {
            List(0..<count, id: \.self) { Text("row \($0)") }
                .defaultScrollAnchor(.bottom)
        }
        frames.render(view(), height: 8)
        let opened = frames.render(view(), height: 8)
        #expect(opened.contains { $0.contains("row 9 ") }, "precondition: \(opened)")
        var disabled = Transaction()
        disabled.scrollContentOffsetAdjustmentBehavior = .disabled
        count = 13
        let held = frames.render(view(), transaction: disabled, height: 8)
        #expect(!held.contains { $0.contains("row 12 ") }, "not followed: \(held)")
        count = 14
        let after = frames.render(view(), height: 8)
        #expect(!after.contains { $0.contains("row 13 ") }, "released: \(after)")

        let control = Frames()
        count = 10
        control.render(view(), height: 8)
        count = 13
        #expect(control.render(view(), height: 8).contains { $0.contains("row 12 ") })
    }
}
