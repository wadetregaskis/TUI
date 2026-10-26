//  🖥️ TUI — A Terminal UI framework for Swift
//  FieldSurfaceMemo.swift
//
//  A palette's derived field surface, kept by everything the derivation reads.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The field surfaces `Palette.derivedFieldBackground()` has derived, keyed on
/// everything the derivation reads, by value — as `RowFills.ruled` keeps a
/// palette's row fills.
///
/// The derivation is a function of exactly these. The page, the stated chrome
/// tone and the text, as the palette resolves them: `isVisiblySeparate`,
/// `surface(steppedFrom:separation:)` and `surfacesRunLighter` read nothing else
/// of the palette, and the separations, the step and the limit are statics of a
/// protocol extension, not requirements a palette could override. The depth,
/// which `isVisiblySeparate` and `quietest` measure in. And the terminal's
/// report, through what a terminal or ANSI colour measures as. So a key that
/// matches is the same derivation, and a palette that changes a role, a depth
/// pin or a terminal report that moves is a different key — never a stale
/// surface. By value rather than `TerminalColors.generation`, because a
/// task-local pin changes the report without moving the generation.
///
/// A dictionary rather than the last answer alone, so fields under two
/// palettes in one frame — a theme preview — do not thrash it into a silent
/// cliff; cleared past 64 entries as `RowFills`' cache is, since an app has a
/// handful of palettes at one depth.
enum FieldSurfaceMemo {
    /// What a derived field surface is a function of.
    struct Key: Hashable {
        /// The palette's page, resolved.
        let page: Color
        /// The palette's stated chrome tone (`appHeaderBackground`), resolved.
        let stated: Color
        /// The palette's text, resolved: the walk's direction and its
        /// readability guard.
        let text: Color
        let depth: ColorDepth
        let terminal: TerminalColors
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: Color] = [:]

    /// The surface kept for `key`, or `derive`'s answer, kept.
    ///
    /// `derive` runs outside the lock: it is a pure function of `key`, so two
    /// threads deriving the same key at once store the same answer.
    static func surface(for key: Key, derive: () -> Color) -> Color {
        if let known = cacheLock.withLock({ cache[key] }) { return known }
        let answer = derive()
        cacheLock.withLock {
            if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
            cache[key] = answer
        }
        return answer
    }
}
