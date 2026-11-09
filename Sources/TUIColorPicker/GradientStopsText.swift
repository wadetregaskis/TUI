//  🖥️ TUI — A Terminal UI framework for Swift
//  GradientStopsText.swift
//
//  A gradient's stops as text, `RRGGBB@position` joined by commas: how the
//  gradient editor keeps its recents, and how the Example keeps the gradients
//  it edits. `package`, not public: SwiftUI has no such format, and the
//  Example is the only other reader.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIStyling

package enum GradientStopsText {
    /// The stops `text` writes. An entry whose colour does not read is
    /// dropped.
    ///
    /// **A stop written without a position is read as evenly spaced**, which
    /// is what the previous format — bare `RRGGBB` stops, from when a gradient
    /// WAS an even `[Color]` — meant. So stored values migrate by being read,
    /// with no version flag and nothing to convert. So is a position that does
    /// not read, or reads as a NaN or an infinity (`Double("nan")` parses): a
    /// NaN location is a stop the ramp never reaches, every comparison with it
    /// being false, and a gradient that never equals itself.
    package static func stops(from text: some StringProtocol) -> [Gradient.Stop] {
        let fields = text.split(separator: ",")
        var stops: [Gradient.Stop] = []
        for (index, field) in fields.enumerated() {
            let parts = field.split(separator: "@", maxSplits: 1)
            // `first`, not `[0]`: `split` drops empty pieces, so a stop that
            // is only the separator ("@") has NO parts. The colour is stored
            // content read back, not ink a view draws with.
            // swiftlint:disable:next framework_colour_literal
            guard let first = parts.first, let colour = Color.hex(String(first)) else { continue }
            // A lone stop has nowhere to sit, and `index / (count − 1)` would
            // be 0/0 for it.
            let even = fields.count > 1 ? Double(index) / Double(fields.count - 1) : 0
            let parsed = parts.count > 1 ? Double(parts[1]) : nil
            stops.append(Gradient.Stop(color: colour, location: parsed.map { $0.isFinite ? $0 : even } ?? even))
        }
        return stops
    }

    /// `gradient`'s stops as text — the inverse of ``stops(from:)``.
    ///
    /// Positions to three decimals, and always written, even when even: a
    /// reader cannot tell an evenly-spaced gradient from one whose spacing
    /// happens to look even, and the round trip has to be exact.
    package static func text(of gradient: Gradient) -> String {
        gradient.stops.map { hex($0.color) + "@" + Double($0.location).formatted(.fixed(3)) }
            .joined(separator: ",")
    }

    /// A colour as the bare `RRGGBB` ``Color/hex(_:)-(String)`` reads back.
    ///
    /// A colour with no channels to state (a palette role) has no hex, and
    /// black is what the format has always written for one. A terminal slot
    /// is written as the colour the terminal reported for it, or xterm's value
    /// while it has reported none.
    package static func hex(_ color: Color) -> String {
        guard let components = color.estimatedRGB else { return "000000" }
        return [components.red, components.green, components.blue]
            .map { $0.digits(width: 2, radix: 16, uppercase: true) }.joined()
    }
}
