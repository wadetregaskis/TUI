//  🖥️ TUI — A Terminal UI framework for Swift
//  FlowLayout.swift
//
//  A layout that wraps its subviews onto lines, like words. SwiftUI has none;
//  a terminal's fixed width makes one wanted more often than on a Mac (rows of
//  chips, tag lists, key hints), and the Example had written its own three
//  times before the owner's ruling of 2026-11-10 made it the framework's.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A layout that places its subviews in a row and wraps onto a new line
/// whenever the next one would not fit, as text wraps words.
///
/// ```swift
/// FlowLayout(spacing: 1) {
///     ForEach(tags, id: \.self) { tag in
///         Text(" \(tag) ").inverted()
///     }
/// }
/// ```
///
/// It is a ``Layout`` value, so it can also be erased into an ``AnyLayout``
/// and switched with another while the subviews keep their identity and
/// their `@State`:
///
/// ```swift
/// let layout = isWrapping ? AnyLayout(FlowLayout()) : AnyLayout(VStackLayout())
/// ```
///
/// SwiftUI has no flow layout: this one is TUI's own.
///
/// ### Lines
///
/// Each subview is placed at its ideal size, and a line holds as many as fit
/// in the width, in order. Each line is as tall as its tallest member; a
/// shorter member sits in its line by ``alignment``'s vertical half, and each
/// line sits across the layout's width by its horizontal half.
///
/// A subview wider than the whole width starts a line and is offered that
/// width, as a squeezed subview of an ``HStackLayout`` is offered what it
/// gets: it takes what it reports there, and one that cannot narrow (a
/// `fixedSize()` text, a fixed frame) overhangs the trailing edge. A ``Text``
/// rarely gets here: its ideal is already its words wrapped to the width there
/// is, so a long one arrives as a taller member, making its line taller.
///
/// A subview of no width — an `EmptyView`, a collapsed conditional — takes
/// no part: no gap is drawn beside it, and it never starts a line.
///
/// ### Size
///
/// Offered no width (`nil`), the layout reports its ideal size: every subview
/// on one line. Offered a width, it reports its widest line, never more than
/// the width — a layout that hugs its content, as a stack does. Offered zero,
/// every subview of any width gets a line of its own and is offered zero, so
/// the height is the members' minimum heights stacked: the layout's minimum.
/// The height offered is not consulted; a flow is as tall as its lines.
///
/// ### Direction
///
/// Lines run from the leading edge to the trailing edge, and the first line is
/// at the top. Leading is left: ``EnvironmentValues/layoutDirection`` is always
/// left-to-right here. When right-to-left lands, this layout mirrors with the
/// stacks.
///
/// **Deliberate divergence from the stacks' SwiftUI defaults — `alignment`
/// defaults to `.topLeading`.** The same choice ``ZStackLayout`` makes (owner,
/// 2026-09-20): top-left reading suits a terminal, and a wrapped run of words
/// reads from the leading edge.
nonisolated public struct FlowLayout: Layout, Sendable, Equatable {
    /// How each line sits across the layout's width (the horizontal half), and
    /// how a member shorter than its line sits within it (the vertical half).
    public var alignment: Alignment

    /// Blank columns between neighbours on a line, or `nil` for what each pair
    /// of neighbours prefers, as ``HStackLayout``'s `spacing`.
    public var spacing: Int?

    /// Blank rows between lines, or `nil` for what views prefer between rows,
    /// which is none, as ``VStackLayout``'s `spacing`.
    public var lineSpacing: Int?

    /// Creates a flow layout.
    ///
    /// - Parameters:
    ///   - alignment: How each line sits across the width, and each member
    ///     within its line (default `.topLeading`).
    ///   - spacing: Blank columns between neighbours on a line, or `nil` (the
    ///     default) for what each pair prefers: one column between two views,
    ///     as in an ``HStackLayout``.
    ///   - lineSpacing: Blank rows between lines, or `nil` (the default) for
    ///     what views prefer between rows: none, as in a ``VStackLayout``.
    public init(alignment: Alignment = .topLeading, spacing: Int? = nil, lineSpacing: Int? = nil) {
        self.alignment = alignment
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    @MainActor public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        let lines = lines(of: subviews, width: proposal.width)
        let widest = lines.map(\.width).max() ?? 0
        return ViewSize(
            width: proposal.width.map { min(widest, $0) } ?? widest,
            height: height(of: lines))
    }

    @MainActor public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.y
        for line in lines(of: subviews, width: bounds.width) {
            let lineX = bounds.x + alignment.horizontal.childOffset(childWidth: line.width, in: bounds.width)
            for member in line.members {
                subviews[member.index].place(
                    at: CellPoint(
                        x: lineX + member.x,
                        y: y + alignment.vertical.childOffset(childHeight: member.size.height, in: line.height)),
                    proposal: ProposedSize(width: member.size.width, height: member.size.height))
            }
            y += line.height + lineGap
        }
    }

    // MARK: - Lines

    /// One line's members, each at its offset from the line's leading edge.
    private struct Line {
        var members: [(index: Int, x: Int, size: ViewSize)] = []
        var width = 0
        var height = 0
        /// The last member that took any width: the one a gap is asked of.
        var lastOccupying: Int?
    }

    /// The subviews packed greedily into lines no wider than `width`, or all
    /// on one when it is `nil`. Both passes go through here, so the size
    /// reported and the arrangement drawn cannot disagree.
    @MainActor private func lines(of subviews: Subviews, width limit: Int?) -> [Line] {
        let gaps = gaps(between: subviews)
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            guard size.width > 0 else {
                // Takes no part in the line's width: no gap, never a break.
                line.members.append((index, line.width, size))
                line.height = max(line.height, size.height)
                continue
            }
            var gap = line.lastOccupying.map { gaps.between($0, index) } ?? 0
            if let limit, line.lastOccupying != nil, line.width + gap + size.width > limit {
                lines.append(line)
                line = Line()
                gap = 0
            }
            if let limit, size.width > limit {
                size = subviews[index].sizeThatFits(ProposedSize(width: limit, height: nil))
            }
            line.members.append((index, line.width + gap, size))
            line.width += gap + size.width
            line.height = max(line.height, size.height)
            line.lastOccupying = index
        }
        if !line.members.isEmpty { lines.append(line) }
        return lines
    }

    /// The lines' heights and the gaps between them.
    @MainActor private func height(of lines: [Line]) -> Int {
        lines.reduce(0) { $0 + $1.height } + lineGap * max(0, lines.count - 1)
    }

    /// The rows between lines in force: the stated ones, or the vertical
    /// distance views prefer.
    @MainActor private var lineGap: Int {
        lineSpacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .vertical)
    }

    /// The gaps between neighbours on a line: ``HStackLayout``'s rule —
    /// every one ``spacing``, or, when it is `nil`, what each pair asks for.
    @MainActor private func gaps(between subviews: Subviews) -> StackGaps {
        let uniform = spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .horizontal)
        guard spacing == nil, subviews.mayStateSpacing else { return StackGaps(uniform: uniform) }
        return StackGaps(uniform: uniform, stating: subviews.children, along: .horizontal, context: subviews.context)
    }
}

// MARK: - Associated types and statics, as the stacks spell them

@MainActor extension FlowLayout: Animatable {
    /// A flow layout recomputes from its subviews and caches nothing.
    public typealias Cache = Void
    /// A flow layout animates nothing of its own.
    public typealias AnimatableData = EmptyAnimatableData

    /// A flow keeps the default guide merge.
    public static var _definesExplicitAlignment: Bool { false }
}

/// A `ForEach` of grid rows is cells under a flow, as under a stack layout,
/// so switching it with `GridLayout` through `AnyLayout` keeps each cell's
/// identity and its `@State`.
@MainActor extension FlowLayout: WholeGridRowExpanding {
    package var expandsWholeGridRows: Bool { true }
}
