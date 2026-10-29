//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutValueKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIView

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
/// The child's stored flag (``ChildView/providesLayoutValues``, the static
/// witness ``View/_providesLayoutValues`` read when the child was made) gates
/// the walk, so a child whose type sets no layout value — almost every child
/// of almost every stack — costs one load, where asking the witness here,
/// through the existential, was a witness call per child per pass in every
/// stack: the one per-frame cost the stacks' priorities added everywhere, and
/// the A/B that landed them was +0.3% to +2.0% across the sweep.
@MainActor
func layoutPriority(of child: ChildView) -> Double {
    guard child.providesLayoutValues else { return 0 }
    return layoutPriority(ofView: child.wrappedView)
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

/// `child`'s length along a stack's axis when offered none of it — what it
/// keeps when its siblings take the rest (`…` for a truncating `Text`, a
/// spacer's minimum length, a frame's `minWidth`). `across` is what it is
/// offered on the other axis. Measured only when the distribution asks: where
/// `child` may be offered less than its natural length
/// (``distributeLinearSpace(naturalSizes:isFlexible:available:gaps:shares:isSpacer:priorities:minimumSize:statedMinimum:sizeAt:)``).
@MainActor
func minimumLength(of child: ChildView, horizontally: Bool, across: Int?, context: RenderContext) -> Int {
    if child.isSpacer { return child.spacerLength(along: horizontally ? .horizontal : .vertical) }
    // A column offered no height answers none, whatever it holds: it clamps its
    // children's total to the offer (`_VStackCore.clipSizeThatFits`). Answered
    // without the measure, which walked the whole column below to come back with
    // that zero — a quarter of `stateful`'s frame once columns shared their height
    // (decisions A-LAYOUT-1).
    if !horizontally, child.wrappedView is any ClampsHeightToOffer {
        return statedMinimumLength(of: child, horizontally: false)
    }
    let proposal = horizontally ? ProposedSize(width: 0, height: across) : ProposedSize(width: across, height: 0)
    let size = child.measure(proposal: proposal, context: context)
    return max(horizontally ? size.width : size.height, statedMinimumLength(of: child, horizontally: horizontally))
}

/// Whether a column has room for every child at its natural height, the gaps
/// between those that occupy it included — and so need offer none of its fixed
/// children less than that.
///
/// A column shares its height by flexibility (A-LAYOUT-1), which needs each
/// child's minimum, and TUI has no true one: offered no height, a column
/// answers none whatever it holds (``ClampsHeightToOffer``), and so does any
/// view around one, measured. Taken at its word beside a child that fills (a
/// gradient used as a view, a `Color`), a column of fixed rows — a block
/// `frame(height:)` fixes — was the most shrinkable thing there and was offered
/// an equal share, half the height, though the stack had room for all of it:
/// its trailing rows were cut, and in a `ScrollView`, which draws its content
/// at exactly the height it measured, a whole block vanished from the page (the
/// Example's mesh gradient, the owner, 2026-10-28, #10). So where everything
/// fits, a fixed child keeps its natural height, as columns did before they
/// shared, and the filling children share the rest; only an OVERFULL column,
/// the case A-LAYOUT-1 is about, asks for minimums. SwiftUI, whose minimums are
/// real, would still cut a fixed child that can shrink — a text of several
/// lines beside a colour — where it all fits; here it is drawn whole.
func fitsAtNaturalHeights(_ heights: [Int], isFlexible: [Bool], spacing: Int, available: Int) -> Bool {
    let occupying = heights.indices.count { isFlexible[$0] || heights[$0] > 0 }
    return heights.reduce(0) { $0 + max(0, $1) } + totalLinearSpacing(occupiedChildren: occupying, spacing: spacing)
        <= available
}

/// The minimum length `child` states along an axis whatever it is offered —
/// a frame's `minWidth` or `minHeight`, which `frame(width:)` sets — found
/// through the wrappers around it, or `0`.
///
/// A measure does not say so: TUI clamps a frame to what it is offered, so
/// offered nothing it answers nothing. SwiftUI's frame keeps its width and
/// overflows, so a stack deals it out first, as a child that cannot shrink;
/// without this, a label column `frame(width:)` fixes was squeezed like text.
@MainActor
func statedMinimumLength(of child: ChildView, horizontally: Bool) -> Int {
    throughWrappers(child.wrappedView, as: (any StatesMinimumLength).self)?.statedMinimumLength(horizontally: horizontally)
        ?? 0
}

/// A view that, offered no height, answers none, whatever its content: the
/// height it reports is clamped to the height it is offered. A `VStack` is one;
/// a `.environment(_:_:)` around one changes nothing of its layout, so it is one
/// too. ``minimumLength(of:horizontally:across:context:)`` answers such a
/// view's vertical minimum without measuring it.
@MainActor
protocol ClampsHeightToOffer {}

extension VStack: ClampsHeightToOffer {}
extension EnvironmentModifier: ClampsHeightToOffer where Content: ClampsHeightToOffer {}

/// A view with a minimum length of its own on either axis.
@MainActor
protocol StatesMinimumLength {
    /// The minimum length along the axis, or `0` for none.
    func statedMinimumLength(horizontally: Bool) -> Int
}

extension FlexibleFrameView: StatesMinimumLength {
    func statedMinimumLength(horizontally: Bool) -> Int {
        max(0, (horizontally ? minWidth : minHeight) ?? 0)
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

/// A layout value — a `.layoutPriority(_:)` among them — on several views is
/// each one's, as SwiftUI's modifier on a `Group` reaches each member: the
/// members of `Group { a; b }.layoutPriority(1)` are each served first.
extension _LayoutValueView: ContentRewrapping {
    public func rewrapping<V: View>(_ view: V) -> any View {
        _LayoutValueView<V>(key: key, value: value, content: view)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``ContentRewrapping`` wrapper.
extension _LayoutValueView: ChildViewProvider where Content: ChildViewProvider {}

/// Each of a row's cells with the value, as each member is.
extension _LayoutValueView: GridRowProviding where Content: GridRowProviding {}

// MARK: - In a Form

/// A layout value — a ``View/layoutPriority(_:)`` — written on a form row is
/// the row's the form lays out, which keeps its place, as SwiftUI's form keeps
/// it (measured, `Tools/SwiftUIProbes/Form rows`).
extension _LayoutValueView: FormRowRewrapping {
    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        _LayoutValueView<V>(key: key, value: value, content: row)
    }
}
