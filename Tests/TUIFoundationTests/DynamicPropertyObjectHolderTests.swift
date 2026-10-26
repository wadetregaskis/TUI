//  🖥️ TUI — A Terminal UI framework for Swift
//  DynamicPropertyObjectHolderTests.swift
//
//  A class property's `@State` is the object's own, which no view's key
//  holds, so the object's state survives a change of the view holding it
//  (decisions-DYNVFIX B-DYNVFIX-3). The storage kept each box under the key
//  of the view that claimed the object, and dropped it with that key — the
//  view's place pruned, an `if`/`else` flipped, its key given to another
//  object's box — though the object still held it, with its value.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What each body hands out, by the name of the view that handed it.
@MainActor
private final class HolderTaps {
    var counts: [String: Binding<Int>] = [:]
    var texts: [String: Binding<String>] = [:]
    var reads: [String] = []
}

/// A class app property holding a `@State`: one instance, handed to every
/// view that shows it.
private final class Item: DynamicProperty {
    @State var count = 0
}

/// A class property passed through a view that does not hold it as one, so
/// the views it is handed to are the first to reach it.
private struct Passed<Object: AnyObject> {
    let object: Object
}

/// A memoised row showing an item: equal while its name and generation are,
/// so it is served from the memo until either changes.
private struct ItemRow: View, Equatable {
    let name: String
    let generation: Int
    let item: Item
    let taps: HolderTaps

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.generation == rhs.generation
    }

    var body: some View {
        taps.counts[name] = item.$count
        return Text(verbatim: "\(name) \(item.count)")
    }
}

/// A view drawn every frame showing an item.
private struct ItemDetail: View {
    let item: Item
    let taps: HolderTaps

    var body: some View {
        taps.counts["detail"] = item.$count
        return Text(verbatim: "detail \(item.count)")
    }
}

/// A sidebar of memoised rows, one per item, and a detail view showing the
/// item at `selection`. An array is not looked into, so the rows and the
/// detail view are the first to reach the items.
private struct Sidebar: View {
    let items: [Item]
    let generations: [Int]
    let selection: Int
    let taps: HolderTaps

    var body: some View {
        VStack {
            ItemRow(name: "row0", generation: generations[0], item: items[0], taps: taps)
                .equatable().frame(height: 1)
            ItemRow(name: "row1", generation: generations[1], item: items[1], taps: taps)
                .equatable().frame(height: 1)
            ItemDetail(item: items[selection], taps: taps)
        }
    }
}

/// A class app property holding a draft's text.
private final class Draft: DynamicProperty {
    @State var text = ""
}

private struct DraftEditor: View {
    let draft: Draft
    let taps: HolderTaps

    var body: some View {
        taps.texts["editor"] = draft.$text
        return Text(verbatim: "editor \(draft.text)")
    }
}

private struct DraftSummary: View {
    let draft: Draft
    let taps: HolderTaps

    var body: some View {
        taps.texts["summary"] = draft.$text
        return Text(verbatim: "summary \(draft.text)")
    }
}

/// The draft shown by an editor or a summary, an `if`/`else` choosing, each
/// inside a stack: the branch's own identity is not below the branch, and
/// so not dropped with it, where its stack's child is.
private struct DraftScreen: View {
    let editing: Bool
    let draft: Passed<Draft>
    let taps: HolderTaps

    @ViewBuilder var body: some View {
        if editing {
            VStack { DraftEditor(draft: draft.object, taps: taps) }
        } else {
            VStack { DraftSummary(draft: draft.object, taps: taps) }
        }
    }
}

/// An item shown by two memoised rows, the first of which can be removed.
private struct TwoItemRows: View {
    let showsFirst: Bool
    let generation: Int
    let item: Passed<Item>
    let taps: HolderTaps

    var body: some View {
        VStack {
            if showsFirst {
                ItemRow(name: "a", generation: generation, item: item.object, taps: taps).equatable().frame(height: 1)
            }
            ItemRow(name: "b", generation: generation, item: item.object, taps: taps).equatable().frame(height: 1)
        }
    }
}

// MARK: - A property set on an object since its first holder walked it

private struct HolderAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var holderAccent: String {
        get { self[HolderAccent.self] }
        set { self[HolderAccent.self] = newValue }
    }
}

/// An observable model read from the environment inside a class property.
@Observable
private final class ScreenModel {
    var name = "model"
}

/// An app property set on a screen between frames: nothing has walked it
/// when it is first read.
private struct ScreenChild: DynamicProperty {
    @Environment(ScreenModel.self) var model
    @Environment(\.holderAccent) var accent
}

/// A class app property whose child property is set between frames.
private final class Screen: DynamicProperty {
    var child: ScreenChild?
    var generation = 0
}

/// A view showing the name of the model the screen's child reads.
private struct ModelScreenView: View {
    let screen: Screen

    var body: some View {
        Text(verbatim: screen.child?.model.name ?? "-")
    }
}

/// A view showing the accent the screen's child reads, noting each read: a
/// measure's and a draw's.
private struct AccentScreenView: View {
    let name: String
    let screen: Screen
    let taps: HolderTaps

    var body: some View {
        let accent = screen.child?.accent ?? "-"
        taps.reads.append("\(name) \(accent)")
        return Text(verbatim: "\(name) \(accent)")
    }
}

/// The screen, shown by a view whose identity is the screen's generation, in
/// a stack that measures it before drawing it.
private struct ReloadedScreen: View {
    let screen: Passed<Screen>

    var body: some View {
        VStack {
            ModelScreenView(screen: screen.object).id(screen.object.generation)
            Text(verbatim: "load")
        }
        .environment(ScreenModel())
    }
}

/// The screen, shown by a view and, when `showsB`, by another one above it,
/// which the stack measures first.
private struct ModelScreenPair: View {
    let showsB: Bool
    let screen: Passed<Screen>

    var body: some View {
        VStack {
            if showsB { ModelScreenView(screen: screen.object) }
            ModelScreenView(screen: screen.object)
        }
        .environment(ScreenModel())
    }
}

/// ``ModelScreenPair``, showing the accent.
private struct AccentScreenPair: View {
    let showsB: Bool
    let screen: Passed<Screen>
    let taps: HolderTaps

    var body: some View {
        VStack {
            if showsB { AccentScreenView(name: "b", screen: screen.object, taps: taps) }
            AccentScreenView(name: "a", screen: screen.object, taps: taps)
        }
        .environment(\.holderAccent, "red")
    }
}

@MainActor
@Suite("DynamicProperty objects changing holder")
struct DynamicPropertyObjectHolderTests {

    /// One frame as the render loop draws it, its render cache the one its
    /// state's writes invalidate: invalidations drained, the pass begun, the
    /// view made and drawn in it (`StateStorage.inRenderPass(_:)`), what was
    /// not drawn pruned.
    private func frame<V: View>(_ view: @autoclosure () -> V, _ tui: TUIContext, height: Int = 3) -> [String] {
        let context = RenderContext(availableWidth: 20, availableHeight: height, tuiContext: tui)
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

    /// A detail view took each item from the memo-served row that claimed
    /// it, and with it the item's `@State` box, kept under the detail's key;
    /// moving on to the next item kept that one's box under the same key and
    /// dropped the first's, though the first item still held it. When the
    /// first row was next drawn, it bound the item afresh, at its default,
    /// and going back bound the first item to the second's box (review of
    /// 8de82a920, 2026-10-12). An object's box is its own, which no view's
    /// key holds.
    @Test("A detail view moving from one memo-served row's object to the next leaves the first object's @State as it was")
    func detailMovingBetweenRowsKeepsEachObjectsState() {
        let tui = TUIContext()
        let taps = HolderTaps()
        let items = [Item(), Item()]
        let view = { (generations: [Int], selection: Int) in
            Sidebar(items: items, generations: generations, selection: selection, taps: taps)
        }
        #expect(frame(view([0, 0], 0), tui) == ["row0 0", "row1 0", "detail 0"])
        taps.counts["row0"]?.wrappedValue = 5
        #expect(frame(view([0, 0], 0), tui) == ["row0 5", "row1 0", "detail 5"])
        #expect(frame(view([0, 0], 0), tui) == ["row0 5", "row1 0", "detail 5"])
        #expect(frame(view([0, 0], 1), tui) == ["row0 5", "row1 0", "detail 0"])
        #expect(frame(view([1, 1], 1), tui) == ["row0 5", "row1 0", "detail 0"])
        #expect(frame(view([2, 2], 0), tui) == ["row0 5", "row1 0", "detail 5"])
    }

    /// An `if`/`else` swapping the view holding an object dropped the old
    /// branch's state, the object's box with it, so the new branch's view
    /// bound the object afresh and the draft's text was gone (review of
    /// 8de82a920).
    @Test("A class property whose holder an if/else swaps keeps its @State, and what the new holder writes")
    func holderSwappedByAConditionalKeepsTheState() {
        let tui = TUIContext()
        let taps = HolderTaps()
        let draft = Passed(object: Draft())
        let view = { (editing: Bool) in DraftScreen(editing: editing, draft: draft, taps: taps) }
        #expect(frame(view(true), tui, height: 1) == ["editor"])
        taps.texts["editor"]?.wrappedValue = "abc"
        #expect(frame(view(true), tui, height: 1) == ["editor abc"])
        #expect(frame(view(false), tui, height: 1) == ["summary abc"])
        taps.texts["summary"]?.wrappedValue = "abcd"
        #expect(frame(view(false), tui, height: 1) == ["summary abcd"])
        #expect(frame(view(true), tui, height: 1) == ["editor abcd"])
    }

    /// The row left was served from the memo in the pass the object's first
    /// holder was removed, so it walked nothing and took no claim; the first
    /// holder's state was dropped at the pass's end, and the row, next
    /// drawn, bound the object afresh, at its default (review of 8de82a920).
    /// What the row's binding wrote in between was lost with it.
    @Test("A class property whose first holder leaves while the other holder is served from the memo keeps its @State")
    func holderLeavingWhileTheOtherIsMemoServedKeepsTheState() {
        let tui = TUIContext()
        let taps = HolderTaps()
        let item = Passed(object: Item())
        let view = { (showsFirst: Bool, generation: Int) in
            TwoItemRows(showsFirst: showsFirst, generation: generation, item: item, taps: taps)
        }
        #expect(frame(view(true, 0), tui, height: 2) == ["a 0", "b 0"])
        taps.counts["a"]?.wrappedValue = 5
        #expect(frame(view(true, 1), tui, height: 2) == ["a 5", "b 5"])
        let served = tui.renderCache.rowWork.servedDrawing
        #expect(frame(view(false, 1), tui, height: 2).first == "b 5")
        #expect(tui.renderCache.rowWork.servedDrawing > served, "the row left is served from the memo")
        taps.counts["b"]?.wrappedValue = 7
        #expect(frame(view(false, 2), tui, height: 2).first == "b 7")
    }

    /// A view measured before the object's first holder had walked it in the
    /// pass read the object's contents as the first holder left them: a
    /// property set on the object since had an `@Environment(Model.self)`
    /// never handed an environment, and reading it trapped (review5 of
    /// DYNVFIX). Here the holder's identity changes as the property is set,
    /// so the stack measures it at its new identity while the first holder
    /// is the old one. Every holder walks the object before its body, and
    /// hands an `@Environment` with none its own. In an exit test, so that
    /// the trap fails this test alone.
    @Test("A view measured at a new identity reads an @Environment object in a property set on its object since")
    func holderMeasuredAtANewIdentityReadsTheModel() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let tests = DynamicPropertyObjectHolderTests()
                let tui = TUIContext()
                let screen = Passed(object: Screen())
                #expect(tests.frame(ReloadedScreen(screen: screen), tui, height: 2) == ["-", "load"])
                screen.object.child = ScreenChild()
                screen.object.generation += 1
                #expect(tests.frame(ReloadedScreen(screen: screen), tui, height: 2) == ["model", "load"])
            }
        }
    }

    /// The same for a second view showing the object, appearing above its
    /// first holder as the property is set: the stack measures it first.
    @Test("A view appearing above an object's first holder reads an @Environment object in a property set on it since")
    func holderAppearingAboveTheFirstHolderReadsTheModel() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let tests = DynamicPropertyObjectHolderTests()
                let tui = TUIContext()
                let screen = Passed(object: Screen())
                #expect(tests.frame(ModelScreenPair(showsB: false, screen: screen), tui, height: 2) == ["-"])
                screen.object.child = ScreenChild()
                #expect(tests.frame(ModelScreenPair(showsB: true, screen: screen), tui, height: 2) == ["model", "model"])
            }
        }
    }

    /// Without the trap: such a measure read the default for a key-path
    /// `@Environment`, so the view was measured under one environment and
    /// drawn under another. Under one environment, both holders read it.
    @Test("A view measured before its object's first holder walks it reads the environment in a property set since")
    func holderMeasuredBeforeTheFirstHolderReadsItsEnvironment() {
        let tui = TUIContext()
        let taps = HolderTaps()
        let screen = Passed(object: Screen())
        let view = { (showsB: Bool) in AccentScreenPair(showsB: showsB, screen: screen, taps: taps) }
        #expect(frame(view(false), tui, height: 2) == ["a -"])
        screen.object.child = ScreenChild()
        taps.reads.removeAll()
        #expect(frame(view(true), tui, height: 2) == ["b red", "a red"])
        #expect(taps.reads.contains("b red"))
        #expect(taps.reads.allSatisfy { $0.hasSuffix(" red") }, "read: \(taps.reads)")
    }
}
