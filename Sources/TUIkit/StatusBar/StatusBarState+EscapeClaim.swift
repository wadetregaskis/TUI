//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarState+EscapeClaim.swift
//
//  A surface's claim on Escape for the frame — what the status bar calls the
//  key, and that the input chain routes it to the focus first — as a claim
//  with a token, so a surface can tell its own claim from a later one with
//  the same label.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One surface's claim on Escape for the frame: the label the bar shows the
/// key under (``StatusBarState/escapeLabelOverride``), whether it grabs the
/// input as a modal does (``StatusBarState/escapeClaimGrabsInput``), and the
/// token the claim was made with.
///
/// The token is what makes a claim a surface's OWN. Two claims can carry one
/// label — a popover presented inside a popover writes the same localized
/// "close popover" as the one around it — so a label says nothing about who
/// wrote it, and an outer popover that renamed "its" claim once its content
/// had drawn renamed the inner one's.
struct EscapeClaim {
    var label: String
    var grabsInput = true
    let token: Int
}

extension StatusBarState {
    /// Claims Escape for the frame under `label` — what setting
    /// ``escapeLabelOverride`` does — and returns the claim's token, for a
    /// surface that renames its claim later in the frame
    /// (``renameEscapeClaim(_:to:)``).
    ///
    /// The claim stands until another is made, or it is withdrawn, or the
    /// next walk begins. A new claim grabs the input unless it says otherwise
    /// (``escapeClaimGrabsInput``): it does not inherit a lightweight claim's
    /// flag from the claim it replaced.
    @discardableResult
    func claimEscape(_ label: String) -> Int {
        let token = nextEscapeClaimToken
        nextEscapeClaimToken &+= 1
        escapeClaim = EscapeClaim(label: label, token: token)
        return token
    }

    /// Renames the claim made with `token` — if it is still the frame's
    /// claim, nothing having claimed Escape or withdrawn the claim since.
    ///
    /// For a presenter that claims Escape before its content draws, and
    /// learns only afterwards what its Escape does: a claim the content made
    /// in between (a list's "clear selection", a popover of its own) stands.
    func renameEscapeClaim(_ token: Int, to label: String) {
        guard escapeClaim?.token == token else { return }
        escapeClaim?.label = label
    }

    /// Withdraws whatever claim on Escape stands.
    ///
    /// For a surface that takes the keyboard and names its Escape on an item
    /// of its own section — a sheet, an alert. A claim made before it in the
    /// walk was made outside it, by a surface it now covers: a popover the
    /// sheet was presented from, a `NavigationStack` beside the view that
    /// presented it. Left standing, the bar showed that surface's name for a
    /// key that closes the sheet (the status bar skips every Escape item while
    /// a claim stands) — or, with its dismissal disabled, for a key that does
    /// nothing at all. Anything inside it renders later, and claims again.
    func withdrawEscapeClaim() {
        escapeClaim = nil
    }
}
