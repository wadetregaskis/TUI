//  🖥️ TUI — A Terminal UI framework for Swift
//  OpticalReadout.swift
//
//  A read-out centred by its figures: the marks of little visual weight at its
//  ends — a sign before, a degree or percent sign after — hang outside the
//  centred block, as typesetters hang punctuation (the owner, 2026-10-28,
//  afternoon list #32).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A read-out split for optical centring: the marks of little visual weight
/// at its ends, and the figures between, each with its width in cells.
///
/// Centred whole, "-5°" sat a cell left of "5", and the figures jumped as the
/// minus came and went. Centred by its figures, the marks hang either side,
/// and a mark that may come — a minus where the range goes below zero — has
/// its cell kept, so the figures stand still.
struct OpticalReadout: Equatable {
    /// The marks that hang before the figures: signs.
    static let leadingMarks: Set<Character> = ["-", "\u{2212}", "+", "±"]
    /// The marks that hang after them: degrees, percent, primes and per mille.
    static let trailingMarks: Set<Character> = ["%", "°", "′", "″", "‰"]

    let lead: String
    let figures: String
    let trail: String

    /// `text` split at its marks; all of it figures where it is nothing but
    /// marks, so a bare "%" is centred as it is.
    init(_ text: String) {
        let characters = Array(text)
        var start = 0
        while start < characters.count, Self.leadingMarks.contains(characters[start]) { start += 1 }
        var end = characters.count
        while end > start, Self.trailingMarks.contains(characters[end - 1]) { end -= 1 }
        guard start < end else {
            (lead, figures, trail) = ("", text, "")
            return
        }
        lead = String(characters[..<start])
        figures = String(characters[start..<end])
        trail = String(characters[end...])
    }

    var leadWidth: Int { lead.strippedLength }
    var figuresWidth: Int { figures.strippedLength }
    var trailWidth: Int { trail.strippedLength }

    /// The cells it needs, with `reservedLead` kept before the figures for a
    /// mark that may come.
    func width(reservingLead reservedLead: Int) -> Int {
        max(leadWidth, reservedLead) + figuresWidth + trailWidth
    }

    /// The cell it starts at in a space `width` cells wide: its figures centred
    /// there, an odd cell over to their right, and moved as little as its marks
    /// — and `reservedLead` cells for a mark that may come — need to fit.
    func start(in width: Int, reservingLead reservedLead: Int) -> Int {
        let centred = max(0, width - figuresWidth) / 2
        let room = max(leadWidth, reservedLead)
        let figuresStart = max(room, min(centred, width - figuresWidth - trailWidth))
        return max(0, figuresStart - leadWidth)
    }
}
