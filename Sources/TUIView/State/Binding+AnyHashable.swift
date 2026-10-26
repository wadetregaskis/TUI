//  🖥️ TUI — A Terminal UI framework for Swift
//  Binding+AnyHashable.swift
//
//  Handing a binding to a concrete `Hashable` value to code that takes one
//  type-erased to `AnyHashable`: a selection or a tag shared by values of
//  several types.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension Binding {
    /// Creates a binding by projecting the base value to a hashable value —
    /// mirrors SwiftUI's `Binding(_:)` with an `AnyHashable` value.
    ///
    /// A read wraps `base`'s value in `AnyHashable`; a write unwraps it and
    /// writes it to `base`, under `base`'s transaction where it has one.
    ///
    /// A write whose value is not a `V` has nowhere to go. SwiftUI traps on it
    /// (measured 2026-10-18: an `AnyHashable(Int8(7))` written through a
    /// projection of a `Binding<Int>` fails its cast). TUI reports it through
    /// `SoftTrap` — a debug build stops there too — and a release build drops
    /// the write, leaving `base` as it was (Deliberate deviations S7).
    ///
    /// - Parameter base: A `Hashable` value to project to an `AnyHashable` value.
    public init<V: Hashable>(_ base: Binding<V>) where Value == AnyHashable {
        self.init(
            get: { AnyHashable(base.wrappedValue) },
            set: { value in
                guard let unwrapped = value.base as? V else {
                    Self.reportMistypedWrite(value, expected: V.self)
                    return
                }
                base.wrappedValue = unwrapped
            })
    }

    /// The words a write of the wrong type through an `AnyHashable`
    /// projection is reported in.
    ///
    /// - Parameters:
    ///   - value: The value written.
    ///   - expected: The base binding's value type.
    ///   - report: Where the message goes: `SoftTrap`, or a test's own log.
    static func reportMistypedWrite<V>(
        _ value: AnyHashable, expected: V.Type, to report: (String) -> Void = { SoftTrap.report($0) }
    ) {
        report(
            "a \(type(of: value.base)) was written through Binding<AnyHashable>(_:), which projects a "
                + "Binding<\(V.self)>: the write is dropped and the binding keeps its value. Write a "
                + "\(V.self), or bind the selection to the type its tags carry.")
    }
}
