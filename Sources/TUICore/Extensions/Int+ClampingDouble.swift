//  🖥️ TUI — A Terminal UI framework for Swift
//  Int+ClampingDouble.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension Int {
    /// `Int(value)` that cannot trap.
    ///
    /// This is NOT `Int(_: Double)`, which traps — in release builds too — on
    /// NaN, on either infinity, and on any magnitude past `Int`'s range; nor
    /// `Int(exactly:)`, which answers `nil` for anything fractional. It is the
    /// floating-point twin of the integer `Int(clamping:)`: a magnitude past
    /// either bound lands ON that bound, NaN — which has no order and so no
    /// nearer bound — lands on zero, and everything else truncates toward zero
    /// exactly as `Int(_:)` does.
    ///
    /// Round first when rounding is wanted: `Int(clamping: x.rounded())`. The
    /// hand-written shape this replaces, `Int(min(hi, max(lo, x)))`, is only
    /// safe once `x` is known finite — `max(lo, .nan)` is `lo` in Swift, but
    /// `Int(.infinity)` still traps — and every site that spelled it out had to
    /// remember the `isFinite` guard as well. Several did not; a zoom factor, a
    /// cell aspect and a tone-curve point each reached a trap this way.
    ///
    /// - Parameter value: Any `Double`, including the ones `Int(_:)` refuses.
    @inlinable
    public init(clamping value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= Double(Self.max) {
            // `Double(Int.max)` rounds UP to 2^63, one past the largest `Int`,
            // so `>=` is exactly the set `Int(_:)` rejects on this side.
            self = .max
        } else if value <= Double(Self.min) {
            self = .min
        } else {
            self = Int(value)  // The three arms above took every value it refuses.
        }
    }

    /// The most cells, either way, ``init(cells:)`` answers: 2^30, past every
    /// screen and every scrolled document, and far enough inside `Int` (a
    /// 32-bit one too: wasm32) that adding a screen's origin or inset to it
    /// cannot overflow.
    @usableFromInline package static let cellReach = 1 << 30

    /// `value` as a distance in whole cells that arithmetic can go on to use:
    /// ``init(clamping:)`` held to ±``cellReach``.
    ///
    /// NOT `Int(clamping:)` alone, where the next line adds to it. That one
    /// lands an infinity on `Int.max`, and `origin + Int.max` traps as surely
    /// as the conversion did. A share of an extent an app's `UnitPoint` names
    /// (`anchor.x * width`, with an anchor that is `1 / 0`), a guide a closure
    /// computed, an offset an animation overshot to: each is added to a
    /// position straight away, so each is held here, where NaN is no distance.
    ///
    /// Round first when rounding is wanted, as with `Int(clamping:)`.
    ///
    /// - Parameter value: Any `Double`.
    @inlinable
    package init(cells value: Double) {
        // NaN first: in this argument order `max(.nan, -reach)` is NaN, and
        // `Int(.nan)` traps.
        let reach = Double(Self.cellReach)
        self = value.isNaN ? 0 : Int(Swift.min(Swift.max(value, -reach), reach))
    }
}

extension Int64 {
    /// `Int64(value)` that cannot trap: the 64-bit twin of
    /// `Int(clamping: Double)`, for counts that must not narrow where `Int`
    /// is 32 bits (wasm32) — nanoseconds, and seconds past 2038.
    ///
    /// NaN lands on zero, a magnitude past either bound on that bound, and
    /// everything else truncates toward zero as `Int64(_:)` does.
    ///
    /// - Parameter value: Any `Double`.
    @inlinable
    public init(clamping value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= Double(Self.max) {
            // `Double(Int64.max)` is 2^63, one past the largest `Int64`.
            self = .max
        } else if value <= Double(Self.min) {
            self = .min
        } else {
            self = Int64(value)  // The three arms above took every value it refuses.
        }
    }
}
