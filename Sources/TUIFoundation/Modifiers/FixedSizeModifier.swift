//  🖥️ TUI — A Terminal UI framework for Swift
//  FixedSizeModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIView

// MARK: - Fixed-Size Environment

/// EnvironmentKey: the immediately-enclosing view should size its width to its
/// content (its "ideal" width) rather than fill the width it is offered.
///
/// Set by ``View/fixedSize(horizontal:vertical:)`` and consumed by views that
/// are otherwise width-greedy — currently `List`, which then sizes to the widest
/// of *all* its rows instead of filling its container. The view that honours it
/// clears it for its own children so the request does not leak down the subtree.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct FixedSizeWidthKey: EnvironmentKey {
    @usableFromInline static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Whether the enclosing view should hug its content width (see
    /// ``FixedSizeWidthKey``).
    @inlinable
    package var fixedSizeWidth: Bool {
        get { self[FixedSizeWidthKey.self] }
        set { self[FixedSizeWidthKey.self] = newValue }
    }
}

// MARK: - Fixed-Size Modifier

extension View {
    /// Fixes a view at its ideal size on the chosen axes instead of letting it
    /// take the size it is offered — matches SwiftUI's
    /// `fixedSize(horizontal:vertical:)`.
    ///
    /// On a fixed axis the view is asked for its ideal size, as SwiftUI asks it
    /// with an unspecified proposal, and is that size whatever its container
    /// offers: `Text("Name").fixedSize()` in a crowded `HStack` keeps its whole
    /// title on one line and leaves its neighbours what remains, where it would
    /// otherwise share the squeeze. A view fixed wider than the `.frame`, the
    /// `.overlay` or the `.background` placing it is drawn at its size, placed
    /// by their alignment, what lies past them drawn past them, as SwiftUI's
    /// is; in any other container it overflows, cut at the container's edge,
    /// as anything wider than its region is. A view with no ideal size along
    /// an axis — one that fills what it is offered, a `Color` or a
    /// `.frame(maxWidth: .infinity)` — keeps the size it is offered there.
    ///
    /// A `List` fixed horizontally hugs its content, sizing to the widest of
    /// **all** its rows (stable as you scroll — it does not track only the rows
    /// on screen), where its default is to fill its container's width. A TUI
    /// addition: SwiftUI's `List` has no ideal width.
    ///
    /// - Parameters:
    ///   - horizontal: Fix the width at the ideal width. Default `true`.
    ///   - vertical: Fix the height at the ideal height: for most views the
    ///     height they need at the width they are given. Default `true`.
    nonisolated public func fixedSize(horizontal: Bool = true, vertical: Bool = true) -> some View {
        _FixedSizeView(content: self, horizontal: horizontal, vertical: vertical)
    }
}

/// ``View/fixedSize(horizontal:vertical:)``: its content at its ideal size on
/// the fixed axes, whatever it is offered there.
///
/// The content is asked for its ideal size as SwiftUI asks with an unspecified
/// proposal: once, offered far more than any terminal has
/// (``idealExtent(along:proposal:offered:context:)``), the width under the
/// ideal-width mark — so a `Text` reports its one-line width rather than
/// wrapping at whatever happened to be available. A view that takes the whole
/// of that offer (a `Color`, a `List`, a `.frame(maxWidth: .infinity)`) has no
/// ideal size along that axis, and keeps the size it is offered there.
///
/// It keeps the environment flag a `List` and a split view's measure read
/// (``EnvironmentValues/fixedSizeWidth``), which they read before this layout
/// existed and still do — set for the content's layout and drawing, and cleared
/// for the probe: a `List` hugs its rows itself under the flag, with its own
/// kept width and the observation that keeps it current, so the probe finds it
/// filling, as SwiftUI's `List` has no ideal width, and the list's own hug
/// answers.
nonisolated struct _FixedSizeView<Content: View>: View {
    let content: Content
    let horizontal: Bool
    let vertical: Bool

    @MainActor var body: Never {
        fatalError("_FixedSizeView renders via Renderable")
    }

    /// The extents the content is laid out at on the fixed axes, when it is
    /// offered `width` by `height`: its ideal ones, where it has them, and `nil`
    /// on an axis that is not fixed or where it has none — there it is offered
    /// what this view is, and sizes itself, as a `List` hugs its rows under the
    /// flag (``flagged(_:)``) at the width it is given, from a width it keeps
    /// for that width. Laid out at its hugged width instead, it missed its kept
    /// width and walked every row again.
    @MainActor fileprivate func idealExtents(
        width offeredWidth: Int, height offeredHeight: Int, context: RenderContext
    ) -> (width: Int?, height: Int?) {
        let width =
            horizontal
            ? idealExtent(
                along: .horizontal, proposal: ProposedSize(width: nil, height: vertical ? nil : offeredHeight),
                offered: offeredWidth, context: context)?.width
            : nil
        guard vertical else { return (width, nil) }
        var heightContext = context
        heightContext.availableWidth = width ?? offeredWidth
        let height = idealExtent(
            along: .vertical, proposal: ProposedSize(width: width ?? offeredWidth, height: nil), offered: offeredHeight,
            context: heightContext)?.height
        return (width, height)
    }

    /// The content's ideal size along `axis`: measured once under `proposal`,
    /// offered the natural-extent ladder's first rung there
    /// (`naturalExtentStartingBudget`, at least 4,096 cells), or `nil` where it
    /// took all of that, or answered a flexible nothing — a view that fills what
    /// it is offered has no ideal size.
    ///
    /// One measure, not the scroll view's ladder, which grows the offer while
    /// the content keeps reaching it: a row that took the width it was offered
    /// without calling itself flexible (a `List` nested in a hugging `List`)
    /// climbed it to the edge of `Int`, the content laid out at every rung.
    @MainActor private func idealExtent(
        along axis: Axis, proposal: ProposedSize, offered: Int, context: RenderContext
    ) -> ViewSize? {
        let budget = naturalExtentStartingBudget(forVisible: offered)
        var probe = context.askingIdealWidth(axis == .horizontal)
        probe.environment.fixedSizeWidth = false
        probe.environment.offeredNoWidth = false
        switch axis {
        case .horizontal: probe.availableWidth = budget
        case .vertical: probe.availableHeight = budget
        }
        let size = measureChild(content, proposal: proposal, context: probe)
        let extent = axis == .horizontal ? size.width : size.height
        let isFlexible = axis == .horizontal ? size.isWidthFlexible : size.isHeightFlexible
        // A flexible nothing is how a greedy view answers the ideal-width ask
        // (`RenderContext.fillingWidth(proposal:)`: SwiftUI's `List` and
        // `TextEditor` report 0, measured): it has no ideal size either.
        guard extent < budget, !(isFlexible && extent == 0) else { return nil }
        return size
    }

    /// `context` with the flag a `List` and a split view read
    /// (``EnvironmentValues/fixedSizeWidth``) said: set where the width is
    /// fixed, cleared where it is not — and with it whether the content was
    /// offered no width (``EnvironmentValues/offeredNoWidth``), which a frame
    /// with an ideal width reads.
    @MainActor fileprivate func flagged(_ context: RenderContext) -> RenderContext {
        let environment = context.environment
        guard environment.fixedSizeWidth != horizontal || environment.offeredNoWidth != horizontal else { return context }
        var flagged = context
        flagged.environment.fixedSizeWidth = horizontal
        flagged.environment.offeredNoWidth = horizontal
        return flagged
    }
}

@MainActor extension _FixedSizeView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var contentContext = flagged(context)
        guard horizontal || vertical else { return TUIView.renderToBuffer(content, context: contentContext) }
        let ideal = idealExtents(width: context.availableWidth, height: context.availableHeight, context: context)
        if let width = ideal.width { contentContext.availableWidth = width }
        if let height = ideal.height { contentContext.availableHeight = height }
        return TUIView.renderToBuffer(content, context: contentContext)
    }
}

@MainActor extension _FixedSizeView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var contentContext = flagged(context)
        guard horizontal || vertical else { return measureChild(content, proposal: proposal, context: contentContext) }
        let offeredWidth = proposal.width ?? context.availableWidth
        let offeredHeight = proposal.height ?? context.availableHeight
        let ideal = idealExtents(width: offeredWidth, height: offeredHeight, context: context)
        contentContext.availableWidth = ideal.width ?? offeredWidth
        contentContext.availableHeight = ideal.height ?? offeredHeight
        var size = measureChild(
            content, proposal: ProposedSize(width: ideal.width ?? offeredWidth, height: ideal.height ?? offeredHeight),
            context: contentContext)
        if let width = ideal.width { (size.width, size.isWidthFlexible) = (width, false) }
        if let height = ideal.height { (size.height, size.isHeightFlexible) = (height, false) }
        return size
    }
}

@MainActor extension _FixedSizeView: ContentRewrapping {
    /// Its content's geometry is its own — its content is laid out at its own size, the ideal one on a fixed axis — so a guide
    /// inside it passes unmoved (``SingleContentWrapper/_keepsContentGeometry``).
    static var _keepsContentGeometry: Bool { true }

    var wrappedContent: Content { content }

    /// Its content's context: the flags it sets for its content (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { flagged(context) }

    func rewrapping<V: View>(_ view: V) -> any View {
        _FixedSizeView<V>(content: view, horizontal: horizontal, vertical: vertical)
    }

    /// A fixed size lays its content out anew, at the size it chooses, as a
    /// frame does, so a priority written inside it is not its own.
    static var _providesLayoutValues: Bool { false }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
@MainActor extension _FixedSizeView: ChildViewProvider where Content: ChildViewProvider {}
