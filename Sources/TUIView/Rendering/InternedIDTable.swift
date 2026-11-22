//  🖥️ TUI — A Terminal UI framework for Swift
//  InternedIDTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Interned ID Table

/// A table of ids interned per view identity, pruned along with the render
/// cache.
///
/// One implementor: the mouse event dispatcher, which mints a handler id per
/// `(identity, slot)` so a control keeps its own id from frame to frame instead
/// of taking whatever number its position in the walk left it.
///
/// Such a table has to live exactly as long as the cache entries that can serve
/// a buffer carrying its ids. A `FrameBuffer` stores its hit-test regions with
/// the ids baked in, so a cached buffer served again needs its control's id to
/// still mean that control — and an id dropped while such an entry survives
/// would leave the served regions pointing at a handler no one registers.
/// ``RenderCache/removeInactive()`` therefore prunes this table with the same
/// retention rule it prunes itself by, rather than the table guessing from its
/// own frame counting.
///
/// A class, and held weakly by the cache: the dispatcher owns itself, and its
/// `TUIContext` owns both.
package protocol InternedIDTable: AnyObject {
    /// Drops every interned id whose identity neither asked for it since the
    /// last prune nor is retained.
    ///
    /// - Parameter isRetained: Whether the cache still holds this identity,
    ///   even though nothing at it may have been visited this pass: marked
    ///   active (a memo served AT it), or under a cached subtree served this
    ///   pass (the cache's own ``RetainedSubtreeIndex`` question).
    func pruneInternedIDs(retaining isRetained: (ViewIdentity) -> Bool)
}
