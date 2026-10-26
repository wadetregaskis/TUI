//  🖥️ TUI — A Terminal UI framework for Swift
//  StripeFill.swift
//
//  What an alternating row's stripe paints: the accent a step off the rows'
//  ground at truecolour, and the entry nearest that a 256- or 16-colour
//  terminal can draw quietly — or no stripe at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Palette {
    /// What an alternating row's stripe paints over `ground` at `depth`, or `nil`
    /// for no stripe.
    ///
    /// At truecolour, the share of the accent over the ground that sets the
    /// stripe ``ViewConstants/alternatingRowContrast`` off the ground, up to
    /// ``ViewConstants/alternatingRowBackground`` of it — or, where the accent
    /// is too near the ground to get that far, the palette's own step off it
    /// (``lifted(from:)``) — eased off a few points at a time where the text
    /// would fall under the floor in (4) below on it, and none where it falls
    /// under at every share. One step of contrast rather than one share of the
    /// accent: the share set Green's, White's and Pro's stripes 1.4:1 off the
    /// page and Basic's 1.17:1, where a stripe is a quiet guide that has only
    /// to show. A coarser terminal does not draw that colour, it draws
    /// the entry nearest it, and nearest is not good enough for a band under
    /// every other row: measured across the sixteen stated palettes
    /// (`StripeLegibilityTests`), the cube put five palettes' stripe
    /// on the SAME entry as a selected row's fill — every other row reading as
    /// selected — drew Green's and Homebrew's as `#005f00` on black, 2.6:1 off
    /// the page where 1.3:1 was asked for, and left Red's text at 3.5:1; the
    /// sixteen slots drew Red Sands' rows on red.
    ///
    /// So at 256 or 16 colours the stripe is the entry nearest that colour —
    /// at 16, the grey slot nearest it — among those that keep four things
    /// true, measured on the entries the terminal paints. Nearest in CONTRAST
    /// off the ground first, its hue second: the cube's entries are coarse
    /// steps, and the nearest in colour to the stripe put Green's on the
    /// cube 1.23:1 off black and Basic's 1.07:1 off white, where an entry
    /// nearer the step was there to take:
    ///
    /// 1. **It shows**: it is not the ground's own entry.
    /// 2. **It is not a highlight**: it is none of the five row fills
    ///    (``RowFills``) — a selected row, a cursor row at either end of its
    ///    breath, both at once.
    /// 3. **It is quiet**: nearer the ground than a selected row's fill is —
    ///    a stripe is a guide for the eye, and a selection is a statement.
    /// 4. **The text stays readable** on it: at least 4.5:1, or where the
    ///    page itself gives less, four fifths of what the page gives.
    ///
    /// Where no entry is all four, there is no stripe: the rows are as
    /// readable without one, and a stripe that looks like a selection is
    /// worse than none. `nil` too without colour, and where the ground, the
    /// accent or the text cannot be measured — the terminal's own colours
    /// before it has reported them.
    ///
    /// Chosen once per ground, palette colours and depth, and kept.
    package func stripeFill(over ground: Color, at depth: ColorDepth = .current) -> Color? {
        guard depth > .noColor else { return nil }
        let target = steppedStripe(over: ground)
        let text = foreground.spendingAlpha(over: ground)
        // The ACCENT measured too, not only the blend: 15% of a colour the
        // terminal decides is, below half, the ground itself — a fill that
        // measures and shows nothing (Opacity as composition §75).
        guard accent.rgbComponents != nil, let groundRGB = ground.rgbComponents,
            let targetRGB = target.rgbComponents, let textRGB = text.rgbComponents
        else { return nil }
        guard depth < .truecolor else {
            // The accent's share eased off, a few points at a time, until the
            // text clears the floor — on a palette whose text barely clears the
            // page (Violet's surface: 4.49:1 at the full share), a fainter stripe
            // rather than a less readable row.
            let floor = StripeKey.readableFloor(text: textRGB, ground: groundRGB)
            for share in stride(from: 1.0, to: 0.0, by: -0.2) {
                let stripe = share == 1 ? target : target.opacity(share, over: ground)
                guard let rgb = stripe.rgbComponents else { return nil }
                if StripeKey.contrast(StripeKey.packed(textRGB), StripeKey.packed(rgb)) >= floor { return stripe }
            }
            return nil
        }
        let table = depth < .palette256 ? RowFills.reportedTable() : nil
        let fills = rowFills(at: depth, over: ground == background ? nil : ground)
        let key = StripeKey(
            ground: StripeKey.packed(groundRGB), target: StripeKey.packed(targetRGB),
            text: StripeKey.packed(textRGB), depth: depth, table: table,
            fills: fills.map { [$0.selection, $0.focusDim, $0.focusBright, $0.emphasisDim, $0.emphasisBright] })
        return StripeKey.chosen(key)
    }

    /// The stripe asked for over `ground`, before a terminal's palette or the
    /// text has a say: the share of the accent that sets it
    /// ``ViewConstants/alternatingRowContrast`` off the ground, found by
    /// halving — the contrast grows with the share — up to
    /// ``ViewConstants/alternatingRowBackground``; or the palette's step off
    /// the ground, where even that much of the accent stays nearer it.
    func steppedStripe(over ground: Color) -> Color {
        let step = ViewConstants.alternatingRowContrast
        let most = accent.opacity(ViewConstants.alternatingRowBackground, over: ground)
        if most.contrastRatio(against: ground) >= step {
            return Self.share(of: accent, upTo: ViewConstants.alternatingRowBackground, over: ground, reaching: step)
        }
        // The palette's own step off the ground, as far toward it as the step
        // asks, or all of it where it stops short; the accent's most, where
        // that is the further of the two.
        let lifted = lifted(from: ground).resolve(with: self)
        guard lifted.contrastRatio(against: ground) > most.contrastRatio(against: ground) else { return most }
        guard lifted.contrastRatio(against: ground) > step else { return lifted }
        return Self.share(of: lifted, upTo: 1, over: ground, reaching: step)
    }

    /// The share of `colour` over `ground`, up to `most`, that sets it `step`
    /// off the ground, found by halving: the contrast grows with the share.
    private static func share(of colour: Color, upTo most: Double, over ground: Color, reaching step: Double) -> Color {
        var (low, high) = (0.0, most)
        for _ in 0..<12 {
            let share = (low + high) / 2
            if colour.opacity(share, over: ground).contrastRatio(against: ground) < step {
                low = share
            } else {
                high = share
            }
        }
        return colour.opacity(high, over: ground)
    }
}

/// What a coarse terminal's stripe depends on, and the choice itself.
private struct StripeKey: Hashable {
    let ground: UInt32
    let target: UInt32
    let text: UInt32
    let depth: ColorDepth
    /// The sixteen slots the terminal paints, at 16 colours.
    let table: [UInt32]?
    /// S, F's two ends and B's two ends, as ``RowFills`` places them here.
    let fills: [Color]?

    static func packed(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> UInt32 {
        UInt32(rgb.red) << 16 | UInt32(rgb.green) << 8 | UInt32(rgb.blue)
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [Self: Color?] = [:]

    /// The stripe for `key`, chosen once and kept.
    static func chosen(_ key: Self) -> Color? {
        if let known = cacheLock.withLock({ cache[key] }) { return known }
        let answer = key.choose()
        cacheLock.withLock {
            // A backstop against unbounded growth, as `RowFills.ruled`'s has.
            if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
            cache[key] = .some(answer)
        }
        return answer
    }

    /// An entry the terminal paints, as the colour that spells it and its RGB.
    private typealias Entry = (colour: Color, rgb: UInt32)

    /// The entries this depth offers: the cube and the grey ramp at 256 colours
    /// (the sixteen slots below them are the terminal's to choose), and at 16
    /// the four greys — every other slot is a saturated hue, and a band of
    /// yellow or blue under every other row is anything but quiet, however
    /// near the page its luminance (measured: the nearest slot by distance
    /// alone striped Basic's white page in bright yellow and Amber's surface
    /// in blue).
    private var entries: [Entry] {
        if let table {
            return [ANSIColor.black, .brightBlack, .white, .brightWhite].compactMap { slot in
                let index = Int(slot.rawValue)
                return index < table.count ? (Color.ansi(slot), table[index]) : nil
            }
        }
        return (16...255).compactMap { index in
            let colour = Color.palette256(UInt8(index))
            return colour.rgbComponents.map { (colour, Self.packed($0)) }
        }
    }

    /// The entry `rgb` is drawn as at this depth.
    private func shown(_ rgb: UInt32) -> UInt32? {
        shown(Self.colour(rgb))
    }

    private func shown(_ colour: Color) -> UInt32? {
        if let table {
            guard case .ansi(let slot) = colour.downsampledToANSI16().value else { return nil }
            let index = Int(slot.rawValue)
            return index < table.count ? table[index] : nil
        }
        return colour.downsampledToPalette256().rgbComponents.map(Self.packed)
    }

    private func choose() -> Color? {
        guard let ground = shown(ground), let text = shown(text) else { return nil }
        let highlights = Set((fills ?? []).compactMap(shown))
        let selection = fills.flatMap { $0.first }.flatMap(shown)
        let quietest = selection.map { Self.contrast($0, ground) } ?? 1.5
        let readable = min(4.5, 0.8 * Self.contrast(text, ground))
        // (The floor as ``readableFloor(text:ground:)`` states it, on the
        // entries painted rather than the colours asked for.)
        let candidates = entries.filter { entry in
            entry.rgb != ground && !highlights.contains(entry.rgb)
                && Self.contrast(entry.rgb, ground) < quietest
                && Self.contrast(text, entry.rgb) >= readable
        }
        // Nearest the step in contrast off the ground — by ratio, so a step
        // too far and one too short weigh the same — and near the stripe
        // asked for in colour, the two weighed together: by contrast alone a
        // cube entry of any hue at the right step won (Red's stripe came out
        // blue, Novel's bright green), and by colour alone the nearest entry
        // could be a long step off the ground (Green's on the cube, 1.23:1).
        // Two thousandths of the ratio's log per unit of sRGB distance: an
        // entry 0.03 nearer the step in log ratio loses to one 15 units
        // nearer the stripe asked for.
        //
        // The step itself, off the ground as painted — not the stripe asked
        // for, measured against it: the painted ground can be a step darker
        // than the ground the stripe was asked over (Green's 050a05 is drawn
        // black), which made the asked stripe read 1.23:1 off it.
        let step = log(ViewConstants.alternatingRowContrast)
        func score(_ entry: Entry) -> Double {
            abs(log(Self.contrast(entry.rgb, ground)) - step)
                + 0.002 * Double(Self.distance(entry.rgb, target)).squareRoot()
        }
        return candidates.min { score($0) < score($1) }?.colour
    }

    /// Squared distance between two colours in sRGB.
    private static func distance(_ first: UInt32, _ second: UInt32) -> Int {
        var total = 0
        for shift: UInt32 in [0, 8, 16] {
            let firstChannel: UInt32 = (first >> shift) & 0xFF
            let secondChannel: UInt32 = (second >> shift) & 0xFF
            let delta = Int(firstChannel) - Int(secondChannel)
            total += delta * delta
        }
        return total
    }

    /// The least contrast the text keeps on a stripe: 4.5:1, or where the
    /// ground itself gives less, four fifths of what it gives.
    static func readableFloor(
        text: (red: UInt8, green: UInt8, blue: UInt8), ground: (red: UInt8, green: UInt8, blue: UInt8)
    ) -> Double {
        min(4.5, 0.8 * contrast(packed(text), packed(ground)))
    }

    /// The WCAG contrast ratio between two packed colours — ``Color/contrastRatio(against:)``'s,
    /// on the colours they spell.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        colour(first).contrastRatio(against: colour(second))
    }

    /// The colour `packed` spells, as 0xRRGGBB.
    private static func colour(_ packed: UInt32) -> Color {
        let byte: UInt32 = 0xFF
        return .rgb(UInt8(packed >> 16 & byte), UInt8(packed >> 8 & byte), UInt8(packed & byte))
    }
}
