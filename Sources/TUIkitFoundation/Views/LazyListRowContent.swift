//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyListRowContent.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Lazy Row Content

/// Where a list's rows sit inside a ``View/gradientExtent(_:)`` ramp spanning
/// the whole list.
///
/// A list renders its rows on demand, so it does not know how tall a row is
/// until it has rendered one — and it has to know before it can decide what
/// colour to render it. So the ramp holds a single row PITCH, seeded from the
/// first row (measured, not rendered) and applied to every row by ordinal. That
/// is exact wherever the rows are the same height, which is a list's ordinary
/// shape, and an estimate otherwise — the same convention the anchored lazy
/// stack window already lives with, for the same reason.
///
/// A class so the list can settle the pitch after the row boxes have been
/// handed out, and a row can read the settled answer at the moment it renders.
@MainActor
package final class ListRowRamp {
    /// The rectangle the ramp runs across. `nil` until the list settles it — a
    /// row rendering before then takes no placement, which is only ever the
    /// row the pitch was seeded from, and its place is the origin regardless.
    package var frame: GradientFrame? { get { _frame } set { _frame = newValue } }

    /// One row's height, in lines.
    package var pitch: Int { get { _pitch } set { _pitch = newValue } }

    // The storage under the `package` accessors: private (CONTRIBUTING.md,
    // "Crossing a module boundary").
    private var _frame: GradientFrame?
    private var _pitch = 1

    /// No arguments, spelled out because the implicit initializer is internal
    /// and TUIkitLists makes these, for its lists.
    package init() {}

    /// Where the row at `index` sits in the ramp.
    func placement(row index: Int) -> GradientFrame? {
        frame?.offset(byX: 0, y: index * pitch)
    }
}

/// What decides a list row's separator once the row has rendered (decisions
/// A47): the list's row source, which knows the defaults written above the list
/// and what the row reported (``LazyListRowContent/separatorDecider``).
@MainActor
package protocol ListRowSeparatorDeciding: AnyObject {
    /// The separator the row at `index`, drawn as `box`, draws below itself,
    /// or `nil`.
    func separatorLine(at index: Int, of box: LazyListRowContent) -> ListRowSeparatorLine?
}

/// A row's rendered buffer and badge, produced on demand and then memoised.
///
/// `List` extraction builds one of these per row but renders *none* up front:
/// the closure runs only when a row enters the visible window (or, for a list
/// short enough that it might fit, when the overflow check has to sum a few
/// heights). A 2,000-row list therefore renders ~viewport rows per frame
/// instead of all 2,000 — the per-frame cost becomes O(visible), not O(total).
/// The result is cached so the windowing, width, and compose passes that each
/// read the buffer don't trigger a re-render.
///
/// Rendering runs the view pipeline, which is `@MainActor`, so this box is
/// `@MainActor` too. That also makes it `Sendable`, which is what lets
/// ``SelectableListRow`` remain `Sendable` while carrying deferred content.
///
/// `@usableFromInline` for the `@inlinable` ``buffer`` and ``badge``: a
/// member is no more visible than its class, and the compiler serialises no
/// body for one that is not (module split).
@MainActor
@usableFromInline
package final class LazyListRowContent {
    private var thunk: ((GradientFrame?, BackgroundProminence) -> (buffer: FrameBuffer, badge: ListRowBadge?))?

    /// The row's render, once it has one: what ``buffer`` and ``badge`` lend.
    ///
    /// `@usableFromInline`, so internal rather than `private`, for those two
    /// `@inlinable` accessors, which TUIkitLists' row code calls from 27
    /// places in a release `Stress` (25 to ``buffer``, 2 to ``badge``),
    /// several of them per drawn row. Without their bodies each ``buffer``
    /// read was a call into its read coroutine, which heap-allocates its
    /// frame, copies the buffer into it and calls back to end the access,
    /// and each ``badge`` read was a getter call: about 3% of a `megalist`
    /// frame in the profile that found it, where the single module read the
    /// property in place.
    ///
    /// This is the one exception to CONTRIBUTING.md's rule "never make a
    /// class's stored property `@usableFromInline`" (in "Crossing a module
    /// boundary"), which allows it only where the binary shows every access
    /// to the property is already dynamic. The rule exists because another
    /// module's view of a class stored property stops the optimiser from
    /// proving its accesses free of conflict, so each keeps a run-time
    /// exclusivity check (`swift_beginAccess`). That decision is all or
    /// nothing per property, so one `swift_beginAccess` on a property shows
    /// that every access to it is checked, and this one has them inside one
    /// module: in a release `Stress`, this class's functions check it at 14
    /// sites in 13 functions before the change (9 in 8 at the pre-split
    /// c181ec0f9), each at its field offset, and at c181ec0f9 the list's row
    /// code kept a check on each read it inlined. So the widening adds no
    /// check. Do not copy it for a property with no such check, whose
    /// accesses are statically enforced, such as the storage under
    /// ``separatorDecider``.
    @usableFromInline var cached: (buffer: FrameBuffer, badge: ListRowBadge?)?

    /// The prominence of the background the list paints under this row — raised
    /// for the focused, selected row, whose content then renders with
    /// `\.backgroundProminence` set to it (``BackgroundProminence``).
    ///
    /// Read when the row renders, like ``gradientRamp``, because the list knows
    /// which row that is only once its handler has settled, and the overflow
    /// check may have rendered the row before then. Changing it after a render
    /// drops that render, so the next read of ``buffer`` renders again with the
    /// new value — which is why the render closure is kept after the first.
    /// A row whose buffer was handed over already rendered (chrome and the
    /// eager rows) has no render to repeat and keeps the buffer it was given.
    package var backgroundProminence: BackgroundProminence {
        get { _backgroundProminence }
        set { _backgroundProminence = newValue }
    }

    /// The least height the list gives this row, in lines — its
    /// `\.defaultMinListRowHeight`, or `\.defaultMinListHeaderHeight` for a
    /// section header. A shorter render is padded to it with the content
    /// centred, as a macOS list centres a row in a taller one; a row already
    /// in hand when this is set is padded then.
    package var minimumHeight: Int { get { _minimumHeight } set { _minimumHeight = newValue } }

    // The storage under this class's `package` accessors: private
    // (CONTRIBUTING.md, "Crossing a module boundary"). The observers are the
    // accessors' behaviour, on the storage so that this module's own writes
    // run them too.
    private var _backgroundProminence = BackgroundProminence.standard {
        didSet {
            guard _backgroundProminence != oldValue, thunk != nil else { return }
            cached = nil
        }
    }
    private var _minimumHeight = 1 {
        didSet {
            guard _minimumHeight != oldValue, let cached else { return }
            self.cached = (paddedToMinimum(cached.buffer), cached.badge)
        }
    }
    private var _sectionSeparator: (edge: VerticalEdge, visibility: Visibility, tint: Color?)?
    private weak var _separatorDecider: (any ListRowSeparatorDeciding)? {
        didSet { separatorDecided = false }
    }
    private var _separatorLine: ListRowSeparatorLine?
    private var _gradientRamp: ListRowRamp?
    private var _rowIndex = 0
    private var _typeSelectProbe: (() -> String?)?

    /// `buffer` with blank lines above and below to make ``minimumHeight``,
    /// the content in the middle; `buffer` itself when it is tall enough.
    private func paddedToMinimum(_ buffer: FrameBuffer) -> FrameBuffer {
        let extra = minimumHeight - buffer.height
        guard extra > 0 else { return buffer }
        let above = extra / 2
        var padded = FrameBuffer(lines: Array(repeating: "", count: above))
        padded.appendVertically(buffer)
        padded.appendVertically(FrameBuffer(lines: Array(repeating: "", count: extra - above)))
        return padded
    }

    /// The section edge whose separator is the line under this row, where it is
    /// one — a section's header (its `.top` edge) or its last row (its `.bottom`)
    /// — with that section's own preference for it (decisions A47). Set by the
    /// list's extraction; `nil` for every other row, whose line is its own.
    package var sectionSeparator: (edge: VerticalEdge, visibility: Visibility, tint: Color?)? {
        get { _sectionSeparator }
        set { _sectionSeparator = newValue }
    }

    /// Decides, once the row has rendered, whether it draws a separator below
    /// it — the row's own preference is only known then — and how, asked of
    /// this row's ``rowIndex``. Installed by the list; `nil` where nothing can
    /// ask for one.
    ///
    /// A reference, not a closure: every row box the list materialises takes
    /// one every frame, and a closure capturing the index was an allocation per
    /// box per frame. Weak, as the source holds the box: a box read after its
    /// frame has no list to ask.
    package var separatorDecider: (any ListRowSeparatorDeciding)? {
        get { _separatorDecider }
        set { _separatorDecider = newValue }
    }

    /// Whether ``separatorDecider`` has been asked about the render in hand.
    private var separatorDecided = false

    /// The separator this row draws below its content, when it draws one: the
    /// buffer's last line is its place, so every height the list reads counts
    /// it, and the list draws the rule there (`_ListCore.renderRow`).
    package var separatorLine: ListRowSeparatorLine? { _separatorLine }

    /// This row's size without rendering it, when the content can answer —
    /// measured at the width the row would be rendered at, which comes back
    /// beside the size so a flexible row can be read as the render would have
    /// filled it. `nil` where nothing can answer but the render itself.
    ///
    /// Two callers. A list spanning a ramp across its rows has to know how
    /// tall a row is before it can choose the colour to render that row in.
    /// And a list asked to hug its content — `.fixedSize(horizontal:)`, or a
    /// `NavigationSplitView` sizing a sidebar — has to know how wide EVERY row
    /// is, on every frame; rendering two thousand rows to learn that was 93%
    /// of a split-view frame, and a measure through the size memo is a lookup.
    private var measureSize: (() -> (size: ViewSize, availableWidth: Int))?

    /// Whether the row's static type can carry a `.badge(_:)` at all — the
    /// answer ``badge`` would give without building and rendering the row to
    /// give it. `false` means `badge` is `nil` and need not be asked.
    package let carriesBadge: Bool

    /// The ramp this row is placed in, or `nil` when no
    /// `.gradientExtent(.subtree)` is in force — which is almost always.
    ///
    /// Read at the moment the row renders rather than when the box is built,
    /// because the list settles the ramp's extent from the first row's height
    /// and that is not known until the boxes exist. A row whose buffer is
    /// already in hand (section chrome) ignores it: it has nothing left to
    /// render, and was placed where it was rendered.
    package var gradientRamp: ListRowRamp? { get { _gradientRamp } set { _gradientRamp = newValue } }

    /// This row's ordinal, for ``gradientRamp``.
    package var rowIndex: Int { get { _rowIndex } set { _rowIndex = newValue } }

    /// The identity the row's content is rendered under, when the row came from
    /// a `ForEach` (`nil` for chrome and the eager fallbacks, which have no
    /// per-element identity to speak of).
    ///
    /// Carried here rather than on ``SelectableListRow`` because this is a
    /// class: a new stored property on the struct would change its layout, and
    /// a dependent module built against the old one fails in ways that look
    /// nothing like the cause. It is what lets a `List` recognise a row of its
    /// own as the source of a `.draggable` drag — the drag names the identity of
    /// the view that started it, which is this row's identity or a descendant.
    ///
    /// `nonisolated` because it is an immutable `Sendable` fixed at
    /// construction: reading it must not force the main actor the way reading
    /// the (rendered) buffer does.
    package nonisolated let rowIdentity: ViewIdentity?

    /// The row's type-select text when the row's view is at hand to ask —
    /// its stated equivalent, or its first line drawn as a measure — or `nil`
    /// for a row handed over already drawn, whose drawn first line is its text
    /// (``typeSelectText``).
    package var typeSelectProbe: (() -> String?)? { get { _typeSelectProbe } set { _typeSelectProbe = newValue } }

    /// The text a typed prefix matches this row by: its stated equivalent
    /// (``View/typeSelectEquivalent(_:)-(Text?)``), else its first line of
    /// text — asked of the row's view where there is one, so a row out of
    /// sight is drawn only as a measure, and read off the drawn buffer
    /// otherwise.
    package var typeSelectText: String? {
        if let typeSelectProbe { return typeSelectProbe() }
        return buffer.lines.first.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Defers rendering until the buffer (or badge) is first read.
    package init(
        identity: ViewIdentity? = nil,
        carriesBadge: Bool = true,
        measure: (() -> (size: ViewSize, availableWidth: Int))? = nil,
        render: @escaping (GradientFrame?, BackgroundProminence) -> (buffer: FrameBuffer, badge: ListRowBadge?)
    ) {
        self.rowIdentity = identity
        self.carriesBadge = carriesBadge
        self.measureSize = measure
        self.thunk = render
    }

    /// Wraps an already-rendered buffer. Used for section headers/footers and
    /// the single-row fallbacks — there are only ever a handful of those and
    /// they are always shown, so deferring them would buy nothing.
    ///
    /// `nonisolated` so the (nonisolated) `SelectableListRow` / `ListRow`
    /// buffer initializers can wrap an already-rendered buffer without hopping
    /// to the main actor — it only stores a `Sendable` tuple, runs no pipeline.
    package nonisolated init(buffer: FrameBuffer, rowBadge: ListRowBadge?) {
        self.rowIdentity = nil
        self.carriesBadge = rowBadge != nil
        self.cached = (buffer, rowBadge)
    }

    /// Wraps an already-rendered buffer and a badge with no prominence of its
    /// own — see ``init(buffer:rowBadge:)``.
    package nonisolated convenience init(buffer: FrameBuffer, badge: BadgeValue?) {
        self.init(buffer: buffer, rowBadge: badge.map { ListRowBadge(value: $0) })
    }

    /// Forgets the render, so the next read of ``buffer`` renders the row again
    /// — for a row whose cached render the list cleared after this box was
    /// served it. Nothing for a box handed its buffer already rendered.
    package func discardRender() {
        guard thunk != nil else { return }
        cached = nil
    }

    /// Renders the row if it has not been rendered, leaving the answer in
    /// ``cached``. Separate from the two accessors below so that neither has to
    /// hand back a COPY of the pair to read one half of it.
    ///
    /// `@usableFromInline`, so internal rather than `private`, for those two
    /// `@inlinable` accessors; not `@inlinable` itself, so a read in another
    /// module is one call to it, as it was inside one module.
    @usableFromInline
    func resolveIfNeeded() {
        guard cached == nil || !separatorDecided && separatorDecider != nil else { return }
        // Kept after the render, for a row whose ``backgroundProminence`` the
        // list raises after something has already rendered it. A box lives for
        // one frame's row source, so what the closure holds goes with it.
        if cached == nil {
            let rendered = thunk!(gradientRamp?.placement(row: rowIndex), backgroundProminence)
            cached = (paddedToMinimum(rendered.buffer), rendered.badge)
            separatorDecided = false
        }
        guard !separatorDecided, let decider = separatorDecider else { return }
        separatorDecided = true
        _separatorLine = decider.separatorLine(at: rowIndex, of: self)
        if separatorLine != nil { cached!.buffer.appendVertically(FrameBuffer(lines: [""])) }
    }

    /// The row's rendered buffer, BORROWED rather than returned.
    ///
    /// The same trade ``FrameBuffer/lines`` makes and for a bigger reason: this
    /// used to read `resolved.buffer`, and `resolved` returned the whole
    /// `(buffer, badge)` pair by value — so every read of one row's buffer
    /// copied a `FrameBuffer` (six arrays retained and released) and then threw
    /// the badge away. A `List` frame reads it several times per drawn row, and
    /// `outlined init with copy of (buffer:badge:)` was 1.7% of a `megalist`
    /// frame with nothing else to show for it.
    ///
    /// `@inlinable` because TUIkitLists reads it (module split): a reader
    /// that cannot see the body calls the read coroutine, which allocates its
    /// frame on the heap and copies the buffer into it, where an inlined read
    /// borrows ``cached`` in place (see there for why that property may be
    /// `@usableFromInline`).
    @inlinable
    package var buffer: FrameBuffer {
        _read {
            resolveIfNeeded()
            yield cached!.buffer
        }
    }

    /// The row's badge, rendering the row first if need be. `@inlinable`
    /// for TUIkitLists, as ``buffer`` is.
    @inlinable
    package var badge: BadgeValue? {
        resolveIfNeeded()
        return cached!.badge?.value
    }

    /// The prominence written around the row's badge, inside the row — `nil`
    /// where none is, so the list's own applies (decisions B72). Renders the
    /// row first if need be, as ``badge`` does.
    package var badgeProminence: BadgeProminence? {
        resolveIfNeeded()
        return cached!.badge?.prominence
    }

    /// The row's buffer without the line its separator is drawn on: the row
    /// lifted out of the list — a drag's floating copy — where there is no row
    /// below it to separate it from, and a blank line under each row of a
    /// carried block read as a gap in it.
    package var bufferWithoutSeparator: FrameBuffer {
        var drawn = buffer
        if separatorLine != nil, !drawn.lines.isEmpty { drawn.lines.removeLast() }
        return drawn
    }

    /// The row's height, rendering it only if there is no other way to ask.
    package var heightWithoutRendering: Int {
        // Through ``buffer``, not `cached`, so a separator not yet decided is.
        if cached != nil { return buffer.height }
        if let measureSize { return max(minimumHeight, measureSize().size.height) }
        return buffer.height
    }

    /// The width the row's buffer would have, without rendering it — or `nil`
    /// when only the render can say (chrome and the eager fallbacks, which
    /// have already rendered and answer through ``buffer`` for nothing).
    ///
    /// Read as the render would have filled it: a row flexible in width
    /// renders filled to the width it was offered, and a row wider than that
    /// is clamped to it, so this is `buffer.width` by construction rather than
    /// by coincidence — `ListTests` pins the hug to the widest of every row.
    package var widthWithoutRendering: Int? {
        if let cached { return cached.buffer.width }
        guard let measureSize else { return nil }
        let measured = measureSize()
        return measured.size.isWidthFlexible
            ? measured.availableWidth
            : min(measured.size.width, measured.availableWidth)
    }
}
