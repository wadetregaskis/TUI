//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectStage.swift
//
//  What a drawing that may be thrown away did, held until the drawing is
//  kept — and how to put back what it remembered, should it not be.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Effect Stage

/// The side effects of drawings the walk may still throw away, held back until
/// each is kept (decisions B-D5G-4).
///
/// A geometry owner that finds a reader drew from a wrong answer draws its
/// subtree again in the same walk (`RenderWalkCheckpoint`), and the scene root
/// walks the whole scene again. What the first drawing *registered* is put
/// back before the second; what it *did* — an `onChange` action, an
/// `onAppear`, a `.task` started — cannot be. So while the walk is in a
/// drawing that may be discarded, a view does not do those things: it hands
/// them here, and they run once the drawing is kept. A discarded drawing's are
/// dropped, and the second drawing hands over its own.
///
/// ## Open and armed
///
/// Every drawing that may be made again is **opened** here (``open()``), but
/// views hold back their effects only once it is **armed** (``arm(atDepth:)``)
/// — once a reader inside has been told an answer that could turn out wrong,
/// which is the only thing that makes its owner draw again. Until then
/// nothing the drawing has drawn depends on an answer: measuring asks no
/// space, and an answer reaches only what is drawn after it is told — the
/// reader's content, and what that writes. A second drawing therefore draws
/// everything before the arming point exactly as the first did, and those
/// views' effects, done at once, are not done again: what they remembered in
/// doing them says so. So a subtree with no reader in it acts exactly as it
/// did before there was a stage, and a subtree with one acts at once up to
/// the first answer, and holds back only after it.
///
/// Arming arms the drawing of the owner that will check the reader — the
/// nearest open owner of the space it asked, or the outermost drawing (the
/// scene root's) — and every drawing opened inside it, until it closes.
///
/// ## Entries
///
/// While armed, a view hands over two kinds of entry:
///
/// - an **effect** — the action itself. It runs when the armed drawing is
///   kept, in the order the effects were handed over, which is the order they
///   ran in before there was a stage. In a kept drawing that an armed one
///   encloses, they wait for the enclosing one.
/// - an **undo** — how to put back what the view remembered to decide whether
///   to act: the value an `onChange` compares against, that a view has
///   appeared. The memory is written as the drawing goes, so the rest of the
///   drawing sees it as before; a discarded drawing runs its undos, last
///   first, so the drawing that replaces it decides from what the frame began
///   with — and an `onChange` whose first drawing stored a prediction fires
///   nothing on the second, as on any first appearance.
///
/// Neither is noted where nothing changes: an `onChange` whose value is what
/// it was hands over no action and remembers nothing new.
///
/// Opening and keeping are a depth count; arming is a comparison. A walk in
/// no armed drawing costs a view one test of ``isStaging`` on the frames it
/// acts, and nothing on the others.
///
/// Owned by `StateStorage`, one per app, and main-actor only in practice:
/// every drawing opens, hands over, and closes during a render walk.
package final class EffectStage {
    /// Where an open drawing's entries start — what ``open()`` returns, and
    /// what ``discard(since:)`` and ``close(_:)`` are given back.
    package struct Mark {
        fileprivate let start: Int
    }

    /// An effect to run when the drawing is kept, or an undo to run when it
    /// is discarded.
    private enum Entry {
        case effect(() -> Void)
        case undo(() -> Void)
    }

    /// What the armed drawings have handed over, oldest first.
    private var entries: [Entry] = []

    /// How many drawings are open, outermost to innermost.
    package private(set) var depth = 0

    /// The depth of the outermost armed drawing, or `Int.max` with none armed.
    private var armedDepth = Int.max

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
    /// and every drawing inside it: a reader in it has been told an answer
    /// that could be wrong, so that drawing may be made again. A depth deeper
    /// than any open drawing arms the innermost, and there is nothing to arm
    /// with none open.
    package func arm(atDepth depth: Int) {
        guard self.depth > 0 else { return }
        armedDepth = min(armedDepth, max(1, min(depth, self.depth)))
    }

    /// Runs `effect` now outside every armed drawing, and otherwise once the
    /// armed drawing is kept.
    package func perform(_ effect: @escaping () -> Void) {
        guard isStaging else {
            effect()
            return
        }
        entries.append(.effect(effect))
    }

    /// Notes how to put back something an armed drawing changed, should the
    /// drawing be discarded. Nothing is noted outside every armed drawing:
    /// what is drawn there is drawn again as it was.
    package func noteUndo(_ undo: @escaping () -> Void) {
        guard isStaging else { return }
        entries.append(.undo(undo))
    }

    /// Throws away what the drawing opened at `mark` has handed over so far —
    /// its effects dropped, its undos run, last first — for the drawing to be
    /// made again. The drawing stays open, and stays armed.
    package func discard(since mark: Mark) {
        while entries.count > mark.start {
            if case .undo(let undo) = entries.removeLast() { undo() }
        }
    }

    /// Keeps the drawing opened at `mark`: its entries join the enclosing
    /// armed drawing's, or — when it was the outermost armed — its effects
    /// run, in order, and its undos are let go.
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
        for case .effect(let effect) in kept { effect() }
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
