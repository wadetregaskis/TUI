//  🖥️ TUI — A Terminal UI framework for Swift
//  GradientStopsCodec.swift
//
//  A Gradient ⇄ a string, for persisting an editable gradient in @AppStorage.
//  Shared by the ProgressView page's indeterminate-sweep gradient and the
//  track-style editor's fill gradient.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

enum GradientStopsCodec {
    /// Decodes `"3CC8BE@0.000,506EF0@1.000"` to a gradient. Invalid entries
    /// are dropped; NO surviving stop yields `fallback`, so a consumer always
    /// has a drawable gradient.
    ///
    /// One stop is not a failure — it is a solid colour, which the editor's
    /// Gradient switch can produce and every consumer paints. Rejecting it
    /// (this did, at first) silently reverts the switch: the panel writes one
    /// stop, the store hands back the fallback, and the dialog redraws as the
    /// gradient it just stopped being.
    ///
    /// The format is the gradient editor's own (`GradientStopsText`), and a
    /// stop written without a position is read as evenly spaced, so values
    /// stored by the bare-`RRGGBB` format before it migrate by being read.
    ///
    /// The format is colours and positions only. A gradient's colour space is
    /// therefore taken from `fallback`, which is the caller's own default —
    /// storing one would be a third format revision for something no editor
    /// can currently set.
    static func decode(_ raw: String, fallback: Gradient) -> Gradient {
        let stops = GradientStopsText.stops(from: raw)
        // `withStops` on the FALLBACK, not `Gradient(stops:)`: the format
        // stores colours and positions and nothing else, so anything else the
        // gradient carries — its colour space — comes from what the caller
        // offered rather than reverting to the default on every reload.
        return stops.isEmpty ? fallback : fallback.withStops(stops)
    }

    /// Encodes a gradient for storage — the inverse of ``decode(_:fallback:)``.
    static func encode(_ gradient: Gradient) -> String {
        GradientStopsText.text(of: gradient)
    }

    /// A colour as the bare `RRGGBB` ``Color/hex(_:)-(String)`` reads back:
    /// the one place this app turns a `Color` into text, so a store written
    /// here can always be read by whatever reads it.
    static func hex(_ color: Color) -> String {
        GradientStopsText.hex(color)
    }
}
