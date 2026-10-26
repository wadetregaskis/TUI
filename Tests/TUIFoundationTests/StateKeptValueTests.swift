//  🖥️ TUI — A Terminal UI framework for Swift
//  StateKeptValueTests.swift
//
//  A view value kept across frames — stored, not made anew by its parent's
//  body — whose place's state the storage has dropped: its place pruned, or
//  its enum case left. A `@State` binds its backing once and keeps it bound
//  while the storage keeps the box (decisions-DYNVFIX B-DYNVFIX-5); a backing
//  whose box was dropped is bound afresh, so the kept value reads its place's
//  state again — the new box, at its default, as SwiftUI resets a case it
//  leaves (`Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`, E1) — and allocates no backing
//  of its own on every body from then on. An `@Environment` box resolved for
//  a place no longer drawn is resolved where it lies again, the same way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// What the bodies hand out.
@MainActor
private final class KeptTap {
    var binding: Binding<Int>?
}

/// A view with a `@State` of its own, whose value hands out a binding from
/// itself, outside any body.
private struct KeptCounter: View {
    let tap: KeptTap
    @State private var count = 0

    /// The binding of this value — the one kept — not of a body's copy.
    var keptBinding: Binding<Int> { $count }

    var body: some View {
        tap.binding = $count
        return Text(verbatim: "count \(count)")
    }
}

/// An app property holding a `@State`, starting at 100.
private struct Tally: DynamicProperty {
    @State private var count = 100

    var value: Int { count }
    var binding: Binding<Int> { $count }
}

/// A view that is an `indirect` enum: its case's payload lies in a box every
/// copy shares, so the walk binds it on a copy the runtime makes.
private indirect enum IndirectScreen: View {
    case tally(Tally, KeptTap)
    case blank

    var body: some View {
        switch self {
        case let .tally(tally, tap):
            tap.binding = tally.binding
            return Text(verbatim: "tally \(tally.value)")
        case .blank:
            return Text(verbatim: "blank")
        }
    }
}

private struct KeptAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var keptAccent: String {
        get { self[KeptAccent.self] }
        set { self[KeptAccent.self] = newValue }
    }
}

/// A view reading an `@Environment`, whose value hands out a reader of it
/// from itself, outside any body.
private struct KeptReader: View {
    @Environment(\.keptAccent) private var accent

    /// A reader of this value's environment — the value kept — not of a
    /// body's copy.
    var keptRead: () -> String {
        let accent = _accent
        return { accent.wrappedValue }
    }

    var body: some View {
        Text(verbatim: "accent \(accent)")
    }
}

/// `reader` drawn in one place under one accent.
private struct FirstPlace: View {
    let reader: KeptReader

    var body: some View {
        VStack { reader }.environment(\.keptAccent, "red")
    }
}

/// `reader` drawn in another place, a different identity, under another.
private struct SecondPlace: View {
    let reader: KeptReader

    var body: some View {
        HStack { reader }.environment(\.keptAccent, "blue")
    }
}

@MainActor
@Suite("@State and @Environment in a view value kept across frames")
struct StateKeptValueTests {

    /// One frame as the render loop draws it: the pass begun, the view
    /// drawn, what was not drawn pruned.
    private func frame<V: View>(_ view: V, _ context: RenderContext) -> String {
        let storage = context.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context).lines.first?.stripped
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The walk bound the backing once and, when the box it was bound to
    /// was dropped, gave each body's copy a backing of its own (the copy of
    /// an `indirect` case's payload the runtime makes, which `body` never
    /// reads), so the kept value went on reading the dropped box: the case
    /// left and come back drew the old case's 7, not its default.
    @Test("A kept indirect enum view's case that comes back starts its @State at its default")
    func keptIndirectCaseComesBackAtDefault() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = KeptTap()
        let kept = IndirectScreen.tally(Tally(), tap)
        #expect(frame(kept, context) == "tally 100")
        tap.binding?.wrappedValue = 7
        #expect(frame(kept, context) == "tally 7")
        #expect(frame(IndirectScreen.blank, context) == "blank")
        #expect(frame(kept, context) == "tally 100", "the case left for another starts again at its default")
    }

    /// A kept value whose place was pruned and drawn again: its own backing
    /// is bound to the place's new box, so a binding made from the kept
    /// value writes the state its place draws. It stayed bound to the
    /// dropped box, and each body's copy was given a backing of its own.
    @Test("A kept view value drawn again after its place was pruned writes the state its place draws")
    func keptValueRebindsAfterPrune() {
        let context = makeRenderContext(width: 30, height: 1)
        let tap = KeptTap()
        let kept = KeptCounter(tap: tap)
        #expect(frame(kept, context) == "count 0")
        kept.keptBinding.wrappedValue = 3
        #expect(frame(kept, context) == "count 3")
        #expect(frame(Text(verbatim: "gone"), context) == "gone")
        #expect(frame(kept, context) == "count 0", "its place was pruned: it starts again at its default")
        kept.keptBinding.wrappedValue = 5
        #expect(frame(kept, context) == "count 5")
    }

    /// A kept value drawn at one place, then moved to another: its box,
    /// resolved for the first place, went on being found at another place
    /// every body, and each body's copy was given a box of its own, so the
    /// kept value's own reader read the first place's environment forever.
    /// The box is unplaced at the end of the first pass that does not draw
    /// the first place, and resolved where it lies from then on.
    @Test("A kept view value moved to another place reads that place's environment once the move has been drawn")
    func keptValueMovedResolvesInPlace() {
        let context = makeRenderContext(width: 30, height: 1)
        let kept = KeptReader()
        #expect(frame(FirstPlace(reader: kept), context) == "accent red")
        #expect(kept.keptRead() == "red")
        #expect(frame(SecondPlace(reader: kept), context) == "accent blue")
        #expect(frame(SecondPlace(reader: kept), context) == "accent blue")
        #expect(kept.keptRead() == "blue", "the first place is no longer drawn")
    }
}
