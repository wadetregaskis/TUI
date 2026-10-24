//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LightDarkColor.swift
//
//  A colour with a light and a dark value of its own — an asset catalogue's
//  colour set, a dynamic `NSColor` — kept as two bytes: its place in a
//  process-wide, append-only table of (light, dark) pairs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation  // `NSLock` — stated, not borrowed from a sibling file (SE-0444)

extension Color {
    /// A colour that is one RGB value under a light colour scheme and another
    /// under a dark one, chosen where it is drawn, as SwiftUI chooses an asset
    /// catalogue colour's variant: or `nil` where the two cannot be kept that
    /// way, and the caller chooses one now, as it did before there was a table.
    ///
    /// - The same colour twice is that colour, with no table entry: a colour
    ///   set with one colour, the common case, stays a plain colour.
    /// - Two plain RGB colours (``ColorValue/rgb(red:green:blue:)``) of the
    ///   same alpha become a ``ColorValue/lightDark(_:)`` colour, at that
    ///   alpha. Its pair goes in ``LightDarkColorTable/shared`` (where an equal
    ///   pair already is, it is that entry), so two colours made of the same
    ///   pair are equal however they were made.
    /// - Anything else is `nil`: variants that differ in alpha (the case
    ///   carries one alpha, `Color`'s own), a variant that is not plain RGB (a
    ///   palette role, a terminal slot, a named colour, which already follows
    ///   the scheme by itself), and a pair that does not fit because the table
    ///   is full (``LightDarkColorTable/capacity``).
    ///
    /// A Display P3 or linear colour is plain RGB by the time it is a `Color`:
    /// it was converted to 8-bit sRGB as it was made.
    ///
    /// - Parameters:
    ///   - light: The colour under a light scheme.
    ///   - dark: The colour under a dark scheme.
    ///   - table: The table to keep the pair in: ``LightDarkColorTable/shared``,
    ///     the one every drawn colour reads. Another is for a test of a full
    ///     table, and a colour it makes means nothing outside that test.
    package static func lightDark(
        light: Color, dark: Color, in table: LightDarkColorTable = .shared
    ) -> Color? {
        if light == dark { return light }
        guard light.alpha == dark.alpha,
            case .rgb(let lightRed, let lightGreen, let lightBlue) = light.value,
            case .rgb(let darkRed, let darkGreen, let darkBlue) = dark.value
        else { return nil }
        let pair = LightDarkColorTable.Pair(
            light: .init(red: lightRed, green: lightGreen, blue: lightBlue),
            dark: .init(red: darkRed, green: darkGreen, blue: darkBlue))
        guard let index = table.index(of: pair) else { return nil }
        return Color(value: .lightDark(index), alpha: light.alpha)
    }

    /// Which (light, dark) pair a ``ColorValue/lightDark(_:)`` colour is: its
    /// place in the process-wide table of such pairs (`LightDarkColorTable`).
    ///
    /// Two bytes rather than a `UInt16`: a `UInt16` aligns to two, which would
    /// align ``ColorValue`` to two and give a five-byte `Color` a stride of six
    /// — a padding byte, undefined, in every colour and every `Text`. Two
    /// `UInt8`s are a two-byte payload at alignment one, under `.rgb`'s three,
    /// so `Color` stays five bytes with no padding.
    ///
    /// Only ever a place in the table, which is the process's: never write one
    /// out (a file, a preference, a pasteboard). Another process's table holds
    /// other pairs. Write the colour's components, as everything that saves a
    /// colour does (`estimatedRGB`, the light value).
    public struct LightDarkIndex: Sendable, Hashable {
        let high: UInt8
        let low: UInt8

        /// The place `index` in the table, which must be under 65,536.
        init(_ index: Int) {
            high = UInt8(truncatingIfNeeded: index >> 8)
            low = UInt8(truncatingIfNeeded: index)
        }

        /// The place in the table.
        var index: Int { Int(high) << 8 | Int(low) }

        /// This colour's value under `scheme`, as an opaque RGB colour, as
        /// ``Color/SystemColor/color(in:)`` answers a named colour's.
        package func color(in scheme: ColorScheme) -> Color {
            let pair = LightDarkColorTable.shared.pair(at: self)
            let components = scheme == .dark ? pair.dark : pair.light
            return .rgb(components.red, components.green, components.blue)
        }

        /// The value a view body measures: the light one, as a named
        /// colour's (``Color/SystemColor``).
        var lightComponents: (red: UInt8, green: UInt8, blue: UInt8) {
            let light = LightDarkColorTable.shared.pair(at: self).light
            return (light.red, light.green, light.blue)
        }
    }
}

/// Every (light, dark) pair of RGB values a ``Color/ColorValue/lightDark(_:)``
/// colour has been made of in this process, each at the place its colours
/// carry.
///
/// ## Why a process-wide table, under "No Singletons"
///
/// The owner's ruling B-D6M-1 (option 3, 2026-10-24) and the grant recorded
/// beside CLAUDE.md's rule: a `Color` is five bytes, room for one RGB value
/// and not two, and a colour made in a view body must reach its second value
/// where it is drawn, with no environment to look it up in. So its pair is
/// here, and the colour holds the place. What makes this safe as a
/// process-wide value is that it is an INTERNER, keyed by the value:
///
/// - The key is the pair itself, not a bundle, a catalogue or a name, so
///   equal pairs share one place however and wherever they were made, and
///   every test, bundle and catalogue in the process share the table with no
///   way to disturb one another.
/// - It only grows. A place, once given, holds its pair for the life of the
///   process, so a colour means the same thing on every frame and in every
///   app the process runs.
///
/// Nothing is evicted, so it is bounded by the places a two-byte index has,
/// 65,536 pairs: 6 bytes a pair, plus the dictionary that finds a pair's
/// place, a few megabytes at most. Past that a new pair is not kept, and the
/// colour that would have held it chooses its variant when it is made, as
/// every catalogue colour did before (see ``Color/lightDark(light:dark:in:)``).
///
/// ## Threads
///
/// Colours are made off the main actor too, so the table is behind a lock.
/// Asking for a place takes it once; reading a pair, which only drawing a
/// ``Color/ColorValue/lightDark(_:)`` colour does, takes it once. No other
/// colour reads the table.
package final class LightDarkColorTable: @unchecked Sendable {
    /// One RGB value.
    package struct Components: Hashable, Sendable {
        package let red: UInt8
        package let green: UInt8
        package let blue: UInt8
    }

    /// A colour's two values: under a light colour scheme and a dark one.
    package struct Pair: Hashable, Sendable {
        package let light: Components
        package let dark: Components
    }

    /// The most pairs a two-byte index can name.
    package static let maximumCapacity = 1 << 16

    /// The table every ``Color/ColorValue/lightDark(_:)`` colour is read from.
    package static let shared = LightDarkColorTable(capacity: maximumCapacity)

    /// How many pairs this table keeps: ``maximumCapacity`` for ``shared``,
    /// fewer for a test of what happens when it is full.
    package let capacity: Int

    private let lock = NSLock()
    /// Guarded by `lock`. The pair at each place, in the order they came.
    private var pairs: [Pair] = []
    /// Guarded by `lock`. Each pair's place.
    private var places: [Pair: Int] = [:]

    /// A table that keeps up to `capacity` pairs, at most ``maximumCapacity``.
    package init(capacity: Int) {
        precondition(capacity <= Self.maximumCapacity, "a place is two bytes")
        self.capacity = capacity
    }

    /// The place of `pair`: where it already is, or the next free one; `nil`
    /// once the table is full and `pair` is not in it.
    package func index(of pair: Pair) -> Color.LightDarkIndex? {
        lock.withLock {
            if let place = places[pair] { return Color.LightDarkIndex(place) }
            guard pairs.count < capacity else { return nil }
            pairs.append(pair)
            places[pair] = pairs.count - 1
            return Color.LightDarkIndex(pairs.count - 1)
        }
    }

    /// The pair at `index`. A place this table did not give out is a
    /// programming error (a colour made with another table, in a test, and
    /// drawn).
    package func pair(at index: Color.LightDarkIndex) -> Pair {
        lock.withLock { pairs[index.index] }
    }

    /// How many pairs the table holds.
    package var count: Int {
        lock.withLock { pairs.count }
    }
}
