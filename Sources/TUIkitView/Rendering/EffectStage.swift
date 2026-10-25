//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectStage.swift
//
//  What a walk's views did, held until the walk is done and run in SwiftUI's
//  order — and how to put back what they remembered, should a drawing they
//  were in be thrown away.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Effect Stage

/// The side effects of the drawings a walk makes, held back until each is
/// kept (decisions B-D5G-4 and B-D5G-11).
///
/// SwiftUI never runs an effect inside a body or a layout: it updates the
/// view graph, then runs the effects that update gave rise to — the
/// `onAppear`s, the `onChange` actions, the preference and geometry reports —
/// and, where they wrote state, updates and draws again before anything is
/// committed (`Tools/SwiftUIProbes/Effect and update ordering/`). TUIkit's walk
/// is its update, so a walk hands every effect its views make here, and they
/// run when the walk is done (``close(_:)``): a view drawn before an `onAppear`
/// and one drawn after it see the same state, and what the action wrote is
/// drawn by the walk made again for it (`FrameSettling`), not half-way through
/// this one.
///
/// A drawing may also be thrown away: a geometry owner that finds a reader
/// drew from a wrong answer draws its subtree again in the same walk
/// (`RenderWalkCheckpoint`), and the scene root walks the whole scene again.
/// What the first drawing *registered* is put back before the second; what it
/// would have *done* is here, not done, and is dropped with it
/// (``discard(since:)``), so only the drawing kept acts.
///
/// ## Open and armed
///
/// Every drawing that may be made again is **opened** here (``open()``), and
/// views hold back their effects while one that is **armed** is open
/// (``arm(atDepth:)``). The scene root's walk is armed from the start, so a
/// walk holds back everything; a drawing inside it is armed with it. A drawing
/// opened with nothing armed around it (a view rendered alone, outside any
/// walk of a scene) is armed once a reader inside is told an answer that could
/// turn out wrong, the one thing that makes its owner draw again.
///
/// ## Entries
///
/// While armed, a view hands over three kinds of entry:
///
/// - an **effect** — the action itself, of a ``Kind``. When the outermost
///   armed drawing is kept, its effects run kind by kind, in SwiftUI's order,
///   and in the order they were handed over within a kind, which is the
///   walk's. In a kept drawing that an armed one encloses, they wait for the
///   enclosing one.
/// - an **undo** — how to put back what the view remembered to decide whether
///   to act: the value an `onChange` compares against, that a view has
///   appeared. The memory is written as the drawing goes, so the rest of the
///   drawing sees it as before; a discarded drawing runs its undos, last
///   first, so the drawing that replaces it decides from what the frame began
///   with — and an `onChange` whose first drawing stored a prediction fires
///   nothing on the second, as on any first appearance.
/// - a view's **presence** — a lifecycle token first seen this pass, which a
///   discarded drawing takes back (``presenceUndo``) so that a view only it
///   drew is not on screen. Kept as the token, not a closure: every view with
///   an `onAppear`, a `.task` or an image is seen first once a pass, and a
///   walk holds all of them.
///
/// None is noted where nothing changes: an `onChange` whose value is what
/// it was hands over no action and remembers nothing new.
///
/// Opening and keeping are a depth count; arming is a comparison. A view pays
/// one test of ``isStaging`` on the frames it acts, and the closure an action
/// needs is made only when it acts.
///
/// Owned by `StateStorage`, one per app, and main-actor only in practice:
/// every drawing opens, hands over, and closes during a render walk.
package final class EffectStage {
    /// What an effect is: which decides when it runs among the others a kept
    /// drawing held — SwiftUI's order, as measured, the cases in the order they
    /// run.
    ///
    /// In SwiftUI's first update of a view carrying `onGeometryChange`,
    /// `onPreferenceChange` and `onAppear`, the geometry action ran first, then
    /// the preference's, then the `onAppear`s, a parent's before its child's
    /// (`Tools/SwiftUIProbes/Effect and update ordering/appear.out`). The order
    /// of `onChange` among them was not measured — the probe's `onChange` was
    /// of what the `onAppear` wrote, so it ran in the next round — and
    /// ``change`` comes last. Within a kind the walk's order stands: a
    /// parent's before its child's, as measured for `onAppear`; siblings, top
    /// to bottom, which was not measured.
    package enum Kind: Int, CaseIterable, Sendable {
        /// `onGeometryChange`, and what a scroll view reports of what it shows:
        /// `onScrollGeometryChange`, `onScrollTargetVisibilityChange`, a bound
        /// `ScrollPosition`'s row.
        case geometry
        /// `onPreferenceChange`.
        case preference
        /// `onAppear`, and a task's start.
        case appearance
        /// `onChange(of:)`, and every other observer of a value:
        /// `onScrollPhaseChange`, `onModifierKeysChanged`,
        /// `onInteractiveResizeChange`.
        case change
    }

    /// Where an open drawing's entries start — what ``open()`` returns, and
    /// what ``discard(since:)`` and ``close(_:)`` are given back.
    package struct Mark {
        fileprivate let start: Int
    }

    /// How the frames' effects settled, counted since the stage was made: how
    /// many frames were walked again for what their effects wrote, and how
    /// often a chain was still writing when the frame was written
    /// (`FrameSettling`).
    package struct Settling: Equatable, Sendable, CustomStringConvertible {
        /// Frames settled.
        package var frames = 0
        /// Frames walked once more.
        package var walkedAgainOnce = 0
        /// Frames walked twice more, the most a frame is.
        package var walkedAgainTwice = 0
        /// Frames whose last walk's effects still wrote: the chain carries on
        /// in the next frame.
        package var leftWriting = 0

        package init() {}

        /// Every walk made again.
        package var rewalks: Int { walkedAgainOnce + 2 * walkedAgainTwice }

        package var description: String {
            "\(frames) frames: \(walkedAgainOnce) walked again once, \(walkedAgainTwice) twice, "
                + "\(leftWriting) still writing"
        }
    }

    /// An effect to run when the drawing is kept, an undo to run when it is
    /// discarded, or a lifecycle token to take back when it is discarded.
    private enum Entry {
        case effect(Kind, () -> Void)
        case undo(() -> Void)
        case presence(String)
    }

    /// What the armed drawings have handed over, oldest first.
    private var entries: [Entry] = []

    /// How many drawings are open, outermost to innermost.
    package private(set) var depth = 0

    /// The depth of the outermost armed drawing, or `Int.max` with none armed.
    private var armedDepth = Int.max

    /// How the frames settled so far — see ``Settling``.
    package private(set) var settling = Settling()

    /// Takes a lifecycle token's presence in this pass back, for a discarded
    /// drawing that first saw it: set by the lifecycle manager the stage is
    /// wired to.
    package var presenceUndo: ((String) -> Void)?

    /// Whether the walk is in an armed drawing — where a view hands its
    /// effects over rather than doing them.
    package var isStaging: Bool { depth >= armedDepth }

    /// Creates a stage with no drawing open.
    package init() {}

    /// Opens a drawing that may be discarded, and returns where its entries
    /// start. Inside an armed drawing it is armed with it.
    package func open() -> Mark {
        depth += 1
        return Mark(start: entries.count)
    }

    /// Arms the open drawing at `depth` — one at depth 1 being the outermost —
    /// and every drawing inside it. A depth deeper than any open drawing arms
    /// the innermost, and there is nothing to arm with none open.
    package func arm(atDepth depth: Int) {
        guard self.depth > 0 else { return }
        armedDepth = min(armedDepth, max(1, min(depth, self.depth)))
    }

    /// Runs `effect` now outside every armed drawing, and otherwise once the
    /// armed drawing is kept, among the effects of its `kind`.
    package func perform(as kind: Kind = .change, _ effect: @escaping () -> Void) {
        guard isStaging else {
            effect()
            return
        }
        entries.append(.effect(kind, effect))
    }

    /// Notes how to put back something an armed drawing changed, should the
    /// drawing be discarded. Nothing is noted outside every armed drawing:
    /// what is drawn there is drawn again as it was.
    package func noteUndo(_ undo: @escaping () -> Void) {
        guard isStaging else { return }
        entries.append(.undo(undo))
    }

    /// Notes that an armed drawing is the first in the pass to see the
    /// lifecycle token `token`, so a discard takes its presence back
    /// (``presenceUndo``).
    package func notePresence(_ token: String) {
        guard isStaging else { return }
        entries.append(.presence(token))
    }

    /// Throws away what the drawing opened at `mark` has handed over so far —
    /// its effects dropped, its undos run, last first — for the drawing to be
    /// made again. The drawing stays open, and stays armed.
    package func discard(since mark: Mark) {
        while entries.count > mark.start {
            switch entries.removeLast() {
            case .undo(let undo): undo()
            case .presence(let token): presenceUndo?(token)
            case .effect: break
            }
        }
    }

    /// Keeps the drawing opened at `mark`: its entries join the enclosing
    /// armed drawing's, or — when it was the outermost armed — its effects
    /// run, kind by kind (``Kind``), and its undos are let go.
    package func close(_ mark: Mark) {
        let closing = depth
        depth -= 1
        guard closing == armedDepth else { return }
        armedDepth = Int.max
        guard !entries.isEmpty else { return }
        // Taken out first: an effect that writes state runs no walk, and one
        // that hands over another has it run at once — nothing is armed now.
        let kept = entries
        entries.removeAll(keepingCapacity: true)
        for kind in Kind.allCases {
            for case .effect(let effectKind, let effect) in kept where effectKind == kind { effect() }
        }
    }

    /// Counts a frame settled after `rewalks` walks more, its last walk's
    /// effects still writing where `stillWriting` (`FrameSettling`).
    package func noteSettled(rewalks: Int, stillWriting: Bool) {
        settling.frames += 1
        if rewalks == 1 { settling.walkedAgainOnce += 1 }
        if rewalks >= 2 { settling.walkedAgainTwice += 1 }
        if stillWriting { settling.leftWriting += 1 }
    }

    /// Closes whatever is still open at the start of a render pass, where
    /// nothing should be: a drawing that opened and was never closed would
    /// hold back every effect after it for good. Its effects run, as for a
    /// drawing kept.
    package func beginRenderPass() {
        guard depth != 0 else { return }
        SoftTrap.report("A drawing opened on the effect stage was never closed (\(depth) open).")
        depth = 1
        armedDepth = 1
        close(Mark(start: 0))
    }
}
