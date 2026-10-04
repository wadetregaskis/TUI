//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineLimitEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - LineLimit

/// How many lines a piece of text may occupy — a *decided* answer, which
/// "unset" is not.
///
/// SwiftUI spells a line limit `Int?`, where `nil` means **unlimited**. That
/// works for a modifier argument but not for a stored value that also has to
/// record whether anybody set one: a cascading `.lineLimit(2)` needs a `Text`
/// to be able to say "no limit for me", and with a bare `Int?` that is the same
/// value as "nobody said", so an inherited limit could never be reset. The two
/// meanings therefore get separate spellings: this type says what the limit IS,
/// and `Optional` around it says whether it was stated.
///
/// The public modifiers still take `Int?`, matching SwiftUI exactly. This is
/// what they store.
///
/// `@frozen`, and every byte of a value written, so the per-pass memos' value
/// hash reads a limit whole — see `Color.ColorValue`, the same bargain.
@frozen
public enum LineLimit: Sendable, Equatable {
    /// No cap — the text occupies as many lines as it needs (or as its
    /// container allows).
    case unlimited

    /// At most `count` lines; the last one absorbs the remainder and is
    /// truncated. Clamped to at least 1 where it is applied, so `.lines(0)`
    /// cannot render a text away entirely.
    ///
    /// `reservesSpace` makes the count a floor as well as a ceiling: the text
    /// occupies exactly that many lines whether or not it needs them. It
    /// travels WITH the count rather than beside it because that is what it
    /// qualifies — a descendant that states a new limit is stating a new
    /// reservation too, and a `Bool` of its own would linger over it.
    case lines(Int, reservesSpace: Bool = false)

    /// At least ``LineRange/minimum`` lines, and at most
    /// ``LineRange/maximum`` — SwiftUI's `lineLimit(_:)` with a range whose
    /// lower bound reserves more than one line. A range that reserves nothing,
    /// or exactly its limit, is one of the cases above.
    case range(LineRange)

    /// The cap as a row count, or `nil` for ``unlimited`` — the form the
    /// wrapping code wants.
    var rowCount: Int? {
        switch self {
        case .unlimited: nil
        case .lines(let count, _): max(1, count)
        case .range(let range): range.maximum.map { max(1, $0) }
        }
    }

    /// The number of lines that must be occupied however short the text is, or
    /// `nil` when it may shrink to fit.
    var reservedLines: Int? {
        switch self {
        case .lines(let count, true): max(1, count)
        case .range(let range): max(1, range.minimum)
        default: nil
        }
    }

    /// Builds a limit from SwiftUI's `Int?` spelling, where `nil` is
    /// *unlimited* rather than *unset*.
    init(_ limit: Int?, reservesSpace: Bool = false) {
        self = limit.map { .lines($0, reservesSpace: reservesSpace) } ?? .unlimited
    }

    /// Builds a limit from a range of lines: the lower bound reserved, the
    /// upper bound a cap.
    init(_ range: ClosedRange<Int>) {
        if range.lowerBound <= 1 {
            self = .lines(range.upperBound)
        } else if range.lowerBound == range.upperBound {
            self = .lines(range.upperBound, reservesSpace: true)
        } else {
            self = .range(LineRange(minimum: range.lowerBound, maximum: range.upperBound))
        }
    }

    /// Builds a limit from a lower bound alone: reserved, with no cap.
    init(_ range: PartialRangeFrom<Int>) {
        self = range.lowerBound <= 1 ? .unlimited : .range(LineRange(minimum: range.lowerBound, maximum: nil))
    }
}

/// A range of lines a ``LineLimit`` allows: a floor and an optional cap.
///
/// Its bounds are held as 32-bit counts, which no line limit outgrows, so a
/// limit is no wider for having a range: a `Text` stores one, and every `Text`
/// would pay for the extra word.
@frozen
public struct LineRange: Sendable, Equatable {
    private let storedMinimum: Int32
    private let storedMaximum: Int32

    /// The lines occupied however short the text is.
    public var minimum: Int { Int(storedMinimum) }

    /// The most lines the text may occupy, or `nil` for no cap.
    public var maximum: Int? { storedMaximum == .max ? nil : Int(storedMaximum) }

    /// A range from `minimum` lines to `maximum`, or upward without a cap where
    /// `maximum` is `nil`. Bounds past what 32 bits count are held at the
    /// largest that fits.
    init(minimum: Int, maximum: Int?) {
        let largest = Int(Int32.max - 1)
        storedMinimum = Int32(min(max(1, minimum), largest))
        storedMaximum = maximum.map { Int32(min(max(1, $0), largest)) } ?? .max
    }
}

// MARK: - Environment key

private struct LineLimitKey: EnvironmentKey {
    /// Unlimited by default, as in SwiftUI: text wraps until something else
    /// stops it.
    static let defaultValue: LineLimit = .unlimited
}

extension EnvironmentValues {
    /// The line limit cascaded by ``View/lineLimit(_:)``, which every ``Text``
    /// below obeys unless it set its own.
    ///
    /// Defaults to ``LineLimit/unlimited``.
    public var lineLimit: LineLimit {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the maximum number of lines text in this subtree may occupy.
    /// Matches SwiftUI's `lineLimit(_:)`.
    ///
    /// ```swift
    /// VStack {
    ///     ForEach(messages) { Text($0.body) }
    /// }
    /// .lineLimit(2)               // every message shows at most two lines
    /// ```
    ///
    /// Pass `nil` for no limit — which, inside a subtree that cascaded one, is
    /// how a branch opts back out:
    ///
    /// ```swift
    /// VStack {
    ///     Text(summary)           // two lines
    ///     Text(detail).lineLimit(nil)   // as many as it needs
    /// }
    /// .lineLimit(2)
    /// ```
    ///
    /// A ``Text``'s own ``Text/lineLimit(_:)`` wins over this for that one
    /// view, exactly as ``Text/truncationMode(_:)`` wins over
    /// ``View/truncationMode(_:)``. Where the text is cut is that separate
    /// choice; this only says how many lines there are.
    ///
    /// A ``Table`` cell's line count is its column's own, whatever the
    /// environment says — see `TableColumn.lineLimit(_:)`.
    ///
    /// - Parameter number: The maximum number of lines, or `nil` for no limit.
    /// - Returns: A view whose descendant text is capped at `number` lines.
    public func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, LineLimit(number))
    }

    /// Caps text in this subtree at `limit` lines, and — when `reservesSpace`
    /// is true — makes it occupy that many whether it needs them or not.
    /// Matches SwiftUI's `lineLimit(_:reservesSpace:)`.
    ///
    /// The reservation is what a list of rows wants. Without it a row whose
    /// subtitle happens to wrap is one line taller than its neighbours, and the
    /// whole column shuffles as the data changes:
    ///
    /// ```swift
    /// ForEach(items) { item in
    ///     VStack(alignment: .leading) {
    ///         Text(item.title)
    ///         Text(item.subtitle).lineLimit(2, reservesSpace: true)
    ///     }
    /// }
    /// ```
    ///
    /// Every row is now the same height, and the short subtitles simply leave a
    /// blank line where the second one would go.
    ///
    /// The floor is honoured only as far as the parent allows: squeezed into
    /// fewer rows than it reserved, the text draws what fits rather than
    /// spilling out of the space it was given.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of lines.
    ///   - reservesSpace: Whether the text also occupies that many lines when
    ///     it is shorter.
    /// - Returns: A view whose descendant text is capped, and optionally
    ///   padded, at `limit` lines.
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        environment(\.lineLimit, LineLimit(limit, reservesSpace: reservesSpace))
    }

    /// Lets text in this subtree occupy between the range's bounds of lines.
    /// Matches SwiftUI's `lineLimit(_:)` with a `ClosedRange`.
    ///
    /// The lower bound is a floor and the upper a cap, as
    /// ``lineLimit(_:reservesSpace:)``'s reservation and limit are. A ``Text``
    /// shorter than the floor keeps the rows anyway; one longer than the cap
    /// is truncated:
    ///
    /// ```swift
    /// Text(item.summary)
    ///     .lineLimit(2...4)
    /// ```
    ///
    /// - Parameter limit: The fewest and the most lines.
    /// - Returns: A view whose descendant text occupies that many lines.
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        environment(\.lineLimit, LineLimit(limit))
    }

    /// Lets text in this subtree occupy at least `limit`'s lower bound of
    /// lines, with no cap. Matches SwiftUI's `lineLimit(_:)` with a
    /// `PartialRangeFrom`.
    ///
    /// - Parameter limit: The fewest lines.
    /// - Returns: A view whose descendant text occupies at least that many
    ///   lines.
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        environment(\.lineLimit, LineLimit(limit))
    }

    /// Caps text in this subtree at `limit`'s upper bound of lines, reserving
    /// none. Matches SwiftUI's `lineLimit(_:)` with a `PartialRangeThrough`,
    /// and means what the `Int` form with the bound does.
    ///
    /// - Parameter limit: The most lines.
    /// - Returns: A view whose descendant text is capped at that many lines.
    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
        environment(\.lineLimit, LineLimit(limit.upperBound))
    }
}

// MARK: - Value Hash

/// A trivial non-generic enum, frozen: every module builds it knowing its
/// layout, so every byte of every value is written. See `_AllBytesDefined`.
extension LineLimit: _AllBytesDefined {}
