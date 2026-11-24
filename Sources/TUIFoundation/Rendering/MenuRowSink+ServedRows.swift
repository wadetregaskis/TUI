//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuRowSink+ServedRows.swift
//
//  An open pop-up menu's rows served from the row memo, as a `List`'s are.
//
//  A row of a `ForEach` is memoized by its element (`_MemoizedRow`), but a
//  menu's row used to decline every memo: its drawing shows two things that
//  are no part of its element, the ordinal it claims (named in its hit-test
//  region) and whether it is the highlighted row, and its claim is a
//  registration the next frame needs. So a Down in a menu of 500 rows drew
//  all 500 (H-92b, CHROME-10). Now the claim is a registration a memo makes
//  again (`EffectJournal`), and the two things the drawing shows are kept
//  right by the menu around the rows:
//
//  - The highlight is the row's own value, which changes for two rows when it
//    moves: the one it leaves and the one it lands on. The column drops their
//    stored drawings before it draws (``MenuPopupController/forgetRowsChangingHighlight(in:)``),
//    as an `EnvironmentModifier` drops what is below it when its value
//    changes; every other row is served.
//  - A served row's claim says what it was drawn as, and the column checks it
//    against what the row is this pass: the ordinal it claims now, and
//    whether that is the highlighted one. A row drawn as it no longer is — the
//    rows above it changed, so its ordinal moved; the keyboard opened the menu
//    and it is the first row to light — makes the column draw again, its walk
//    put back first, with the rows that were stale dropped
//    (``drawMenuColumn(_:context:controller:)``). Rare: a Down, an Up or a type select never needs it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension MenuRowSink {
    /// The journal's name for a row's claim.
    static let claimKind = EffectJournal.Kind("menuRowClaim")

    /// Records the claim a row just made — `ordinal`, `action`, `isEnabled`,
    /// drawn highlighted or not (`isLit`) — for a memo around the row to make
    /// again on every frame it serves the row's drawing.
    ///
    /// A row of a sink that does not serve rows, or one opening a submenu
    /// (whose submenu is drawn in this frame's context, which a served row's
    /// claim would carry from the frame that drew it), declines every memo
    /// instead, as every menu row did before.
    func recordClaim(
        ordinal: Int, isLit: Bool, action: @escaping () -> Void, isEnabled: Bool, opensSubmenu: Bool,
        context: RenderContext
    ) {
        let tracker = context.environment.volatileReadTracker
        guard servesRows, !opensSubmenu else {
            tracker?.recordRenderSideEffect()
            return
        }
        tracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let identity = context.identity
        journal.append(
            EffectJournal.Entry(kind: Self.claimKind, channelToken: context.environment.keyChannelToken) { served in
                served.environment.menuRowSink?.replayClaim(
                    ServedClaim(
                        identity: identity, ordinal: ordinal, isLit: isLit, action: action, isEnabled: isEnabled),
                    highlighted: served.environment.menuHighlightedOrdinal)
            })
    }

    /// A served row's claim, as the row made it when it was drawn.
    struct ServedClaim {
        let identity: ViewIdentity
        let ordinal: Int
        let isLit: Bool
        let action: () -> Void
        let isEnabled: Bool
    }

    /// Makes a served row's claim again, this pass, with `highlighted` the
    /// ordinal the menu highlights: the next ordinal, the row's action, and
    /// the first highlight where a menu the keyboard opened gives it
    /// (``takesFirstHighlight(ordinal:isEnabled:)``), exactly as the row's
    /// own render does. A row whose drawing showed another ordinal, or the
    /// other highlight, is noted stale (``staleRows``).
    func replayClaim(_ claim: ServedClaim, highlighted: Int?) {
        let ordinal = claimOrdinal(for: claim.identity)
        publish(ordinal: ordinal, action: claim.action, isEnabled: claim.isEnabled)
        let isLit =
            ordinal == highlighted || takesFirstHighlight(ordinal: ordinal, isEnabled: claim.isEnabled)
        if ordinal != claim.ordinal || isLit != claim.isLit { staleRows.append(claim.identity) }
    }
}

extension MenuPopupController {
    /// Drops the stored drawings of the rows whose highlight this frame
    /// changes — the row drawn highlighted last frame and the row to be
    /// highlighted now — so that the column draws those two and serves the
    /// rest. Their sizes stay: a row measures as no menu's row (only a render
    /// claims an ordinal), so the highlight cannot move a cell of its size.
    ///
    /// By who drew each ordinal last frame. Where the rows have moved since,
    /// the row served under the old numbering is caught by its claim
    /// (``MenuRowSink/replayClaim(_:highlighted:)``).
    func forgetRowsChangingHighlight(in cache: RenderCache?) {
        guard let cache, highlightedOrdinal != drawnHighlight else { return }
        for ordinal in [drawnHighlight, highlightedOrdinal] {
            guard let ordinal, drawnClaimants.indices.contains(ordinal) else { continue }
            cache.clearAffected(by: drawnClaimants[ordinal], keepingSizes: true)
        }
    }
}

/// Draws the menu's column of rows, `rows`, serving each row it can from the
/// row memo (`MenuRowSink+ServedRows.swift`).
///
/// The rows whose highlight changes are dropped first, so a Down draws two
/// rows. A row served as it no longer is — its ordinal moved, or its
/// highlight — is caught by its claim, and then the column is drawn again,
/// the walk put back to where it stood (``RenderWalkCheckpoint``) and the
/// stale rows dropped, so what the frame keeps is what a column drawn from
/// nothing would show.
@MainActor
func drawMenuColumn(_ rows: some View, context: RenderContext, controller: MenuPopupController) -> FrameBuffer {
    controller.forgetRowsChangingHighlight(in: context.renderCache)
    let checkpoint = RenderWalkCheckpoint(context: context)
    defer { checkpoint.keep() }
    let column = TUIView.renderToBuffer(rows, context: context)
    let stale = controller.sink.staleRows
    guard !stale.isEmpty else { return column }
    checkpoint.rewind(context: context)
    for identity in stale { context.renderCache?.clearAffected(by: identity, keepingSizes: true) }
    controller.beginRenderPass()
    return TUIView.renderToBuffer(rows, context: context)
}
