//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusedValue.swift
//
//  `@FocusedValue` and `@FocusedBinding`: reading what the focused view, or
//  one of its ancestors, published.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkitCore
import TUIkitView

// MARK: - The reader's link

/// What a focused-value property wrapper reads through: the focus manager of
/// the environment its view renders in, handed over by the same reflection
/// pass that fills the `@Environment` boxes.
///
/// A reference, so the copy of the wrapper an event closure captured reads
/// the manager the render found.
final class FocusedValueReader {
    weak var focusManager: FocusManager?

    /// The values published for wherever the focus is now, or an empty table
    /// outside any render's environment.
    var table: FocusedValues {
        guard let manager = focusManager else { return FocusedValues() }
        return manager.focusedValues.table(focusedAt: manager.focusedIdentity)
    }

    /// Takes the environment the view renders in, and tells any memo above
    /// the view that what its body reads is keyed by nothing the memo sees.
    func resolve(_ environment: EnvironmentValues) {
        focusManager = environment.focusManager
        Self.noteRead(in: environment)
    }

    /// Tells any memo above the view drawn in `environment` that what its body
    /// reads is keyed by nothing the memo sees: what resolving does, and what
    /// a walk that hands an object's reader nothing does alone
    /// (`UnkeyedEnvironmentReader`).
    static func noteRead(in environment: EnvironmentValues) {
        // The value follows the focus and other views' publishing — neither
        // of which is part of this view's value or its environment — so a
        // buffer cached around the reader would show a stale value.
        environment.volatileReadTracker?.recordUnkeyedRead()
    }
}

// MARK: - @FocusedValue

/// A property wrapper for observing values from the focused view or one of
/// its ancestors. Mirrors SwiftUI's `@FocusedValue`.
///
/// ```swift
/// struct NoteDetail: View {
///     @FocusedValue(\.selectedNote) private var note
///
///     var body: some View {
///         Text(note?.wrappedValue.title ?? "Nothing selected")
///     }
/// }
/// ```
///
/// If several views publish a value under the same key, the one closest to
/// the focus wins: the deepest publisher on the focus's path, and failing any
/// there, the first scene value (`focusedSceneValue(_:_:)`) in
/// the tree. With nothing published it reads `nil`.
///
/// A reader usually sits beside what it reads — a detail pane, a status line —
/// rather than above it, and may draw before the view that publishes. It then
/// reads what was published last frame, and if that turns out to have changed
/// by the end of this one, one more frame draws the new value. A value that
/// cannot be compared (a closure, a `Binding`) is not checked that way; a
/// `Binding` reads through to its source wherever it is read, and a closure is
/// called when its moment comes, so neither shows a stale state.
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    private let reader = FocusedValueReader()
    private let read: (FocusedValues) -> Value?

    /// A new property wrapper for the given key path.
    ///
    /// - Parameter keyPath: The key path for the focus value to read.
    public init(_ keyPath: KeyPath<FocusedValues, Value?>) {
        read = { $0[keyPath: keyPath] }
    }

    /// A new property wrapper for the `@Observable` object of `objectType`
    /// published with ``View/focusedValue(_:)``.
    ///
    /// - Parameter objectType: The type of the object to read.
    public init(_ objectType: Value.Type) where Value: AnyObject, Value: Observable {
        read = { $0[FocusedObjectKey<Value>.self] }
    }

    /// The value for the focus key given the current scope and state of the
    /// focused view hierarchy, or `nil` where none is published.
    public var wrappedValue: Value? {
        read(reader.table)
    }
}

extension FocusedValue: EnvironmentResolvable {
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        reader.resolve(environment)
    }
}

// MARK: - @FocusedBinding

/// A property wrapper for observing and automatically unwrapping state
/// bindings from the focused view or one of its ancestors. Mirrors SwiftUI's
/// `@FocusedBinding`.
///
/// ```swift
/// struct Inspector: View {
///     @FocusedBinding(\.selectedNote) private var note
///
///     var body: some View {
///         if let note {
///             Text(note.title)
///         }
///     }
/// }
/// ```
///
/// Setting the property writes through the published binding; setting it to
/// `nil`, or with nothing published, does nothing. Which binding is read
/// follows the same rule as ``FocusedValue``.
@propertyWrapper
public struct FocusedBinding<Value>: DynamicProperty {
    private let reader = FocusedValueReader()
    private let keyPath: KeyPath<FocusedValues, Binding<Value>?>

    /// A new property wrapper for the given key path.
    ///
    /// - Parameter keyPath: The key path for the focus value to read.
    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) {
        self.keyPath = keyPath
    }

    /// The published binding, if there is one.
    private var binding: Binding<Value>? {
        reader.table[keyPath: keyPath]
    }

    /// The unwrapped value for the focus key given the current scope and state
    /// of the focused view hierarchy.
    public var wrappedValue: Value? {
        get { binding?.wrappedValue }
        nonmutating set {
            guard let newValue, let binding else { return }
            binding.wrappedValue = newValue
        }
    }

    /// A binding to the optional value.
    ///
    /// The unwrapped value is `nil` when no focused view hierarchy has
    /// published a corresponding binding.
    public var projectedValue: Binding<Value?> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

extension FocusedBinding: EnvironmentResolvable {
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        reader.resolve(environment)
    }
}

// Inside an object, a walk that hands either nothing still tells the memos
// above its view that the view reads it. See `UnkeyedEnvironmentReader`.
extension FocusedValue: UnkeyedEnvironmentReader {
    package static func noteUnkeyedRead(in environment: EnvironmentValues) {
        FocusedValueReader.noteRead(in: environment)
    }
}

extension FocusedBinding: UnkeyedEnvironmentReader {
    package static func noteUnkeyedRead(in environment: EnvironmentValues) {
        FocusedValueReader.noteRead(in: environment)
    }
}

// MARK: - The property walks

// Handled by the environment walk directly, so the walks need not look inside.
extension FocusedValue: FrameworkDynamicProperty {}
extension FocusedBinding: FrameworkDynamicProperty {}

// Each reads a table it does not hold: a view holding one compares equal to
// another reading a different focus. See `TypeWalk`.
extension FocusedValue: _ReadsItsSource {}
extension FocusedBinding: _ReadsItsSource {}
