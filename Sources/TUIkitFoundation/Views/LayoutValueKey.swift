//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutValueKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Layout Value Key

/// A key for a value a view hands to the ``Layout`` that arranges it.
///
/// The channel by which a subview tells its layout something the layout cannot
/// work out from geometry alone — a column span, a sort rank, a "this one is
/// the hero" flag:
///
/// ```swift
/// private struct Span: LayoutValueKey {
///     static let defaultValue = 1
/// }
///
/// extension View {
///     func span(_ n: Int) -> some View { layoutValue(key: Span.self, value: n) }
/// }
///
/// // …then inside the layout:
/// let columns = subview[Span.self]
/// ```
///
/// The value travels with the view, not through the environment, so it reaches
/// exactly the one layout that arranges it and no deeper.
public protocol LayoutValueKey {
    /// The type of value this key carries.
    associatedtype Value

    /// The value a subview that never set one reports.
    static var defaultValue: Value { get }
}

// MARK: - Carrying the Values

/// A view carrying layout values for its container's ``Layout`` to read.
///
/// Produced by ``View/layoutValue(key:value:)``. Renders transparently as its
/// content; the values are metadata.
///
/// - Important: Framework infrastructure. Created by
///   ``View/layoutValue(key:value:)``; do not instantiate directly.
public struct _LayoutValueView<Content: View>: View {
    /// The key this view sets, identified by its type.
    let key: ObjectIdentifier

    /// The value, type-erased — recovered by the `LayoutValueKey`-typed
    /// subscript on ``LayoutSubview``, which knows what it asked for.
    let value: Any

    /// The wrapped content view.
    let content: Content

    public var body: some View {
        content
    }

    /// See ``View/_providesLayoutValues``.
    public static var _providesLayoutValues: Bool { true }
}

/// A view that can answer for the layout values set on it.
///
/// Implemented by the wrapper ``View/layoutValue(key:value:)`` produces. Unlike
/// the alignment-guide equivalent this needs no static witness: it is only ever
/// consulted from inside a ``Layout``, which is already off the hot path that
/// every child of every stack walks.
@MainActor
package protocol LayoutValueProviding {
    /// The value set for `key`, or `nil` if this view (or anything it wraps)
    /// did not set one.
    func layoutValue(for key: ObjectIdentifier) -> Any?
}

extension _LayoutValueView: LayoutValueProviding {
    package func layoutValue(for key: ObjectIdentifier) -> Any? {
        if key == self.key { return value }
        // Chained values nest, so a wrapper that cannot answer asks the one it
        // wraps. The OUTERMOST wins for a repeated key, as with every modifier.
        return (content as? LayoutValueProviding)?.layoutValue(for: key)
    }
}

extension View {
    /// Associates a value with this view, for the ``Layout`` that arranges it
    /// to read.
    ///
    /// - Important: Apply it as the **outermost** modifier on a subview the
    ///   layout should read, for the reason given on
    ///   ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``: a
    ///   modifier applied after it hides the value from the container.
    ///
    /// - Parameters:
    ///   - key: The key type.
    ///   - value: The value to associate.
    /// - Returns: A view carrying the layout value.
    public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        _LayoutValueView(key: ObjectIdentifier(K.self), value: value, content: self)
    }
}

// MARK: - Layout Priority

/// The built-in key behind ``View/layoutPriority(_:)``.
private struct LayoutPriorityKey: LayoutValueKey {
    static let defaultValue: Double = 0
}

extension View {
    /// Sets the priority by which a parent layout should apportion space to
    /// this child.
    ///
    /// The built-in stacks (``HStack``, ``VStack``, ``HStackLayout``,
    /// ``VStackLayout``) offer space to their highest-priority children first:
    /// each priority is offered what is left once every child of a lower one
    /// has its minimum size — its size when offered nothing, `…` for a
    /// truncating ``Text`` — and divides it as a stack of one priority does.
    /// So `HStack { Text(long); Text(other).layoutPriority(1) }` keeps `other`
    /// whole and truncates `long`. A custom ``Layout`` reads it from
    /// ``LayoutSubview/priority`` and is free to use it as it likes.
    ///
    /// A priority is kept through modifiers that do not lay the view out anew
    /// (`.foregroundStyle`, `.font`, `.background`, `.tag`, …) and lost under
    /// one that does (`.padding`, `.frame`), as SwiftUI keeps it (measured,
    /// `Tools/SwiftUIProbes/Layout priority/priority.out`).
    ///
    /// - Parameter value: The priority. Higher wins; the default is `0`.
    /// - Returns: A view carrying the priority.
    public func layoutPriority(_ value: Double) -> some View {
        layoutValue(key: LayoutPriorityKey.self, value: value)
    }
}

extension LayoutSubview {
    /// The priority set with ``View/layoutPriority(_:)``, or `0`.
    public var priority: Double {
        self[LayoutPriorityKey.self]
    }
}

/// The priority `child` was given with ``View/layoutPriority(_:)``, or `0`:
/// read through every single-content wrapper written after it, as SwiftUI
/// keeps it, and through a member's proxy to the member.
///
/// The static witness (``View/_providesLayoutValues``) gates the walk, so a
/// child whose type sets no layout value costs one witness call.
@MainActor
func layoutPriority(of child: ChildView) -> Double {
    layoutPriority(ofView: child.wrappedView)
}

@MainActor
private func layoutPriority(ofView view: any View) -> Double {
    guard type(of: view)._providesLayoutValues else { return 0 }
    let key = ObjectIdentifier(LayoutPriorityKey.self)
    var current = view
    while true {
        if let provider = current as? LayoutValueProviding, let value = provider.layoutValue(for: key) as? Double {
            return value
        }
        if let proxy = current as? LayoutTraitsForwarding { return layoutPriority(of: proxy.forwardedChild) }
        guard let wrapper = current as? any SingleContentWrapper else { return 0 }
        current = wrapper.wrappedContent
    }
}

/// Each of `children`'s length along a stack's axis when offered none of it —
/// what a child of a lower priority keeps when a higher one takes the rest
/// (`…` for a truncating `Text`, a spacer's minimum length). `across` is what
/// each is offered on the other axis. Measured only for a stack whose
/// children have priorities (``layoutPriorities(of:)``).
@MainActor
func minimumLengths(
    of children: [ChildView], horizontally: Bool, across: Int?, context: RenderContext
) -> [Int] {
    children.map { child in
        if child.isSpacer { return child.spacerMinLength ?? 0 }
        let proposal =
            horizontally ? ProposedSize(width: 0, height: across) : ProposedSize(width: across, height: 0)
        let size = child.measure(proposal: proposal, context: context)
        return horizontally ? size.width : size.height
    }
}

/// Each of `children`'s layout priorities, or `nil` when every one is `0` —
/// the common answer, for which a stack keeps the distribution it always had.
@MainActor
func layoutPriorities(of children: [ChildView]) -> [Double]? {
    var priorities: [Double]?
    for (index, child) in children.enumerated() {
        let priority = layoutPriority(of: child)
        guard priority != 0 else { continue }
        if priorities == nil { priorities = [Double](repeating: 0, count: children.count) }
        priorities?[index] = priority
    }
    return priorities
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _LayoutValueView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}
