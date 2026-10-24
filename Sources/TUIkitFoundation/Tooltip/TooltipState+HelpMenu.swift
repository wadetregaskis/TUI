//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipState+HelpMenu.swift
//
//  The menu bar's Help menu's two choices about tooltips — whether they show
//  at all, and every one at once — and what the screen holds for them to act
//  on.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TooltipState {
    /// The trigger the scene's root draws with for the Help menu's choices, or
    /// `nil` where the person has chosen nothing and each subtree's own
    /// (``EnvironmentValues/tooltipTrigger``, `.automatic` by default) stands:
    /// `.never` with Show Tooltips off, `.always` with Show All Tooltips on.
    ///
    /// Published at the root, so a subtree's own `tooltips(_:)` still wins
    /// inside it, as any environment value written nearer a view does: an app
    /// that turned a panel's tooltips off keeps them off.
    package var menuTrigger: TooltipTrigger? {
        if !showsTooltips { return .never }
        return showsAllTooltips ? .always : nil
    }

    /// Whether a `help(_:)` view was drawn this walk.
    package var hasHelpOnScreen: Bool { helpDrawnThisWalk > 0 }

    /// Turns every tooltip on the screen on or off — Help ▸ Show All
    /// Tooltips' action and the help key's with Option — returning whether
    /// anything changed: nothing does, and the key falls through, while
    /// tooltips are off or no view on the screen has help to show, unless
    /// they are showing and this hides them.
    @discardableResult
    package func toggleShowsAllTooltips() -> Bool {
        guard showsAllTooltips || (showsTooltips && hasHelpOnScreen) else { return false }
        showsAllTooltips.toggle()
        return true
    }

    /// Notes that a `help(_:)` view draws this walk, and records the note for
    /// a memo that serves the view to make again (`EffectJournal`): the count
    /// is emptied every walk (``beginWalk()``), and a view served from a memo
    /// draws nothing of its own.
    @MainActor
    package func noteHelpDrawn(in context: RenderContext) {
        helpDrawnThisWalk += 1
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        let token = context.environment.keyChannelToken
        journal.append(
            EffectJournal.Entry(kind: Self.helpDrawnKind, channelToken: token) { replay in
                replay.environment.tooltipState?.helpDrawnThisWalk += 1
            })
    }

    /// The journal kind of ``noteHelpDrawn(in:)``.
    static let helpDrawnKind = EffectJournal.Kind("helpDrawn")
}
