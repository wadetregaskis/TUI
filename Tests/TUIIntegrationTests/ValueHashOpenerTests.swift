//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueHashOpenerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport
@testable import TUIView

/// A value holding one existential, as a view's environment modifier holds a
/// style: the existential is the field the plan steps through.
private struct Holds<Existential> {
    let value: Existential
    let tail: UInt8
}

/// An opener is an optimisation and nothing else: a table given one opens an
/// existential of its static type directly, where a table without one opens it
/// by a cast, and the two must mix the same words — or a value would hash one
/// way under an app's caches and another under a bare one's.
@MainActor
@Suite("An existential's opener mixes what the cast would")
struct ValueHashOpenerTests {
    private let opened = ValueHashPlans.tui()
    private let cast = ValueHashPlans()

    private func hash<V>(_ value: V, _ plans: ValueHashPlans) -> Int? {
        withUnsafePointer(to: value) { unsafe plans.valueHash(at: $0) }
    }

    /// Checks `value` both ways, and returns the static type it checked.
    @discardableResult
    private func check<Existential>(
        _ value: Existential, sourceLocation: SourceLocation = #_sourceLocation
    ) -> ObjectIdentifier {
        let holder = Holds(value: value, tail: 7)
        let viaOpener = hash(holder, opened)
        #expect(viaOpener != nil, sourceLocation: sourceLocation)
        #expect(viaOpener == hash(holder, cast), sourceLocation: sourceLocation)
        #expect(
            opened.plan(for: Holds<Existential>.self).stepDescriptions
                == ["0: existential opened by \(Existential.self)"], sourceLocation: sourceLocation)
        #expect(
            cast.plan(for: Holds<Existential>.self).stepDescriptions
                == ["0: existential cast from \(Existential.self)"], sourceLocation: sourceLocation)
        return ObjectIdentifier(Existential.self)
    }

    @Test("Every opener TUI registers mixes the words the cast mixes, and each is checked here")
    func everyOpener() {
        var checked: Set<ObjectIdentifier> = [
            check(_AppearanceButtonStyle.automatic as any ButtonStyle),
            check(AutomaticFormStyle() as any FormStyle),
            check(DefaultGaugeStyle() as any GaugeStyle),
            check(DefaultLabelStyle() as any LabelStyle),
            check(InsetGroupedListStyle() as any ListStyle),
            check(DefaultMenuStyle() as any MenuStyle),
            check(AutomaticNavigationSplitViewStyle() as any NavigationSplitViewStyle),
            check(DefaultPickerStyle() as any PickerStyle),
            check(DefaultTextFieldStyle() as any TextFieldStyle),
            check(DefaultToggleStyle() as any ToggleStyle),
        ]
        // `AnyLayout`'s box is of a protocol private to its file, so it is
        // checked through the layout that holds it.
        let layout = AnyLayout(HStackLayout())
        #expect(hash(layout, opened) != nil)
        #expect(hash(layout, opened) == hash(layout, cast))
        let boxType = ValueHashPlans.tuikitOpeners.first { "\($0.existential)" == "AnyLayoutBox" }?.existential
        // Out of `#expect`: see CONTRIBUTING, "Testing".
        let foundBox = boxType != nil
        #expect(foundBox)
        if let boxType { checked.insert(ObjectIdentifier(boxType)) }
        #expect(opened.plan(for: AnyLayout.self).stepDescriptions == ["0: existential opened by AnyLayoutBox"])
        // A new opener fails here until it is checked above.
        let openers = Set(ValueHashPlans.tuikitOpeners.map { ObjectIdentifier($0.existential) })
        #expect(openers == checked)
    }

    @Test("Different payloads behind one opener hash apart")
    func differentPayloads() {
        #expect(
            hash(Holds(value: DefaultMenuStyle() as any MenuStyle, tail: 0), opened)
                != hash(Holds(value: InlineMenuStyle() as any MenuStyle, tail: 0), opened))
        #expect(
            hash(Holds(value: _AppearanceButtonStyle.automatic as any ButtonStyle, tail: 0), opened)
                != hash(Holds(value: _AppearanceButtonStyle.plain as any ButtonStyle, tail: 0), opened))
        #expect(hash(AnyLayout(HStackLayout()), opened) != hash(AnyLayout(VStackLayout()), opened))
    }

    /// A palette is opened directly by every table — the value hash's own
    /// module can name the protocol — and must mix what the cast would.
    @Test("A palette is opened directly by every table, as the cast would open it")
    func palette() {
        let holder = Holds(value: SystemPalette(.green) as any Palette, tail: 3)
        #expect(cast.plan(for: Holds<any Palette>.self).stepDescriptions == ["0: existential palette"])
        var direct = hashFoldSeed
        var viaCast = hashFoldSeed
        withUnsafePointer(to: holder.value) { pointer in
            unsafe #expect(ExistentialField.palette.mix(at: pointer, into: &direct, plans: cast))
            unsafe #expect(ExistentialField.other((any Palette).self).mix(at: pointer, into: &viaCast, plans: cast))
        }
        #expect(direct == viaCast)
        #expect(hash(holder, cast) != hash(Holds(value: SystemPalette(.amber) as any Palette, tail: 3), cast))
    }
}
