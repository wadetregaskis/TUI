//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerValues.swift
//
//  Values a view sets for the container directly around it to read: SwiftUI's
//  `ContainerValues`, `ContainerValueKey` and `.containerValue(_:_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Container Value Key

/// A key for accessing container values.
///
/// Declare a key with a default, then a property on ``ContainerValues`` that
/// reads and writes it — the shape SwiftUI's own documentation of this
/// protocol shows:
///
/// ```swift
/// private struct PinRotationKey: ContainerValueKey {
///     static let defaultValue: Double = 0
/// }
///
/// extension ContainerValues {
///     var pinRotation: Double {
///         get { self[PinRotationKey.self] }
///         set { self[PinRotationKey.self] = newValue }
///     }
/// }
/// ```
///
/// `@Entry var pinRotation: Double = 0` inside the extension generates those
/// same declarations, as in SwiftUI. `@Entry` is a macro, in the opt-in
/// `TUIkitMacros` product, which an app imports beside TUIkit so that only an
/// app that asks for the macros builds swift-syntax; without it the key is
/// written out by hand, as above.
public protocol ContainerValueKey {
    /// The type of value produced by the container value.
    associatedtype Value

    /// The default value of the container value.
    static var defaultValue: Value { get }
}

// MARK: - Container Values

/// A collection of container values associated with a given view.
///
/// Container values are set on a view with ``View/containerValue(_:_:)``, and
/// tags with ``View/tag(_:includeOptional:)``. Like preferences, they are read
/// by a view above the one that sets them; unlike preferences, they do not
/// merge and do not escape their closest container. They survive modifiers
/// that are not containers:
///
/// ```swift
/// VStack {
///     Text("A").containerValue(\.pinRotation, 1)   // 1
///     Text("B").containerValue(\.pinRotation, 2)   // 2
///     Text("C").containerValue(\.pinRotation, 3)
///         .padding()                                // still 3
/// }   // the VStack's own value is the default: it never escapes the stack
/// ```
///
/// What reads them is the container directly around: a ``Subview`` handed out
/// by ``Group/init(subviews:transform:)`` or ``ForEach/init(subviews:content:)``,
/// a custom layout's ``LayoutSubview``, and a ``SectionConfiguration`` for the
/// values written on its `Section`. A `ForEach`'s rows are each
/// tagged with their element's `id` unless they tag themselves, as in SwiftUI.
public struct ContainerValues {
    /// The values written with ``View/containerValue(_:_:)``, by key type.
    private var values: [ObjectIdentifier: Any] = [:]

    /// The tags, in the order they were written: innermost first, so the last
    /// one is the outermost — the one in force for its type.
    private var tags: [(value: AnyHashable, includeOptional: Bool)] = []

    /// No values and no tags: what a view that sets none reports.
    init() {}

    /// Accesses the particular container value associated with a custom key.
    ///
    /// - Parameter key: The key's type.
    public subscript<Key: ContainerValueKey>(key: Key.Type) -> Key.Value {
        get {
            // Unwrapped first, then cast: a stored `nil` of an optional
            // `Value` is a value, and casting the dictionary's own `Any?`
            // would turn an ABSENT key into that `nil` instead of the default.
            guard let stored = values[ObjectIdentifier(key)] else { return Key.defaultValue }
            return stored as? Key.Value ?? Key.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }

    /// The tag value for the given type if the container values contain one.
    ///
    /// Tags are matched by casting, the rule ``View/tag(_:includeOptional:)``
    /// states: a tag of `Speed` answers for `Speed?` too unless it was set with
    /// `includeOptional: false`. Of several tags that answer, the outermost
    /// `.tag(_:)` wins, and any explicit tag beats the one a `ForEach` row gets
    /// from its element's `id`.
    ///
    /// - Parameter type: The type to get the tag value for.
    /// - Returns: The tag value for the given type if the subview has one,
    ///   otherwise `nil`.
    public func tag<V: Hashable>(for type: V.Type) -> V? {
        for tag in tags.reversed() {
            if let value = resolveTag(tag.value, includeOptional: tag.includeOptional, as: V.self) {
                return value
            }
        }
        return nil
    }

    /// Returns true if the container values contain a tag matching a given
    /// value.
    ///
    /// - Parameter tag: The tag value to check for.
    /// - Returns: If the container values has a tag matching the given value.
    public func hasTag<V: Hashable>(_ tag: V) -> Bool {
        self.tag(for: V.self) == tag
    }

    /// Records a tag, as the outermost so far.
    mutating func appendTag(_ value: AnyHashable, includeOptional: Bool) {
        tags.append((value, includeOptional))
    }
}

// MARK: - Writing Them

/// A view carrying a value written with ``View/containerValue(_:_:)``.
///
/// Renders exactly as its content: the value is metadata for the container
/// around it. Written on several views at once — a `Group`, a `ForEach` — it
/// reaches each of them, as in SwiftUI, because a value is not an effect: it
/// multiplies nothing by being distributed (see ``SingleContentWrapper``).
///
/// - Important: Framework infrastructure. Created by
///   ``View/containerValue(_:_:)``; do not instantiate directly.
public struct _ContainerValueView<Content: View>: View {
    /// The wrapped content view.
    let content: Content

    /// Writes this view's value into a ``ContainerValues``.
    let write: (inout ContainerValues) -> Void

    public var body: some View {
        content
    }

    /// Static witness: this view writes a container value — see
    /// ``View/_providesContainerValues``.
    public static var _providesContainerValues: Bool { true }
}

extension View {
    /// Sets a particular container value of a view.
    ///
    /// Use this modifier to set one of the writable properties of the
    /// ``ContainerValues`` structure, including custom values that you create.
    /// The value is read by the container closest around this view — through
    /// ``Subview/containerValues``, ``LayoutSubview/containerValues`` or
    /// ``SectionConfiguration/containerValues`` — and by nothing further out,
    /// even a container with only this one view in it. A key path into a property of a value sets just that part:
    ///
    /// ```swift
    /// Text("B")
    ///     .containerValue(\.pinPosition.rotation, 10)
    ///     .containerValue(\.pinPosition.xOffset, 5)
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A key path that indicates the property of the
    ///     ``ContainerValues`` structure to update.
    ///   - value: The new value to set for the item specified by `keyPath`.
    /// - Returns: A view that has the given value set in its container values.
    public func containerValue<V>(
        _ keyPath: WritableKeyPath<ContainerValues, V>, _ value: V
    ) -> some View {
        _ContainerValueView(content: self) { $0[keyPath: keyPath] = value }
    }
}

extension _ContainerValueView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

extension _ContainerValueView: ContentRewrapping {
    public func rewrapping<V: View>(_ view: V) -> any View {
        _ContainerValueView<V>(content: view, write: write)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``ContentRewrapping`` wrapper — each member comes back inside a copy
/// of this one, carrying the value.
extension _ContainerValueView: ChildViewProvider where Content: ChildViewProvider {}

// MARK: - Reading Them

/// A view that writes container values: ``_ContainerValueView`` and the tag
/// wrapper.
@MainActor
protocol ContainerValueWriting {
    /// Writes this view's values into `values`, over whatever is there.
    func writeContainerValues(into values: inout ContainerValues)
}

extension _ContainerValueView: ContainerValueWriting {
    func writeContainerValues(into values: inout ContainerValues) {
        write(&values)
    }
}

extension ContainerValues {
    /// The values `child` carries for the container it is a member of.
    ///
    /// `implicitTag` is the element id a `ForEach` row is tagged with by
    /// default, written first so any explicit tag outranks it.
    ///
    /// Read through every single-content wrapper — `.padding()`, `.frame`,
    /// `.foregroundStyle` and the rest are not containers — and through
    /// `ForEach`'s row memo, whose TYPE is asked first, so a row is built only
    /// when it can carry a value. The writers apply innermost first, so the
    /// outermost write of a key wins, as with every modifier. Nothing is walked
    /// for a child whose type writes nothing (``View/_providesContainerValues``).
    @MainActor
    init(of child: ChildView, implicitTag: AnyHashable?) {
        self.init()
        if let implicitTag { appendTag(implicitTag, includeOptional: true) }
        // Only a keyed child — a `ForEach` row — can be behind the memo, so
        // a positional one does not pay the cast.
        for writer in containerValueWriters(
            of: child.wrappedView, lookingThroughMemo: child.identityChildKey != nil
        ).reversed() {
            writer.writeContainerValues(into: &self)
        }
    }
}

/// The views writing container values on `view`, outermost first.
@MainActor
private func containerValueWriters(
    of view: any View, lookingThroughMemo: Bool
) -> [any ContainerValueWriting] {
    var current = view
    // A member that is an `AnyView` is what it erases, to the container
    // reading its values, as SwiftUI takes an `AnyView` apart (the
    // compatibility guide's Subviews row, measured): `AnyView(Text("a").tag(1))`
    // is an option tagged 1. A metatype compare, so every other member pays
    // one pointer comparison. An `AnyView` under a modifier is not looked
    // into: its witness cannot say what it erases, and answering "may" for
    // every `AnyView` would walk every erased row in every container.
    while type(of: current) == AnyView.self, let erased = current as? AnyView {
        current = erased.erasedView
    }
    if !type(of: current)._providesContainerValues {
        guard lookingThroughMemo, let memo = current as? any _ValueMemoWrapping,
            memo.memoizedContentType._providesContainerValues
        else { return [] }
        current = memo.memoizedContent
    }
    var writers: [any ContainerValueWriting] = []
    // The witness is asked at each step, so the walk stops at the innermost
    // writer rather than descending through everything below it.
    while type(of: current)._providesContainerValues {
        if let writer = current as? any ContainerValueWriting { writers.append(writer) }
        guard let wrapper = current as? any SingleContentWrapper else { break }
        current = wrapper.wrappedContent
    }
    return writers
}
