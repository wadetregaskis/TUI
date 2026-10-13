//  🖥️ TUIkit — Terminal UI Kit for Swift
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

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

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
}
