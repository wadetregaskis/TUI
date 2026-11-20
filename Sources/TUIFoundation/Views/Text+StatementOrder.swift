//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+StatementOrder.swift
//
//  Which of two statements of one kind a `Text`'s own modifiers keep: the one
//  written first, as SwiftUI's do.
//
//  Created by Wade Tregaskis
//  License: MIT

// SwiftUI's rule, measured (macOS 15.8.3,
// `Tools/SwiftUIProbes/Text foregroundStyle levels (TXTFG)/stacked.swift`): a
// `Text`'s own modifiers nest as view modifiers do, the one written first
// nearest the text, so of two of one kind the FIRST written wins —
// `Text("x").foregroundStyle(.red).foregroundStyle(.blue)` is red,
// `.font(.title).font(.caption)` a title, `.bold(false).bold(true)` not bold —
// and a later one fills in only what no earlier one said. The same holds for
// the `View` modifiers TUI also declares on `Text` (`lineLimit`,
// `truncationMode`): there the nearer environment value wins.
//
// The one modifier that keeps the LAST is `customAttribute(_:)`, measured
// too: SwiftUI's renderer reads the outermost attribute of a type, a whole
// concatenation's over a fragment's own (`Text+CustomAttribute.swift`).
//
// Where two kinds meet — a level and a colour, a bold and a weight — the
// earlier one applies to the result of the later, as a nearer modifier applies
// to what the farther one gave it. Each method below says how.
//
// Framework code that restyles a `Text` on purpose, over what it states, sets
// the style directly (`text.style.… =`) or merges a style over it
// (`TextStyle.merged(over:)`), never through these.

extension TextStyle {
    /// `bold(isActive)` written after what this style states.
    ///
    /// A bold stated before, or any weight, wins: `fontWeight(.light).bold()`
    /// is light, and after `fontWeight(nil)` a bold is the font's own weight's
    /// business (both measured).
    mutating func stateBold(_ isActive: Bool) {
        guard isBold == nil, !weightIsFonts else { return }
        isBold = isActive
    }

    /// `fontWeight(weight)` written after what this style states.
    ///
    /// A weight stated before wins. A bold stated before applies to this
    /// weight, as SwiftUI's `bold()` applies to the weight below it (measured):
    /// `bold()` makes a regular or heavy weight bold and leaves a light one
    /// light, and `bold(false)` leaves a light weight light and makes any
    /// other regular. A `dim(_:)` stated before keeps its say on the faint
    /// attribute. A `nil` weight states the font's own (``weightIsFonts``).
    ///
    /// A weight always states the faint attribute, on or off, which is how a
    /// later one knows a weight was stated; only ``Text/dim(_:)`` states it
    /// alone, and a weight after that still states the bold.
    mutating func stateWeight(_ weight: FontWeight?) {
        guard !weightIsFonts else { return }
        guard let attributes = weight?.styleAttributes else {
            // Both said is a weight (or a bold and a dim, which says as much).
            if isBold == nil || isDim == nil { weightIsFonts = true }
            return
        }
        let light = attributes.dim == true
        guard isDim == nil else {
            // A weight or a `dim(_:)` came first. Only the latter leaves the
            // bold unsaid, and only that is filled in here.
            if isBold == nil { isBold = attributes.bold == true }
            return
        }
        isBold = isBold.map { $0 && !light } ?? (attributes.bold == true)
        isDim = light
    }

    /// `dim(isActive)` written after what this style states: a faint
    /// attribute stated before, by `dim(_:)` or a weight, wins.
    mutating func stateDim(_ isActive: Bool) {
        guard isDim == nil else { return }
        isDim = isActive
    }
}
