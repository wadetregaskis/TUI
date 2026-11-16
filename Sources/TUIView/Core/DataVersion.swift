//  🖥️ TUI — A Terminal UI framework for Swift
//  DataVersion.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// One token for each run of equal values a view is handed frame after frame —
/// a `Table`'s rows, say — so that a memo keyed by the token compares in O(1)
/// what, keyed by the rows, it compared element by element on every ask.
///
/// A memo keyed by the data itself (an ``AnyEquatableBox`` of the rows) pays
/// a full `==` on every lookup unless the rows it is handed are the very
/// buffer it stored, which `Array`'s `==` answers from the buffer. An app that
/// builds its rows in its body (a sort, a filter) hands a new buffer every
/// frame, and every ask of every memo keyed by them compared all of them:
/// `Table`'s `.fit` widths, asked per `.fit` column by the measure and again by
/// the render, were 7% of `Stress`'s 4,000-row `file-browser` frame; a hugging
/// `List`'s widest row (`_ListCore.widestRowMemoKey`) is asked the same way,
/// and so are a windowed `.columns` form's kept widths
/// (`FormColumnWidths.rowsVersion`).
///
/// Here the rows are compared once against the last value seen, and the token
/// stays the same while they are equal. The newest value is kept in place of
/// the one it equals, so the frame's later asks, handed that same buffer,
/// compare it by `Array`'s identity check rather than element by element. A
/// memo stores the token, which compares by identity: O(1) a lookup, and one
/// compare of the rows for each buffer the view is handed (a hash of them would
/// cost the same walk, and could collide).
///
/// What this is NOT: a hash, or a guess. Equality is the data's own `==`, and
/// any change at all (an edit, an insertion, a removal, a reorder, the same
/// count with other content) mints a new token, so an entry stored under the
/// old one misses. Data that comes back to an earlier value gets a new token
/// too: a miss where a hit was possible, never the reverse.
///
/// Lives with the view's state (one per view identity), not in the render
/// cache whose entries it keys: the writes that sweep those leave it, and an
/// entry that outlives it holds a token no new keeper hands out.
package final class DataVersion {
    /// What a memo stores and compares in place of the data: equal only to
    /// itself. A class, so its identity is the version; an entry holding it
    /// keeps it alive, so no later token can reuse its address.
    package final class Token: Equatable {
        init() {}

        package static func == (lhs: Token, rhs: Token) -> Bool { lhs === rhs }
    }

    /// The last value the token was handed out for.
    private var latest: AnyEquatableBox?
    private var current = Token()

    package init() {}

    /// The token for `data`: the last one when `data` equals the last value
    /// seen, a new one when it does not.
    package func token(for data: AnyEquatableBox) -> Token {
        if latest != data { current = Token() }
        latest = data
        return current
    }
}
