//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersSupport.swift
//
//  The values and the renderer the hostile-number suites share: every public
//  API that takes a number is handed NaN, both infinities, a negative, zero
//  and numbers far past any terminal (1e18), and must draw something —
//  anything — without trapping or hanging. A trap here is the bug class
//  `Int(Double.nan)`, `0..<negative`, `String(repeating:count: -1)`, an
//  `Int` overflow: one stray number from an app's arithmetic took the whole
//  process down.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

/// The hostile values each suite runs its APIs over.
///
/// A length past every screen is HELD, to `Int.statedLengthLimit` (2^16)
/// cells, not cut to the screen: a fixed frame is drawn at its size, and
/// scroll content can be that long. So the suites state a huge length along
/// ONE axis at a time. Along both, `.frame(width: .max, height: .max)` is a
/// picture of 2^32 cells — an allocation no clamp short of the screen can
/// make small, not an arithmetic trap.
enum Hostile {
    /// Every floating-point value an API must survive: not a number, both
    /// infinities, a negative, zero, and numbers far beyond a screen.
    static let doubles: [Double] = [.nan, .infinity, -.infinity, -1, 0, 1e-300, 1e18, -1e18]

    /// Every integer an API must survive: a negative, zero, and numbers far
    /// beyond a screen, out to the type's own ends.
    static let ints: [Int] = [-1, 0, -1_000_000_000_000_000_000, 1_000_000_000_000_000_000, .max, .min]

    /// The sizes each view is drawn at: an ordinary one, and the two smallest,
    /// where every subtraction of chrome goes negative.
    static let sizes: [(width: Int, height: Int)] = [(40, 10), (1, 1), (0, 0)]
}

/// Draws `view` at every hostile size, two frames each, through the whole
/// frame the run loop draws, opacity resolved as the screen shows it — what a
/// hostile number has to get through without trapping.
///
/// - Parameters:
///   - configure: Changes each harness's root environment first.
///   - transaction: The transaction every frame is drawn under.
///   - nows: The frame instants drawn, in nanoseconds.
///   - view: Builds the view for the frame at each instant's index.
@MainActor
func drawHostile<V: View>(
    configure: (inout EnvironmentValues) -> Void = { _ in },
    transaction: Transaction? = nil,
    nows: [Int64] = [0, 16_666_667],
    _ view: (Int) -> V
) {
    for size in Hostile.sizes {
        let harness = InputChainHarness(width: size.width, height: size.height, configure: configure)
        if let transaction { harness.transaction = transaction }
        let palette = harness.context.environment.palette
        for (index, now) in nows.enumerated() {
            harness.now = now
            let buffer = harness.frame(view(index))
            _ = buffer.resolvingOpacity(surface: palette.background, palette: palette)
        }
    }
}

/// Draws `view` once at every hostile size, as ``drawHostile(configure:transaction:nows:_:)``
/// does. One frame: a held length is drawn at its full 2^16 cells, and a
/// second frame of it doubles the suite's time to find the same traps.
@MainActor
func drawHostile<V: View>(_ view: @autoclosure () -> V) {
    drawHostile(nows: [0]) { _ in view() }
}
