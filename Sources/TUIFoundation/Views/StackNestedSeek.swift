//  🖥️ TUI — A Terminal UI framework for Swift
//  StackNestedSeek.swift
//
//  SCROLL-FIT's locate by route (design B-SCROLLFIT-15, A-SCROLLFIT-4 (b)): a
//  `scrollTo` whose key none of a stack's own rows carries — a message in a
//  day's lazy stack, inside an outer lazy stack of days; a row of a lazy
//  stack under a title, sought by the column above it — is searched for below
//  them, level by level, by measuring the rows for the search alone
//  (`ScrollKeyLocate`), rows never built included. The row it is found in is
//  then either handed the seek, when it is pulled (it places its own rows
//  from an anchor, and resolves the seek there), or — drawn whole — drawn for
//  the key's place alone, which the seek then aims at as a line inside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// Where a sought key lies in the row of a container that holds it.
struct NestedSeekTarget {
    /// The row the key lies below.
    let ordinal: Int
    /// The key's view's top in the row's lines, and its height.
    let y: Int
    let height: Int
}

@MainActor
enum NestedSeek {
    /// `context` as a search's measures and drawing see it: measuring, so
    /// nothing below runs an `onAppear` or registers a focusable; with no
    /// render cache, so no memo is read or kept and nothing is filed as
    /// pulled; with no scroll request, so nothing below takes it for its own;
    /// and with `search` in its environment.
    static func searchContext(_ context: RenderContext, search: ScrollKeyLocate) -> RenderContext {
        var environment = context.environment
        environment.renderCache = nil
        environment.scrollKeyLocate = search
        environment.scrollContentWindow = nil
        var searching = context.withEnvironment(environment)
        searching.isMeasuring = true
        return searching
    }

    /// The first of a container's `count` rows below which `key` lies, or
    /// `nil` when none holds it: each row measured for the search
    /// (`_VStackCore.locateSizeThatFits`), a level deeper each time round,
    /// until the key is found or no stack the last round reached had rows
    /// left to look below. A miss costs a measure of every row on every level
    /// there is, once per call; a key one level down, one round over the rows
    /// before its own and two over its own.
    ///
    /// `context` is the container's rows' context: what `child`'s rows are
    /// measured under.
    static func row(
        holding key: String, count: Int, child: (Int) -> ChildView, width: Int, context: RenderContext
    ) -> Int? {
        guard count > 0 else { return nil }
        let search = ScrollKeyLocate(key: key)
        let searching = searchContext(context, search: search)
        let proposal = ProposedViewSize(width: width, height: nil)
        for depth in 0...ScrollKeyLocate.maximumDepth {
            search.depth = depth
            search.hasDeeperRows = false
            for ordinal in 0..<count {
                _ = child(ordinal).measure(proposal: proposal, context: searching)
                if search.found { return ordinal }
            }
            guard search.hasDeeperRows else { return nil }
        }
        return nil
    }

    /// Where `key` lies in `row` drawn whole, `height` lines tall at `width`:
    /// the row drawn for the search, the view the key names marking itself
    /// (``ScrollKeyLocate/marksTarget``). `nil` when the drawing marked none —
    /// the key lies in a view that draws its own rows apart (a nested scroll
    /// view, a list), whose own seek finds it.
    static func place(
        of key: String, in row: ChildView, width: Int, height: Int, context: RenderContext
    ) -> (y: Int, height: Int)? {
        let search = ScrollKeyLocate(key: key)
        search.marksTarget = true
        return row.render(width: width, height: height, context: searchContext(context, search: search))
            .seekTargetLines
    }

    /// The row of a container's whose content holds `key`, and where in it,
    /// for a container that draws that row whole: ``row(holding:count:child:width:context:)``
    /// then ``place(of:in:width:height:context:)``. A row whose drawing marks
    /// no place is aimed at whole.
    static func target(
        holding key: String, count: Int, child: (Int) -> ChildView, width: Int, rowHeight: (Int) -> Int,
        context: RenderContext
    ) -> NestedSeekTarget? {
        guard let ordinal = row(holding: key, count: count, child: child, width: width, context: context)
        else { return nil }
        let height = rowHeight(ordinal)
        let place = place(of: key, in: child(ordinal), width: width, height: height, context: context)
        return NestedSeekTarget(ordinal: ordinal, y: place?.y ?? 0, height: place?.height ?? height)
    }

    /// The viewport line a seek puts its target on: the request's anchor's,
    /// or — minimal movement — the inset edge it is off past, or the line it
    /// is on already, `current`, when it shows whole.
    static func line(for seek: ScrollToRequest, height: Int, current: Int, viewportHeight: Int) -> Int {
        if let anchor = seek.anchor {
            let slack = viewportHeight - seek.topInset - seek.bottomInset - height
            return seek.topInset + Int((Double(slack) * anchor.y).rounded())
        }
        if current < seek.topInset { return seek.topInset }
        let bottom = viewportHeight - seek.bottomInset - height
        if current > bottom { return max(seek.topInset, bottom) }
        return current
    }
}

extension ScrollFillColumn {
    /// Row `ordinal`'s top in lines below the viewport's top (negative above
    /// it), read from the anchor: the rows between summed where the walk
    /// measures across a jump, or they are fewer than a screen of rows, and
    /// at the running pitch past that — where the row is off screen whatever
    /// their heights, on the side its ordinal says.
    func viewportLine(ofRow ordinal: Int, viewportHeight: Int) -> Int {
        let anchored = anchor.ordinal
        let rows = ordinal < anchored ? ordinal..<anchored : anchored..<ordinal
        let lines =
            walksJumps || rows.count <= viewportHeight
            ? rows.reduce(0) { $0 + pitch(of: $1) } : rows.count * estimatedPitch
        return (ordinal < anchored ? -lines : lines) - anchor.within
    }
}

// MARK: - The search's measure

@MainActor extension _VStackCore {
    /// This stack's answer to a search's measure (`ScrollKeyLocate`): the key
    /// looked for among its own rows — by the data's keys, never building a
    /// row — and, while the search may go deeper, below each in turn. Answers
    /// no size: nothing but the search reads it.
    func locateSizeThatFits(_ search: ScrollKeyLocate, proposal: ProposedViewSize, context: RenderContext)
        -> ViewSize
    {
        let children = resolveChildViewCollection(from: content, context: context)
        if children.seekOrdinal(forKey: search.key) != nil {
            search.found = true
            return .zero
        }
        guard !children.isEmpty else { return .zero }
        guard search.depth > 0 else {
            search.hasDeeperRows = true
            return .zero
        }
        search.depth -= 1
        defer { search.depth += 1 }
        let rows = ProposedViewSize(width: proposal.width ?? context.availableWidth, height: nil)
        for ordinal in 0..<children.count {
            _ = children[ordinal].measure(proposal: rows, context: context)
            if search.found { break }
        }
        return .zero
    }
}
