//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarState+EscapeClaim.swift
//
//  A surface's claim on Escape for the frame — what the status bar calls the
//  key, and that the input chain routes it to the focus first — as a claim
//  with a token, so a surface can tell its own claim from a later one with
//  the same label, made in a pane, so a claim holds only while the focus is
//  where it was made.
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

/// ``StatusBarState/escapeClaimGrabsInput`` set while no claim stood in
/// `pane` (`nil`: on the page), kept for the next claim made there.
struct PendingEscapeClaimFlag {
    let pane: String?
    let grabsInput: Bool
}

extension StatusBarState {
    /// The claim on Escape that stands where the focus is: the claim made in
    /// the pane the focus is in (`FocusManager.activePaneID`), or the page's
    /// while it is on the page — the only claim there is, where no pane is
    /// drawn.
    ///
    /// The page's claim does not stand while the focus is in a pane, nor a
    /// pane's while it is elsewhere: Escape belongs to the pane the reader is
    /// in (A19, owner Q6).
    var activeEscapeClaim: EscapeClaim? {
        guard let pane = focusManager?.activePaneID else { return escapeClaim }
        return paneEscapeClaims[pane]
    }

    /// Whether a claim on Escape stands in the pane rendering now — or on the
    /// page, outside every pane — whether or not the focus is there.
    ///
    /// For a surface that claims Escape only when nothing inside it has
    /// (`NavigationStack`): a claim made in another pane is not one inside it.
    var hasEscapeClaimHere: Bool {
        guard let pane = focusManager?.currentPaneID else { return escapeClaim != nil }
        return paneEscapeClaims[pane] != nil
    }

    /// Claims Escape for the frame under `label` — what setting
    /// ``escapeLabelOverride`` does — in the pane rendering now, and returns
    /// the claim's token, for a surface that renames its claim later in the
    /// frame (``renameEscapeClaim(_:to:)``).
    ///
    /// The claim stands until another is made in its pane, or it is withdrawn,
    /// or the next walk begins. A new claim grabs the input unless it says
    /// otherwise (``escapeClaimGrabsInput``, set after the label or just
    /// before it): it does not inherit a lightweight claim's flag from the
    /// claim it replaced.
    @discardableResult
    func claimEscape(_ label: String) -> Int {
        let token = nextEscapeClaimToken
        nextEscapeClaimToken &+= 1
        var claim = EscapeClaim(label: label, token: token)
        if let pending = takePendingEscapeClaimFlag() { claim.grabsInput = pending }
        setEscapeClaimHere(claim)
        return token
    }

    /// The flag ``escapeClaimGrabsInput`` was set to before a claim was made
    /// in the pane rendering now, if it was — taken, so that only the claim
    /// made next has it.
    private func takePendingEscapeClaimFlag() -> Bool? {
        guard let pending = pendingEscapeClaimFlag, pending.pane == focusManager?.currentPaneID else { return nil }
        pendingEscapeClaimFlag = nil
        return pending.grabsInput
    }

    /// Renames the claim made with `token` — if it is still its pane's claim,
    /// nothing having claimed Escape there or withdrawn the claim since.
    ///
    /// For a presenter that claims Escape before its content draws, and
    /// learns only afterwards what its Escape does: a claim the content made
    /// in between (a list's "clear selection", a popover of its own) stands.
    func renameEscapeClaim(_ token: Int, to label: String) {
        updateEscapeClaimHere { claim in
            if claim.token == token { claim.label = label }
        }
    }

    /// Withdraws whatever claim on Escape stands in the pane rendering now.
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
        setEscapeClaimHere(nil)
        _ = takePendingEscapeClaimFlag()
    }

    /// Replaces the claim of the pane rendering now (the page's, outside
    /// every pane) with `claim`.
    private func setEscapeClaimHere(_ claim: EscapeClaim?) {
        if let pane = focusManager?.currentPaneID {
            paneEscapeClaims[pane] = claim
        } else {
            escapeClaim = claim
        }
    }

    /// Changes the claim of the pane rendering now, if it has one.
    func updateEscapeClaimHere(_ change: (inout EscapeClaim) -> Void) {
        if let pane = focusManager?.currentPaneID {
            guard var claim = paneEscapeClaims[pane] else { return }
            change(&claim)
            paneEscapeClaims[pane] = claim
        } else if var claim = escapeClaim {
            change(&claim)
            escapeClaim = claim
        }
    }
}
