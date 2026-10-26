//  🖥️ TUI — A Terminal UI framework for Swift
//  ListTableGlideTests.swift
//
//  A `List`'s and a `Table`'s animated programmatic scroll (decisions
//  B27-ANIMATING, piece 6): a `scrollTo` or a bound `.scrollPosition`
//  request made inside `withAnimation` glides a row at a time, without moving
//  the cursor or the selection, and the list reports its scroll phases —
//  `.animating` while it glides, `.interacting` for a user's scroll — to
//  `onScrollPhaseChange`, as SwiftUI's list does. Drawn with `GlideFrames`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

// `let _ = box.proxy = proxy` captures the proxy inside a `@ViewBuilder`
// closure, where `_ =` is not a statement the builder accepts.
// swiftlint:disable redundant_discardable_let

/// The first row a frame shows, by its number: the first `row N` or
/// `item N` on any line, so a table's header and a list's cursor marks are
/// passed over.
private func firstRow(_ lines: [String]) -> Int? {
    for line in lines {
        guard let range = line.range(of: #"(row|item) \d+"#, options: .regularExpression) else { continue }
        return Int(line[range].split(separator: " ").last ?? "")
    }
    return nil
}

/// A row of the table below.
private struct Numbered: Identifiable, Sendable {
    let id: Int
}

/// Rows a test inserts into while a glide runs.
@MainActor
private final class GlideIDs {
    var values = Array(0..<200)
}

/// The selection the views below are bound to.
@MainActor
private final class GlideSelection {
    var value: Int? = 2
}

@MainActor
@Suite("Animated scrolling: a List's and a Table's requests glide, and they report phases")
struct ListTableGlideTests {

    private func list(_ box: GlideProxyBox, _ selection: GlideSelection, log: GlidePhaseLog) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            List(selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                ForEach(0..<200, id: \.self) { Text("row " + String($0)) }
            }
            .onScrollPhaseChange { old, new in log.changes.append("\(old)→\(new)") }
        }
    }

    private func table(_ box: GlideProxyBox, _ selection: GlideSelection, log: GlidePhaseLog) -> some View {
        ScrollViewReader { proxy in
            let _ = box.proxy = proxy
            Table((0..<200).map(Numbered.init), selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                TableColumn("N") { (row: Numbered) in Text("item " + String(row.id)) }
            }
            .onScrollPhaseChange { old, new in log.changes.append("\(old)→\(new)") }
        }
    }

    /// The list's or table's handler, once drawn.
    private func listHandler(_ frames: GlideFrames) -> ItemListHandler<Int>? {
        frames.focusManager.activeSection?.focusables.compactMap { $0 as? ItemListHandler<Int> }.first
    }

    /// Draws `view` through a glide to row 120, and checks what each frame
    /// shows and what the list reports.
    private func glidesWithoutMovingTheCursor(
        _ view: some View, box: GlideProxyBox, selection: GlideSelection, frames: GlideFrames
    ) throws {
        frames.render(view)
        let handler = try #require(listHandler(frames))
        let cursor = handler.focusedIndex
        withAnimation(.easeInOut(duration: 0.5)) { box.proxy?.scrollTo(120, anchor: .top) }
        let start = frames.render(view)
        #expect(firstRow(start) == 0, "the request's frame shows where the list stands: \(start)")
        var tops: [Int] = []
        while let wake = frames.nextWake, tops.count < 200 {
            tops.append(firstRow(frames.render(view, atNanos: wake)) ?? -1)
        }
        #expect(tops.last == 120, "lands with the row at the top: \(tops)")
        #expect(Set(tops).count > 10, "through the rows between: \(tops)")
        #expect(zip(tops, tops.dropFirst()).allSatisfy { $0 <= $1 }, "an ease never goes back: \(tops)")
        #expect(handler.glide == nil)
        #expect(handler.focusedIndex == cursor, "the cursor stays where it was")
        #expect(selection.value == 2, "and so does the selection")
    }

    @Test("A List's animated scrollTo glides a row at a time, leaving the cursor and the selection", arguments: [false, true])
    func listGlides(isTable: Bool) throws {
        let frames = GlideFrames()
        let (box, selection, log) = (GlideProxyBox(), GlideSelection(), GlidePhaseLog())
        if isTable {
            try glidesWithoutMovingTheCursor(table(box, selection, log: log), box: box, selection: selection, frames: frames)
        } else {
            try glidesWithoutMovingTheCursor(list(box, selection, log: log), box: box, selection: selection, frames: frames)
        }
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→idle"], "\(log.changes)")
        #expect(selection.value == 2)
    }

    @Test("An unanimated scrollTo, or one under reduce motion, jumps and reports no phase", arguments: [false, true])
    func jumps(reduceMotion: Bool) throws {
        let frames = GlideFrames()
        frames.reduceMotion = reduceMotion
        let (box, selection, log) = (GlideProxyBox(), GlideSelection(), GlidePhaseLog())
        let view = list(box, selection, log: log)
        frames.render(view)
        withAnimation(reduceMotion ? .linear(duration: 0.5) : nil) { box.proxy?.scrollTo(120, anchor: .top) }
        #expect(firstRow(frames.render(view)) == 120)
        #expect(listHandler(frames)?.glide == nil)
        #expect(log.changes == ["idle→idle"], "\(log.changes)")
    }

    @Test("The wheel mid-glide stops it where it stands, and the list is interacting, then idle")
    func wheelStopsTheGlide() throws {
        let frames = GlideFrames()
        let (box, selection, log) = (GlideProxyBox(), GlideSelection(), GlidePhaseLog())
        let view = table(box, selection, log: log)
        frames.render(view)
        let handler = try #require(listHandler(frames))
        handler.phaseNow = { UInt64(frames.now) }
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(120, anchor: .top) }
        frames.render(view)
        for _ in 0..<10 { if let wake = frames.nextWake { frames.render(view, atNanos: wake) } }
        let reached = handler.scrollOffset
        #expect(reached > 0 && reached < 120, "under way: \(reached)")
        handler.userScrollFine(by: 3)
        #expect(handler.glide == nil, "stopped at the wheel")
        frames.render(view, atNanos: frames.now + 1)
        #expect(log.changes == ["idle→idle", "idle→animating", "animating→interacting"], "\(log.changes)")
        let later = frames.render(view, atNanos: frames.now + Int64(ScrollPhase.quietNanos))
        #expect(firstRow(later) == reached + 3, "from where it stood, and no further: \(later)")
        #expect(log.changes.last == "interacting→idle", "\(log.changes)")
    }

    @Test("Moving the cursor mid-glide stops it")
    func cursorStopsTheGlide() throws {
        let frames = GlideFrames()
        let (box, selection, log) = (GlideProxyBox(), GlideSelection(), GlidePhaseLog())
        let view = list(box, selection, log: log)
        frames.render(view)
        let handler = try #require(listHandler(frames))
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(120, anchor: .top) }
        frames.render(view)
        for _ in 0..<5 { if let wake = frames.nextWake { frames.render(view, atNanos: wake) } }
        #expect(handler.glide != nil)
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.glide == nil, "the cursor's move stopped it")
        frames.render(view, atNanos: frames.now + 1)
        #expect(log.changes.last == "animating→idle", "\(log.changes)")
    }

    @Test("Rows inserted between the viewport and the row mid-glide are corrected by the landing")
    func insertionBetweenIsReSought() throws {
        let frames = GlideFrames()
        let box = GlideProxyBox()
        let ids = GlideIDs()
        func view() -> some View {
            ScrollViewReader { proxy in
                let _ = box.proxy = proxy
                List { ForEach(ids.values, id: \.self) { Text("row " + String($0)) } }
            }
        }
        frames.render(view())
        withAnimation(.linear(duration: 1)) { box.proxy?.scrollTo(120, anchor: .top) }
        frames.render(view())
        for _ in 0..<5 { if let wake = frames.nextWake { frames.render(view(), atNanos: wake) } }
        let handler = try #require(listHandler(frames))
        #expect(handler.glide != nil, "under way")
        ids.values.insert(contentsOf: 1_000..<1_005, at: 100)
        let landed = frames.follow(view())
        #expect(firstRow(landed.last?.lines ?? []) == 120, "the landing finds the row again: \(landed.last?.lines ?? [])")
    }

    @Test("A bound scrollPosition(id:) row request glides, and is told the row once, on landing")
    func positionGlides() {
        let frames = GlideFrames()
        var writes: [Int?] = []
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0; writes.append($0) })
        let view = List {
            ForEach(0..<200, id: \.self) { Text("row " + String($0)) }
        }
        .scrollPosition(id: binding, anchor: .top)
        frames.render(view)
        frames.render(view)
        writes.removeAll()
        visible = 90
        let start = frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        #expect(firstRow(start) == 0, "\(start)")
        let tops = frames.follow(view).compactMap { firstRow($0.lines) }
        #expect(tops.count > 5 && tops.last == 90, "\(tops)")
        #expect(writes.allSatisfy { $0 == 90 } && writes.count <= 1, "only the row it lands on: \(writes)")
    }

    @Test("A bound position's edge made inside an animation glides there")
    func positionEdgeGlides() {
        let frames = GlideFrames()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = Table((0..<200).map(Numbered.init)) {
            TableColumn("N") { (row: Numbered) in Text("item " + String(row.id)) }
        }
        .scrollPosition(binding)
        frames.render(view)
        position.scrollTo(edge: .bottom)
        frames.render(view, transaction: Transaction(animation: .linear(duration: 0.5)))
        let landed = frames.follow(view)
        #expect(landed.count > 5)
        #expect(landed.last?.lines.contains { $0.contains("item 199") } == true, "\(landed.last?.lines ?? [])")
    }
}

// swiftlint:enable redundant_discardable_let
