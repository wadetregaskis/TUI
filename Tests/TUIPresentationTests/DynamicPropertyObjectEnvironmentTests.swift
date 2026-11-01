//  🖥️ TUI — A Terminal UI framework for Swift
//  DynamicPropertyObjectEnvironmentTests.swift
//
//  A class property's `@Environment` is each holder's while it draws: every
//  walk resolves it to the walking view's environment, and what a walk other
//  than the first holder's handed it is put back after that view's content,
//  so the body and everything it built read their own view's; at rest, the
//  first holder's (decisions-DYNVFIX B-DYNVFIX-3, lane DYNVCLAIM). SwiftUI
//  resolves none (measured: `Tools/SwiftUIProbes/Class properties held by
//  several views/cls.out`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

private struct ObjectAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var objectAccent: String {
        get { self[ObjectAccent.self] }
        set { self[ObjectAccent.self] = newValue }
    }
}

/// What each body read and handed out, by the name of the view.
@MainActor
private final class AccentTaps {
    var reads: [String: [String]] = [:]
    var readers: [String: () -> String] = [:]
}

/// A class app property holding an `@Environment`.
private final class Accented: DynamicProperty {
    @Environment(\.objectAccent) var accent
}

/// A class property passed through a view that does not hold it as one.
private struct Passed<Object: AnyObject> {
    let object: Object
}

/// A view showing the object's accent, noting each read — a measure's and a
/// draw's — and handing out a closure that reads it later.
private struct AccentView: View {
    let name: String
    let object: Accented
    let taps: AccentTaps

    var body: some View {
        let object = object
        taps.reads[name, default: []].append(object.accent)
        taps.readers[name] = { object.accent }
        return Text(verbatim: "\(name) \(object.accent)")
    }
}

/// One object shown by two views under two environments.
private struct TwoAccents: View {
    let first: String
    let second: String
    let object: Passed<Accented>
    let taps: AccentTaps

    var body: some View {
        VStack {
            AccentView(name: "a", object: object.object, taps: taps).environment(\.objectAccent, first)
            AccentView(name: "b", object: object.object, taps: taps).environment(\.objectAccent, second)
        }
    }
}

/// `TwoAccents`, the second view above the first and drawn only when
/// `showsSecond`: the stack measures it first.
private struct SecondAbove: View {
    let showsSecond: Bool
    let first: String
    let second: String
    let object: Passed<Accented>
    let taps: AccentTaps

    var body: some View {
        VStack {
            if showsSecond {
                AccentView(name: "b", object: object.object, taps: taps).environment(\.objectAccent, second)
            }
            AccentView(name: "a", object: object.object, taps: taps).environment(\.objectAccent, first)
        }
    }
}

/// A view holding the object, whose content holds it again under another
/// environment and then reads it in a row drawn after that.
private struct OuterHolder: View {
    let object: Accented
    let taps: AccentTaps

    var body: some View {
        let object = object
        return VStack {
            AccentView(name: "inner", object: object, taps: taps).environment(\.objectAccent, "inner")
            ForEach(0..<1, id: \.self) { _ in
                RowReader(object: Passed(object: object), taps: taps)
            }
        }
    }
}

/// A row of the outer holder's content, which does not hold the object as a
/// property — `Passed` is not one, and is not looked into — so it reads it as
/// the outer holder's content does.
private struct RowReader: View {
    var name = "row"
    /// A value new each frame, so the row is drawn again rather than served
    /// from the memo: what it reads of the object is not in its value.
    var frame = 0
    let object: Passed<Accented>
    let taps: AccentTaps

    var body: some View {
        let accent = object.object.accent
        taps.reads[name, default: []].append(accent)
        return Text(verbatim: "\(name) \(accent)")
    }
}

/// The outer holder under one environment, below a view that holds the
/// object under another: the first holder, so the outer holder's walk is
/// not the object's first holder's.
private struct NestedHolders: View {
    let object: Passed<Accented>
    let taps: AccentTaps

    var body: some View {
        VStack {
            AccentView(name: "first", object: object.object, taps: taps).environment(\.objectAccent, "first")
            OuterHolder(object: object.object, taps: taps).environment(\.objectAccent, "outer")
        }
    }
}

/// A view holding the object in a field when `held` is it, whose content —
/// `content`, then a row drawn anew each frame (not one a `ForEach` serves
/// from its row memo, blind to what its closure captures) — reads it: the
/// row after `content` reads this view's environment when it holds the
/// object.
private struct HoldingLevel<Content: View>: View {
    let name: String
    let frame: Int
    let held: Accented?
    let object: Passed<Accented>
    let taps: AccentTaps
    let content: Content

    var body: some View {
        VStack {
            content
            RowReader(name: name, frame: frame, object: object, taps: taps)
        }
    }
}

/// A class app property holding a `@FocusState`, whose manager — what the
/// walk resolves from the environment — it tells.
private final class FocusHolder: DynamicProperty {
    @FocusState var focused: Bool

    var manager: FocusManager? { _focused.store.environmentManager }
}

/// A view holding a `FocusHolder`.
private struct FocusHolderView: View {
    let name: String
    let holder: FocusHolder

    var body: some View {
        Text(verbatim: name)
    }
}

/// One `FocusHolder` shown by two views under two focus managers: the
/// second's, a backdrop's, drawn after the first's.
private struct TwoFocusManagers: View {
    let holder: Passed<FocusHolder>
    let live: FocusManager
    let backdrop: FocusManager

    var body: some View {
        VStack {
            FocusHolderView(name: "live", holder: holder.object).environment(\.focusManager, live)
            FocusHolderView(name: "backdrop", holder: holder.object).environment(\.focusManager, backdrop)
        }
    }
}

/// A page holding a `FocusHolder` under the live focus manager, presenting a
/// sheet that holds it too: the page is drawn first, as the sheet's backdrop,
/// under that backdrop's focus manager, which focuses nothing.
private struct FocusHolderSheet: View {
    let holder: Passed<FocusHolder>
    let live: FocusManager

    var body: some View {
        FocusHolderView(name: "page", holder: holder.object)
            .sheet(isPresented: .constant(true)) {
                FocusHolderView(name: "sheet", holder: holder.object)
            }
            .environment(\.focusManager, live)
    }
}

private struct InspectedNoteKey: FocusedValueKey {
    typealias Value = String
}

private struct InspectedCountKey: FocusedValueKey {
    typealias Value = Binding<Int>
}

extension FocusedValues {
    fileprivate var inspectedNote: String? {
        get { self[InspectedNoteKey.self] }
        set { self[InspectedNoteKey.self] = newValue }
    }

    fileprivate var inspectedCount: Binding<Int>? {
        get { self[InspectedCountKey.self] }
        set { self[InspectedCountKey.self] = newValue }
    }
}

/// A class app property holding a `@FocusedValue`: an inspector of what the
/// focused control publishes.
private final class NoteInspector: DynamicProperty {
    @FocusedValue(\.inspectedNote) var note
}

/// A class app property holding a `@FocusedBinding`.
private final class CountInspector: DynamicProperty {
    @FocusedBinding(\.inspectedCount) var count
}

/// A line showing what a `NoteInspector` reads. Any two compare equal, so a
/// memo above one serves it unless told that its body reads what the memo
/// does not see.
private struct NoteLine: View, @preconcurrency Equatable {
    let name: String
    let inspector: NoteInspector

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Text(verbatim: "\(name) \(inspector.note ?? "none")")
    }
}

/// A line showing what a `CountInspector` reads.
private struct CountLine: View {
    let name: String
    let inspector: CountInspector

    var body: some View {
        Text(verbatim: "\(name) \(inspector.count.map(String.init) ?? "none")")
    }
}

/// A page showing an object on its first line, the object's primary holder,
/// and again in a row with no focus stop that a `ForEach` memoises by its
/// element, above two buttons publishing what the object reads.
private struct RowBesidePrimary<Line: View, Published>: View {
    let line: (String) -> Line
    let key: WritableKeyPath<FocusedValues, Published?>
    let published: (a: Published, b: Published)

    var body: some View {
        VStack {
            line("page")
            ForEach([1], id: \.self) { _ in line("row") }
            Button("A") {}.focusedValue(key, published.a)
            Button("B") {}.focusedValue(key, published.b)
        }
    }
}

/// A page showing a `NoteInspector` behind a memo, presenting a sheet that
/// shows it too above two buttons publishing what it reads: the page is drawn
/// first, as the sheet's backdrop, so it is the object's primary holder.
private struct NoteInspectorUnderSheetApp: App {
    let inspector: Passed<NoteInspector>

    init() { inspector = Passed(object: NoteInspector()) }

    var body: some Scene {
        WindowGroup {
            VStack {
                NoteLine(name: "page", inspector: inspector.object).equatable()
                Spacer()
            }
            .sheet(isPresented: .constant(true)) {
                VStack {
                    NoteLine(name: "sheet", inspector: inspector.object)
                    Button("A") {}.focusedValue(\.inspectedNote, "a")
                    Button("B") {}.focusedValue(\.inspectedNote, "b")
                }
            }
        }
    }
}

@MainActor
@Suite("DynamicProperty objects' environment")
struct DynamicPropertyObjectEnvironmentTests {

    /// One frame as the render loop draws it: invalidations drained, the pass
    /// begun, the view made and drawn in it (`StateStorage.inRenderPass(_:)`),
    /// what was not drawn pruned.
    private func frame<V: View>(_ view: @autoclosure () -> V, _ tui: TUIContext, height: Int = 2) -> [String] {
        let context = RenderContext(availableWidth: 30, availableHeight: height, tuiContext: tui)
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

    /// Both holders read the first holder's environment in their bodies: the
    /// claim's rule, B-DYNVFIX-3's stated price. Each body reads its own
    /// view's now; closures, run after every holder has drawn, read the
    /// first holder's.
    @Test("Two views showing one class property under two environments each draw their own")
    func holdersUnderTwoEnvironmentsEachDrawTheirOwn() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { TwoAccents(first: "red", second: "blue", object: object, taps: taps) }
        #expect(frame(view(), tui) == ["a red", "b blue"])
        #expect(frame(view(), tui) == ["a red", "b blue"])
        #expect(taps.readers["a"]?() == "red")
        #expect(taps.readers["b"]?() == "red", "a closure reads the first holder's")
    }

    /// A view drawn above the object's first holder read the first holder's
    /// environment — its last walk's, or this pass's when the first holder
    /// was measured between the view's measure and its draw — whatever its
    /// own (review4 of DYNVFIX, deac1c31f(2); review5 S1's milder form).
    /// Every read of its body, measured and drawn, is its own.
    @Test("A view drawn above an object's first holder reads its own environment, measured and drawn")
    func holderDrawnBeforeAnotherReadsItsOwnNewEnvironment() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { (showsSecond: Bool, first: String) in
            SecondAbove(showsSecond: showsSecond, first: first, second: "green", object: object, taps: taps)
        }
        #expect(frame(view(false, "red"), tui) == ["a red"])
        taps.reads.removeAll()
        #expect(frame(view(true, "blue"), tui) == ["b green", "a blue"])
        #expect(taps.reads["b"]?.isEmpty == false)
        #expect(taps.reads["b"]?.allSatisfy { $0 == "green" } == true, "b read: \(taps.reads["b"] ?? [])")
        #expect(taps.reads["a"]?.allSatisfy { $0 == "blue" } == true, "a read: \(taps.reads["a"] ?? [])")
    }

    /// A holder measured before the first holder walks the object in the
    /// pass, and drawn after, read the first holder's last environment in its
    /// measure and its new one in its draw (review5 of DYNVFIX, S1's milder
    /// form): what it is measured with is what it draws.
    @Test("A view holding a class property is measured with the environment it is drawn with")
    func objectEnvironmentMeasuredAsDrawn() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { (showsSecond: Bool, first: String) in
            SecondAbove(showsSecond: showsSecond, first: first, second: "green", object: object, taps: taps)
        }
        _ = frame(view(false, "red"), tui)
        taps.reads.removeAll()
        _ = frame(view(true, "blue"), tui)
        let reads = taps.reads["b"] ?? []
        #expect(reads.count >= 2, "measured and drawn: \(reads)")
        #expect(Set(reads).count == 1, "measured and drawn alike: \(reads)")
    }

    /// Bodies a holder's content evaluates after a holder nested in that
    /// content — a row drawn after it — read the outer holder's environment:
    /// what the inner holder's walk handed the object is put back after the
    /// inner holder's content.
    @Test("A holder's content read after an inner holder of the same object reads the outer holder's environment")
    func outerHoldersContentReadsItsOwnEnvironmentAfterAnInnerHolder() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { NestedHolders(object: object, taps: taps) }
        #expect(frame(view(), tui, height: 3) == ["first first", "inner inner", "row outer"])
        #expect(frame(view(), tui, height: 3) == ["first first", "inner inner", "row outer"])
        #expect(taps.reads["row"]?.allSatisfy { $0 == "outer" } == true, "\(taps.reads["row"] ?? [])")
        #expect(taps.readers["first"]?() == "first", "at rest, the first holder's")
    }

    /// The first holder of the object, drawn first while the view around it
    /// held nothing, is its primary; once the outer view holds it too, the
    /// primary's walk, nested in the outer one's content, handed the object
    /// its environment and noted nothing to put back, so the outer view's
    /// row after it read the inner one's (review1 of lane DYNVCLAIM,
    /// a36532985 (1)). The outer view's content reads the outer view's after
    /// the inner one's; at rest, the primary's.
    @Test("A holder's content read after its object's primary holder, nested in it, reads the outer holder's environment")
    func outerHoldersContentReadsItsOwnEnvironmentAfterTheNestedPrimary() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { (holds: Bool, frame: Int) in
            HoldingLevel(
                name: "row", frame: frame, held: holds ? object.object : nil, object: object, taps: taps,
                content: AccentView(name: "inner", object: object.object, taps: taps)
                    .environment(\.objectAccent, "inner")
            )
            .environment(\.objectAccent, "outer")
        }
        #expect(frame(view(false, 1), tui) == ["inner inner", "row inner"])
        #expect(frame(view(true, 2), tui) == ["inner inner", "row outer"])
        #expect(frame(view(true, 3), tui) == ["inner inner", "row outer"])
        #expect(taps.readers["inner"]?() == "inner", "at rest, the primary's")
    }

    /// Two holders around the primary: each one's content after what it
    /// nests reads its own environment — the middle one's put back after the
    /// primary's content, the outermost one's after the middle one's — and
    /// at rest the object reads the primary's.
    @Test("Holders nested around their object's primary each read their own environment after what they nest")
    func holdersNestedAroundThePrimaryEachReadTheirOwnAfterIt() {
        let tui = TUIContext()
        let taps = AccentTaps()
        let object = Passed(object: Accented())
        let view = { (holds: Bool, frame: Int) in
            HoldingLevel(
                name: "row1", frame: frame, held: holds ? object.object : nil, object: object, taps: taps,
                content: HoldingLevel(
                    name: "row2", frame: frame, held: holds ? object.object : nil, object: object, taps: taps,
                    content: AccentView(name: "inner", object: object.object, taps: taps)
                        .environment(\.objectAccent, "inner")
                )
                .environment(\.objectAccent, "middle")
            )
            .environment(\.objectAccent, "outer")
        }
        #expect(frame(view(false, 1), tui, height: 3) == ["inner inner", "row2 inner", "row1 inner"])
        #expect(frame(view(true, 2), tui, height: 3) == ["inner inner", "row2 middle", "row1 outer"])
        #expect(frame(view(true, 3), tui, height: 3) == ["inner inner", "row2 middle", "row1 outer"])
        #expect(taps.readers["inner"]?() == "inner", "at rest, the primary's")
    }

    /// The object's environment at rest was kept on its hub, which the
    /// storage keeps: the environment holds the storage, so a storage that
    /// had drawn a class property never went (review1 of lane DYNVCLAIM,
    /// a36532985 (4)). It goes with its context.
    @Test("A state storage that drew a class property goes with its context")
    func storageThatDrewAnObjectGoesWithItsContext() {
        weak var storage: StateStorage?
        do {
            let tui = TUIContext()
            storage = tui.stateStorage
            let taps = AccentTaps()
            let object = Passed(object: Accented())
            #expect(frame(TwoAccents(first: "red", second: "blue", object: object, taps: taps), tui) == ["a red", "b blue"])
        }
        #expect(storage == nil)
    }

    /// The managers of the `@FocusState`s inside an object — what a property
    /// that is not an `@Environment` takes from the environment — were taken
    /// by every walk, and none put back: the last holder drawn, a backdrop
    /// holding the page's object, won, and a focus set from a closure went to
    /// the backdrop's manager, which focuses nothing (review1 of lane
    /// DYNVCLAIM, a36532985 (2)). The object's primary holder's walk takes
    /// them, or any walk before it has one.
    @Test("A class property's @FocusState takes its first holder's focus manager, not a later holder's")
    func objectFocusStateTakesItsPrimarysManager() {
        let tui = TUIContext()
        let live = FocusManager()
        let backdrop = FocusManager()
        let holder = Passed(object: FocusHolder())
        let view = { TwoFocusManagers(holder: holder, live: live, backdrop: backdrop) }
        #expect(frame(view(), tui) == ["live", "backdrop"])
        #expect(holder.object.manager === live)
        #expect(frame(view(), tui) == ["live", "backdrop"])
        #expect(holder.object.manager === live)
    }

    /// A modal draws the page beneath it first, as a backdrop under a focus
    /// manager of its own that focuses nothing and dies with the frame, at
    /// the page's identity: the page is the object's primary holder. Taken
    /// from the primary alone, the object's `@FocusState` took the backdrop's
    /// manager while the sheet was up, and a focus set from the sheet's
    /// action went nowhere (review2 of lane DYNVCLAIM, 748e897b2). No walk
    /// under a backdrop hands them in, and a live holder does while the
    /// primary draws as one.
    @Test("A class property's @FocusState takes a live holder's focus manager while its first holder is a sheet's backdrop")
    func objectFocusStateTakesALiveManagerWhileItsPrimaryIsABackdrop() {
        let tui = TUIContext()
        let live = FocusManager()
        let holder = Passed(object: FocusHolder())
        _ = frame(FocusHolderSheet(holder: holder, live: live), tui, height: 10)
        #expect(holder.object.manager === live)
        _ = frame(FocusHolderSheet(holder: holder, live: live), tui, height: 10)
        #expect(holder.object.manager === live)
    }

    /// The first two lines of `buffer`, as they read.
    private func firstTwo(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.prefix(2).map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Resolving an object's `@FocusedValue` tells the memos above the holder
    /// that what its body reads follows the focus. A walk that does not hand
    /// it the environment — another holder's than the primary's — told them
    /// nothing, so a row memoised by its element stored what it drew and
    /// served it after the focus moved (review of 75c2c226c, S3).
    @Test("A memoised row showing an object's @FocusedValue, not the object's primary holder, follows the focus")
    func rowShowingAnObjectsFocusedValueFollowsTheFocus() {
        let harness = InputChainHarness()
        let inspector = NoteInspector()
        let page = {
            RowBesidePrimary(
                line: { NoteLine(name: $0, inspector: inspector) }, key: \.inspectedNote, published: ("a", "b"))
        }
        harness.frame(page())
        #expect(firstTwo(harness.frame(page())) == ["page a", "row a"])
        harness.press(KeyEvent(key: .tab))
        #expect(firstTwo(harness.frame(page())) == ["page b", "row b"])
    }

    /// The same for a `@FocusedBinding`, which reads through the same link.
    @Test("A memoised row showing an object's @FocusedBinding, not the object's primary holder, follows the focus")
    func rowShowingAnObjectsFocusedBindingFollowsTheFocus() {
        let harness = InputChainHarness()
        let inspector = CountInspector()
        let page = {
            RowBesidePrimary(
                line: { CountLine(name: $0, inspector: inspector) }, key: \.inspectedCount,
                published: (.constant(1), .constant(2)))
        }
        harness.frame(page())
        #expect(firstTwo(harness.frame(page())) == ["page 1", "row 1"])
        harness.press(KeyEvent(key: .tab))
        #expect(firstTwo(harness.frame(page())) == ["page 2", "row 2"])
    }

    /// No walk drawn as a backdrop hands an object's `@FocusedValue` the
    /// environment, so the page behind a sheet told the memo above its holder
    /// nothing: the dimmed page kept the value it first drew while the focus
    /// moved in the sheet (review of 75c2c226c, S3).
    @Test("A page behind a sheet showing an object's @FocusedValue follows the focus in the sheet")
    func pageBehindASheetShowingAnObjectsFocusedValueFollowsTheFocus() {
        let app = TestApp(NoteInspectorUnderSheetApp(), width: 40, height: 16)
        func shows(_ text: String) -> Bool { app.screen.contains(text) }
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        #expect(shows("page a"), "\(app.screen.lines)")
        #expect(shows("sheet a"))
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 33_333_334)
        #expect(shows("page b"), "\(app.screen.lines)")
        #expect(shows("sheet b"))
    }
}
