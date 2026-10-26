//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+Headroom.swift
//
//  SwiftUI's HDR headroom annotation, on a medium with no HDR.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Color {
    /// Creates a new color with specified HDR content headroom — mirrors
    /// SwiftUI's `headroom(_:)`.
    ///
    /// SwiftUI uses the headroom to ask the display for more brightness, and
    /// to tone-map the colour where the display cannot give it. A terminal is
    /// a standard-dynamic-range display with nothing to ask: every escape it
    /// takes is 8-bit sRGB (no terminal protocol carries headroom; Ghostty's
    /// colour specifications, the widest, are SDR too). So whatever headroom
    /// is asked for, the display's — none — is the one available, and the
    /// colour comes back unchanged.
    ///
    /// Unchanged means as TUI made it, which is in SDR already: a component
    /// outside 0…1 was clamped when the colour was created, rather than
    /// tone-mapped as SwiftUI would map it to an SDR display. A colour meant to
    /// be brighter than white draws as the brightest the terminal has.
    ///
    /// SwiftUI's other HDR API — `Color.ResolvedHDR`, `resolveHDR(in:)` and
    /// `exposureAdjust(_:)` — is not offered, since each would have to pretend
    /// to a range no terminal draws (`parity-map.json`, decisions A16).
    ///
    /// - Parameter headroom: The headroom value to associate with the new
    ///   color. Not stored: nothing a terminal draws could read it.
    /// - Returns: This color.
    public func headroom(_ headroom: Double?) -> Color {
        self
    }
}
