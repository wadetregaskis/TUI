//  🖥️ TUI — A Terminal UI framework for Swift
//  DynamicPropertyModifierTests.swift
//
//  Where the property walk updates a modifier's properties: only where the
//  modifier is applied — as the `modifier` of the `ModifiedContent` being
//  drawn — and once. A modifier stored anywhere else (a view's field,
//  `.transaction(_:)`'s wrapped modifier, a half of `.concat(_:)`) still has
//  its `@State` bound and its `@Environment` resolved, as TUI always did,
//  but nothing in it is updated: its copy was updated, and then the copy
//  applied from it was updated again (DYNV bug 5, session notes
//  DYNV/notes.md). SwiftUI updates the applied copy once (measured on macOS
//  15.8.1, SwiftUI 6.5.4: `Tools/SwiftUIProbes/Dynamic property discovery/op.out`, case vii-c2,
//  and `Tools/SwiftUIProbes/Dynamic property discovery/dv2-main.out`, `txn` and `concat`).
//  A modifier class is a property class wherever it is held, updated before
//  the body of each view holding it, as SwiftUI updates one held in a view's
//  field (`classmod.out`; decisions DYNVFIX, B-DYNVFIX-4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// An app property whose `update()` counts in a stored value of its own.
private struct CountingValue: DynamicProperty {
    var count = 0

    mutating func update() {
        count += 1
    }
}

/// A modifier holding an app property, showing what its `update()` left.
private struct ShowCount: ViewModifier {
    var counting = CountingValue()

    func body(content: Content) -> some View {
        HStack {
            content
            Text(verbatim: "count \(counting.count)")
        }
    }
}

/// Stores the modifier in a field and applies it.
private struct StoredAndApplied: View {
    let modifier: ShowCount

    var body: some View {
        Text(verbatim: "x").modifier(modifier)
    }
}

/// A modifier that hands its content on unchanged.
private struct PassThrough: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct ModifierAccent: EnvironmentKey {
    static let defaultValue = "plain"
}

extension EnvironmentValues {
    fileprivate var modifierAccent: String {
        get { self[ModifierAccent.self] }
        set { self[ModifierAccent.self] = newValue }
    }
}

/// A modifier reading the environment and keeping a `@State`.
private struct Tagging: ViewModifier {
    @Environment(\.modifierAccent) var accent
    @State private var taps = 0

    /// What the modifier's `@State` holds, and a binding to it.
    var tapCount: Int { taps }
    var tapsBinding: Binding<Int> { $taps }

    func body(content: Content) -> some View {
        content
    }
}

/// Stores the modifier, and reads what it holds in its own body.
private struct StoredReader: View {
    let tagging: Tagging
    let taps: TapBox

    var body: some View {
        taps.binding = tagging.tapsBinding
        return Text(verbatim: "\(tagging.accent) \(tagging.tapCount)")
    }
}

@MainActor
private final class TapBox {
    var binding: Binding<Int>?
}

// MARK: - A modifier class in a field

/// A plain class, not a property and not a modifier.
private class Decoration {}

/// A subclass of it that is a modifier and an app property, counting its
/// updates. `update()` is nonisolated, as `DynamicProperty` declares it: the
/// class is on the main actor as a modifier.
private final class CountingDecoration: Decoration, ViewModifier, DynamicProperty {
    nonisolated(unsafe) var updates = 0

    nonisolated func update() {
        updates += 1
    }

    func body(content: Content) -> some View {
        content
    }
}

/// A subclass of it that is an app property and not a modifier, counting
/// its updates: what a modifier class held in the same place is compared with.
private final class CountingProperty: Decoration, DynamicProperty {
    nonisolated(unsafe) var updates = 0

    nonisolated func update() {
        updates += 1
    }
}

/// Holds an object in a field declared as the plain class, and never applies
/// it.
private struct PlainFieldDecoration: View {
    let decoration: Decoration

    var body: some View {
        Text(verbatim: "x")
    }
}

/// Holds an object in a field declared as its own class, and never applies
/// it.
private struct StrongDecoration<Held: Decoration>: View {
    let decoration: Held

    var body: some View {
        Text(verbatim: "x")
    }
}

/// Holds an object `unowned`, and never applies it.
private struct UnownedDecoration<Held: Decoration>: View {
    unowned let decoration: Held

    var body: some View {
        Text(verbatim: "x")
    }
}

@MainActor
@Suite("DynamicProperty modifiers")
struct DynamicPropertyModifierTests {

    private func lines<V: View>(_ view: V, context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map {
            $0.stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    /// The walks descended into any `ViewModifier` value, so the view's own
    /// field was updated and written back before `body`, and then the copy
    /// `body` hands `.modifier(_:)` was updated again: the modifier's body
    /// read 2. SwiftUI gives a modifier stored in a view's field nothing, and
    /// updates only the copy in `ModifiedContent` (op.out, case vii-c2: the
    /// modifier's body reads count=1).
    @Test("A modifier stored in a view and applied runs its property's update() once per body, as SwiftUI does")
    func storedAndAppliedModifierUpdatesOnce() {
        let context = makeRenderContext(width: 20, height: 1)
        let direct = lines(Text(verbatim: "x").modifier(ShowCount()), context: context)
        #expect(direct.first?.hasSuffix("count 1") == true, "applied directly: \(direct)")
        let stored = lines(StoredAndApplied(modifier: ShowCount()), context: context)
        #expect(stored.first?.hasSuffix("count 1") == true, "stored and applied: \(stored)")
    }

    /// The same, through TUI's own API: `ViewModifier.transaction(_:)`
    /// (and `.animation(_:)`, built on it) returns a modifier that stores the
    /// one it wraps and applies it in its body, and `.concat(_:)` returns a
    /// `ModifiedContent` whose body applies its two halves. The walks updated
    /// the stored copy, then the applied one: the modifier's body read 2 in
    /// both. SwiftUI's body reads count=1 for both
    /// (`Tools/SwiftUIProbes/Dynamic property discovery/dv2-main.out`, `txn` and `concat`).
    @Test("A modifier wrapped by .transaction(_:) or joined by .concat(_:) runs its property's update() once per body")
    func wrappedOrJoinedModifierUpdatesOnce() {
        let context = makeRenderContext(width: 20, height: 1)
        let wrapped = lines(Text(verbatim: "x").modifier(ShowCount().transaction { _ in }), context: context)
        #expect(wrapped.first?.hasSuffix("count 1") == true, "wrapped by transaction: \(wrapped)")
        let animated = lines(Text(verbatim: "x").modifier(ShowCount().animation(nil)), context: context)
        #expect(animated.first?.hasSuffix("count 1") == true, "wrapped by animation: \(animated)")
        let joined = lines(Text(verbatim: "x").modifier(ShowCount().concat(PassThrough())), context: context)
        #expect(joined.first?.hasSuffix("count 1") == true, "joined by concat: \(joined)")
    }

    /// The reach TUI keeps beyond SwiftUI: a modifier stored in a view's
    /// field has its `@Environment` resolved and its `@State` bound, so the
    /// view's own body can read them.
    @Test("A modifier stored in a view's field still has its @Environment resolved and its @State kept")
    func storedModifierIsStillBound() {
        let context = makeRenderContext(width: 20, height: 1)
        let taps = TapBox()
        let view = { StoredReader(tagging: Tagging(), taps: taps).environment(\.modifierAccent, "red") }
        #expect(lines(view(), context: context) == ["red 0"])
        taps.binding?.wrappedValue = 4
        #expect(lines(view(), context: context) == ["red 4"])
    }

    /// A class that is both a modifier and a property, held in a view's field
    /// and never applied, is a property class there: its `update()` runs
    /// before the view's body, as often as a property class's held the same
    /// way. SwiftUI runs it once per body, held in a field declared as its
    /// class (`Tools/SwiftUIProbes/Dynamic property discovery/classmod.out`;
    /// it traps if such a class is applied). It ran never here, being taken
    /// for a stored modifier (decisions DYNVFIX, B-DYNVFIX-4).
    @Test("A modifier class held in a view's field is updated before its body, as a property class held there is")
    func storedModifierClassIsUpdatedAsAPropertyClass() {
        let context = makeRenderContext(width: 20, height: 1)
        var modifier = CountingDecoration()
        var property = CountingProperty()
        for _ in 0..<2 {
            _ = lines(StrongDecoration(decoration: modifier), context: context)
            _ = lines(StrongDecoration(decoration: property), context: context)
        }
        #expect(modifier.updates > 0 && modifier.updates == property.updates, "in a field of its own class")

        (modifier, property) = (CountingDecoration(), CountingProperty())
        for _ in 0..<2 {
            _ = lines(PlainFieldDecoration(decoration: modifier), context: context)
            _ = lines(PlainFieldDecoration(decoration: property), context: context)
        }
        #expect(modifier.updates > 0 && modifier.updates == property.updates, "behind a plain class field")

        (modifier, property) = (CountingDecoration(), CountingProperty())
        for _ in 0..<2 {
            _ = lines(UnownedDecoration(decoration: modifier), context: context)
            _ = lines(UnownedDecoration(decoration: property), context: context)
        }
        #expect(modifier.updates > 0 && modifier.updates == property.updates, "held unowned")
    }
}
