//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueHashOpeners.swift
//
//  The existentials of TUI's own protocols that views hold, opened
//  directly by the per-pass memos' value hash rather than by a cast.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

extension ValueHashPlans {
    /// A plan table that opens the existentials of TUI's own protocols a
    /// view holds directly (``tuikitOpeners``) — what an app's render caches
    /// are made with. Whoever makes one keeps it for every cache it makes: a
    /// plan is a fact about a type (see `RenderCache.valueHashPlans`).
    package static func tui() -> ValueHashPlans {
        ValueHashPlans(openers: tuikitOpeners)
    }

    /// One opener for each protocol of this module that a view stores as an
    /// existential: the style protocols, held by the environment modifier
    /// every `.buttonStyle(_:)`, `.menuStyle(_:)` … makes, and `AnyLayout`'s
    /// erased box.
    ///
    /// A static type the value hash cannot name is opened by a cast otherwise
    /// — a box for an `Any` and a dynamic cast, 2.2% of a `menus` frame, whose
    /// buttons each hold an `any ButtonStyle`. Each opener mixes the words the
    /// cast would have (`ValueHashOpenerTests` holds them to it), so a table
    /// without them hashes every value the same, only slower.
    package static var tuikitOpeners: [any ValueHashOpener.Type] {
        [
            ButtonStyleOpener.self,
            FormStyleOpener.self,
            GaugeStyleOpener.self,
            LabelStyleOpener.self,
            ListStyleOpener.self,
            MenuStyleOpener.self,
            NavigationSplitViewStyleOpener.self,
            PickerStyleOpener.self,
            TextFieldStyleOpener.self,
            ToggleStyleOpener.self,
            AnyLayout.ValueHashOpening.self,
        ]
    }
}

// Each opener loads the field as its existential and hands it to a generic
// function constrained to the protocol, which is what makes Swift open it.

private enum ButtonStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any ButtonStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: ButtonStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any ButtonStyle).self).pointee)
    }
}

private enum FormStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any FormStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: FormStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any FormStyle).self).pointee)
    }
}

private enum GaugeStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any GaugeStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: GaugeStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any GaugeStyle).self).pointee)
    }
}

private enum LabelStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any LabelStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: LabelStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any LabelStyle).self).pointee)
    }
}

private enum ListStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any ListStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: ListStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any ListStyle).self).pointee)
    }
}

private enum MenuStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any MenuStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: MenuStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any MenuStyle).self).pointee)
    }
}

private enum NavigationSplitViewStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any NavigationSplitViewStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: NavigationSplitViewStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any NavigationSplitViewStyle).self).pointee)
    }
}

private enum PickerStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any PickerStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: PickerStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any PickerStyle).self).pointee)
    }
}

private enum TextFieldStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any TextFieldStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: TextFieldStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any TextFieldStyle).self).pointee)
    }
}

private enum ToggleStyleOpener: ValueHashOpener {
    static var existential: Any.Type { (any ToggleStyle).self }

    static func mix(at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans) -> Bool {
        func open<Style: ToggleStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
        return unsafe open(pointer.assumingMemoryBound(to: (any ToggleStyle).self).pointee)
    }
}
