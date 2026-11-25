//  🖥️ TUI — A Terminal UI framework for Swift
//  SGRState+Writes.swift
//
//  What a run of SGR escapes wrote that the state it leaves cannot show, and
//  the style a cut carries across it: the run netted, not replayed.
//
//  Created by Wade Tregaskis
//  License: MIT

extension SGRState {

    /// What a run of SGR codes wrote that the state they leave cannot show:
    /// whether a reset was among them, and which slots their codes turned OFF
    /// since the last one.
    ///
    /// The state says what is on. From a default terminal that is everything,
    /// but bytes are rarely written to one: a painter puts its own fill back
    /// after every reset (`ANSIRenderer.restating(_:afterResetsIn:)`), and a
    /// cut is drawn after whatever its row drew before it. There a `22` turns
    /// off a bold the run never turned on, a stated `ESC[49m` takes away a fill
    /// a reset would have had put back, and a reset is not the same as no
    /// reset. Kept beside the state, these say all of that, and the two
    /// together are the run's whole effect on any terminal (``CarriedStyle``).
    struct Writes: Equatable {
        /// Whether the codes held a reset. The fields below then count only
        /// the codes after the last one.
        var reset = false
        /// The attributes (bit `n` for attribute `n`) whose last write was an
        /// off-code: never one in force.
        var attributes: UInt16 = 0
        /// Whether the last write to each colour was its default code: 39, 49
        /// or 59.
        var foreground = false
        var background = false
        var underlineColour = false
    }
}

/// The styling a run of SGR escapes establishes, netted: what a cut through a
/// row carries onto its far side in place of every escape before it.
///
/// A slice of a row starts with the styling in force at its first column, and
/// that used to be every SGR escape the columns before it held, one after
/// another. Correct, and quadratic where it counts: a gradient background cuts
/// a row into a run per column, and a row whose content changes colour per
/// cell then carried about W²/2 escapes (CORE1-6) — 137 KB for one 120-cell
/// row, to be netted away again by the writer. `SGRState`'s header records the
/// same defect, a megabyte for one row, in `insertOverlay`.
///
/// Netted, the prefix is a handful of codes. It does to any terminal state
/// what the escapes did, and not only to a default one: a reset among them is
/// stated as one (a painter restates its fill after it), and each slot whose
/// last write was an off-code is turned off (`22`, `39`, `49` …), since the
/// state they leave holds nothing to say so (``SGRState/Writes``).
/// `ANSIRunSlicingStateTests` pins that from several prior states, with
/// several fills restated after resets, against the history it replaces.
struct CarriedStyle {
    private var state = SGRState()
    private var writes = SGRState.Writes()
    /// The prefix as last spelled, until an escape changes it: most cuts of a
    /// row come between the same escapes, and spelling one builds a string.
    private var spelled: String? = ""

    /// Folds an SGR escape the walk has passed.
    mutating func note(_ sequence: String) {
        state.apply(sequence, noting: &writes)
        spelled = nil
    }

    /// One escape that leaves a terminal styled as the noted escapes left it,
    /// or the empty string when they did nothing.
    mutating func prefix() -> String {
        if let spelled { return spelled }
        let result = Self.spell(state, writes)
        spelled = result
        return result
    }

    private static func spell(_ state: SGRState, _ writes: SGRState.Writes) -> String {
        var codes = writes.reset ? "0" : ""
        func add(_ code: String) {
            if !codes.isEmpty { codes += ";" }
            codes += code
        }
        let off = writes.attributes
        func wentOff(_ attribute: Int) -> Bool { off & (1 << UInt16(attribute)) != 0 }
        // 22 turns off bold and faint together. A faint that went off went with
        // it, and a bold then either went too or came back on, which the state
        // states after this. A bold that went off on its own, with faint never
        // written, was a 21: 22 would take a faint the run never touched.
        if wentOff(2) || (wentOff(1) && state.isOn(2)) {
            add("22")
        } else if wentOff(1) {
            add("21")
        }
        if wentOff(3) { add("23") }
        if wentOff(4) { add("24") }
        if wentOff(5) || wentOff(6) { add("25") }
        if wentOff(7) { add("27") }
        if wentOff(8) { add("28") }
        if wentOff(9) { add("29") }
        if writes.foreground { add("39") }
        if writes.background { add("49") }
        if writes.underlineColour { add("59") }
        if !state.isDefault { add(state.parameters) }
        return codes.isEmpty ? "" : "\u{1B}[" + codes + "m"
    }
}
