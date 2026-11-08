//  🖥️ TUI — A Terminal UI framework for Swift
//  BodyChangeReport+Environment.swift
//
//  What `_printChanges()` keeps of a view's `@Environment` properties, and how
//  it compares one evaluation's with the last's.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension BodyChangeReport {
    /// How one input compares with what the last report saw.
    enum Change {
        /// It compares equal.
        case same
        /// It compares unequal.
        case changed
        /// It can't be compared: it may have changed.
        case unknown
    }

    /// A property that reads the environment, as `@Environment` does: what
    /// it reads in a given one.
    protocol EnvironmentReading {
        /// What the property reads in `environment`, or `nil` for nothing
        /// there (an absent optional object).
        func reportedValue(in environment: EnvironmentValues) -> Any?
    }

    /// What one `@Environment` property read, as kept for the next report.
    ///
    /// An object by identity, held weakly so the record keeps no model alive;
    /// an `Equatable` value as itself; anything else as uncomparable.
    enum Reading {
        /// Nothing: an optional object that was absent.
        case absent
        /// An object, by identity.
        case object(WeakReference, ObjectIdentifier)
        /// A value its own `==` compares.
        case value(any Equatable)
        /// A value that can't be compared: a closure, a style that is not
        /// `Equatable`.
        case uncomparable

        init(_ value: Any?) {
            guard let value = Self.unwrapped(value) else {
                self = .absent
                return
            }
            if type(of: value) is AnyClass {
                // `type(of:)` first: on Darwin any value converts to
                // `AnyObject`, boxed, so `as? AnyObject` says nothing.
                let object = value as AnyObject
                self = .object(WeakReference(object), ObjectIdentifier(object))
            } else if let equatable = value as? any Equatable {
                self = .value(equatable)
            } else {
                self = .uncomparable
            }
        }

        /// `value` with any `Optional` around it taken off: `nil` for none.
        private static func unwrapped(_ value: Any?) -> Any? {
            guard let value else { return nil }
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle == .optional else { return value }
            return unwrapped(mirror.children.first?.value)
        }
    }

    /// A weak reference to an object, for a ``Reading``.
    final class WeakReference {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    /// Each `@Environment` property among `subject`'s own fields, by its name
    /// (`_colorScheme`), with what it reads in `environment` — the environment
    /// its body was just evaluated in.
    static func environmentReadings<Subject>(
        of subject: Subject, in environment: EnvironmentValues
    ) -> [(name: String, value: Any?)] {
        Mirror(reflecting: subject).children.compactMap { child in
            guard let label = child.label, let property = child.value as? any EnvironmentReading else { return nil }
            return (label, property.reportedValue(in: environment))
        }
    }

    /// How `new` compares with `old`, what the last report kept: a property
    /// it kept nothing for is new, so changed.
    static func change(from old: Reading?, to new: Any?) -> Change {
        guard let old else { return .changed }
        switch (old, Reading(new)) {
        case (.absent, .absent):
            return .same
        case (.object(let reference, let id), .object(_, let newID)):
            // Equal only while the old object is alive: a freed address can
            // come back for another object.
            return reference.object != nil && id == newID ? .same : .changed
        case (.value(let left), .value(let right)):
            return equal(left, right) ? .same : .changed
        case (.uncomparable, _), (_, .uncomparable):
            return .unknown
        default:
            return .changed
        }
    }

    /// Whether two `Equatable` values are equal: unequal when their types
    /// differ.
    private static func equal(_ left: any Equatable, _ right: any Equatable) -> Bool {
        func opened<T: Equatable>(_ left: T) -> Bool { (right as? T).map { $0 == left } ?? false }
        return opened(left)
    }
}
