//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusedValue.swift
//
//  `@FocusedValue` and `@FocusedBinding`: reading what the focused view, or
//  one of its ancestors, published.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUICore
import TUIView

// MARK: - The reader's link

/// What a focused-value property wrapper reads through: the focus manager of
/// the environment its view renders in, handed over by the same reflection
/// pass that fills the `@Environment` boxes.
///
/// A reference, so the copy of the wrapper an event closure captured reads
/// the manager the render found.
final class FocusedValueReader {
    weak var focusManager: FocusManager?
    /// Where it was last resolved (``PlaceResolvedReader``).
    var stamp = PlaceStamp<ViewIdentity>()

    /// Resolves the reader at `address` for `place` in `pass`, or, where it
    /// was resolved at another place in this pass, a reader of its own, which
    /// `install` puts in the copy: what `@FocusedValue` and `@FocusedBinding`
    /// share (``PlaceResolvedReader``).
    ///
    /// - Returns: Whether the copy was given a reader of its own.
    static func resolve(
        _ reader: FocusedValueReader, _ environment: EnvironmentValues, place: ViewIdentity, pass: UInt32,
        install: (FocusedValueReader) -> Void
    ) -> Bool {
        if reader.stamp.isSecondPlace(place, in: pass) {
            let own = FocusedValueReader()
            own.stamp.stamp(place, in: pass)
            own.resolve(environment)
            install(own)
            return true
        }
        reader.stamp.stamp(place, in: pass)
        reader.resolve(environment)
        return false
    }

    /// The values published for wherever the focus is now, or an empty table
    /// outside any render's environment.
    ///
    /// For the focus of the manager that owns the values, not of
    /// `focusManager`: a view drawn as a backdrop renders under a throwaway
    /// manager with no focus of its own, and reads what a live reader reads
    /// (`FocusedValueRegistry.owner`).
    var table: FocusedValues {
        guard let manager = focusManager else { return FocusedValues() }
        return manager.focusedValues.tableAtTheFocus()
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
///
/// A reader drawn as a backdrop — on the page beneath a sheet, or inside
/// `dimmed()` — reads what a reader on the live page reads: the values for
/// wherever the focus is, which while a sheet is up is in the sheet.
///
/// An open menu — a `Menu`'s, a context menu, the menu bar's — takes the
/// keyboard but not the focus, as a menu on macOS leaves the first responder
/// where it was: while it is open, its items and the page read the values of
/// the view focused where it was opened. So a menu bar command gated on a
/// focused value (`.disabled(note == nil)`) stays enabled in its open menu.
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    private var reader = FocusedValueReader()
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

/// Resolved for each place a view value is drawn at, as `@Environment` is.
extension FocusedValue: PlaceResolvedReader {
    package static func resolveEnvironment(
        at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues, place: ViewIdentity, pass: UInt32
    ) -> Bool {
        let value = address.assumingMemoryBound(to: Self.self)
        return FocusedValueReader.resolve(value.pointee.reader, environment, place: place, pass: pass) {
            value.pointee.reader = $0
        }
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
    private var reader = FocusedValueReader()
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

/// Resolved for each place a view value is drawn at, as `@Environment` is.
extension FocusedBinding: PlaceResolvedReader {
    package static func resolveEnvironment(
        at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues, place: ViewIdentity, pass: UInt32
    ) -> Bool {
        let binding = address.assumingMemoryBound(to: Self.self)
        return FocusedValueReader.resolve(binding.pointee.reader, environment, place: place, pass: pass) {
            binding.pointee.reader = $0
        }
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
