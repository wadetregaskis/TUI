//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifierKeyMonitor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Modifier Key Monitor

/// The modifier keys held now, as the terminal last reported them, and the
/// views that want to hear when they change.
///
/// Fed by the run loop from `TerminalInput.modifierKeys`, which only a terminal
/// speaking the kitty keyboard protocol sends — a modifier key pressed or
/// released on its own, or a lock key toggled, and the parser's own report
/// when a key's modifiers disagree with the last one, the terminal loses the
/// focus, or the protocol is popped for a suspend (`KittyKeyDecoder`). In a
/// legacy encoding nothing
/// feeds it, so the state stays empty and nothing it holds ever fires; the
/// render loop does not even publish it there
/// (``KeyboardReporting/reportsModifierKeys``).
///
/// Its observers are registered per walk of the scene, as key handlers are,
/// and are asked when a report changes the state — between frames, like a key
/// handler, so every change reaches them, not only the ones a frame happens to
/// see.
///
/// `@unchecked Sendable` on the same footing as the other dispatchers
/// (`KeyEventDispatcher`, `MouseEventDispatcher`): touched only from the main
/// run loop, by the render pass and by input dispatch.
package final class ModifierKeyMonitor: @unchecked Sendable {
    /// The modifier keys held, and Caps Lock if it is on.
    private(set) var current: EventModifiers = []

    /// One view's observer: what it masks the state to, and its action.
    private struct Observer {
        let mask: EventModifiers
        let action: (EventModifiers, EventModifiers) -> Void
    }

    /// This walk's observers, in render order.
    private var observers: [Observer] = []

    /// Whether the frame on screen drew something from ``current``, so a change
    /// needs a frame to show.
    private var isDrawnFrom = false

    /// Where the focus was in a modified view that an alternate has replaced,
    /// keyed by the modified view's identity — see ``alternateShown(at:focusManager:)``.
    private var heldFocus: [ViewIdentity: HeldFocus] = [:]

    /// Counts walks of the scene, so a held focus knows whether the last walk
    /// drew its alternate.
    private var walk = 0

    /// The focus a modified view held when an alternate replaced it.
    private struct HeldFocus {
        /// The control in the modified view that held the focus, or `nil` when
        /// the focus was elsewhere.
        let focusID: String?
        /// The focus manager the modified view drew under.
        let focusManager: FocusManager?
        /// Whether an alternate in the chain is drawn for these held keys:
        /// once one is not, the focus goes back (``record(_:)``).
        let showsAlternate: (EventModifiers) -> Bool
        /// Where the focus was once the frame that first drew the alternate
        /// had ended — where the focus system's recovery sent it, the control
        /// having left the ring — and `nil` if nowhere. Known once
        /// ``landed``.
        var landedID: String?
        /// Whether ``landedID`` has been taken (``endFrame()``).
        var landed = false
        /// The last walk an alternate in this chain was drawn.
        var touched: Int
    }

    init() {}

    /// Forgets the last walk's observers and drawing; the walk about to start
    /// registers its own. A held focus whose view drew nothing last walk has
    /// left the scene, and goes too.
    func beginSceneRender() {
        observers.removeAll()
        isDrawnFrom = false
        if !heldFocus.isEmpty {
            heldFocus = heldFocus.filter { $0.value.touched >= walk }
        }
        walk &+= 1
    }

    // MARK: - The focus an alternate takes

    /// Notes that the view at `identity` is replaced this walk by one of its
    /// modifier-key alternates.
    ///
    /// On the first walk it is, remembers which of its controls held the
    /// focus: that control is not drawn now, so the focus system recovers the
    /// focus to a neighbour at the end of the pass — the alternate's own
    /// control, where it has one in the same place, or the next control on the
    /// page. Where that left it is taken as the frame ends (``endFrame()``),
    /// so the return can tell the recovery's move from one the user made, a
    /// Tab read with the keys' release in one burst of input included.
    ///
    /// - Parameter showsAlternate: Whether an alternate in the chain is drawn
    ///   for the keys given (`ModifierKeyAlternateModifier.mostSpecificMatch`).
    func alternateShown(
        at identity: ViewIdentity, focusManager: FocusManager?, showsAlternate: @escaping (EventModifiers) -> Bool
    ) {
        if var held = heldFocus[identity] {
            held.touched = walk
            heldFocus[identity] = held
            return
        }
        heldFocus[identity] = HeldFocus(
            focusID: focusManager.flatMap { Self.focusedID(in: identity, of: $0) },
            focusManager: focusManager, showsAlternate: showsAlternate, touched: walk)
    }

    /// Ends a frame, once its focus pass has (`FocusManager.endRenderPass`):
    /// a held focus whose alternate this frame drew for the first time takes
    /// where the focus is now — where the recovery put it.
    package func endFrame() {
        guard !heldFocus.isEmpty else { return }
        for (identity, held) in heldFocus where !held.landed {
            var landing = held
            landing.landedID = held.focusManager?.currentFocusedID
            landing.landed = true
            heldFocus[identity] = landing
        }
    }

    /// Notes that the view at `identity` is drawn this walk, and if an
    /// alternate replaced it while it held the focus and the keys' release
    /// did not already give it back (``record(_:)``), gives it back now.
    ///
    /// Not where an alternate at `identity` was drawn this same walk. The
    /// modified view an outer alternate stands in for is walked unseen
    /// (`ModifierKeyAlternateModifier.walkHidden`), and an inner alternate
    /// in the chain renders there at the same identity, knowing only its own
    /// keys: on keys that do not overlap the outer one's, none of its own
    /// match, and it says its modified view is drawn. Taken at its word, it
    /// gave the focus back mid-walk to a control that was not drawn, the
    /// recovery moved it to a neighbour, and the release found nothing to
    /// give back.
    func modifiedViewShown(at identity: ViewIdentity, focusManager: FocusManager?) {
        guard !heldFocus.isEmpty, let held = heldFocus[identity], held.touched != walk else { return }
        heldFocus[identity] = nil
        giveBack(held, at: identity)
    }

    /// Gives the focus back to the control an alternate took it from, if
    /// nothing moved it on purpose meanwhile: the focus is where the recovery
    /// put it, or on a control of the alternate, or nowhere.
    ///
    /// The control is not in the ring — it is not drawn — so the focus is
    /// asked for by id, which the focus system holds until it registers. The
    /// focus the recovery gave a neighbour goes first: given back as the
    /// keys are released, between frames, the neighbour would otherwise draw
    /// focused in the next frame before the control registered and took it,
    /// two controls showing the focus for a frame (decisions-D1K B-D1K-2).
    private func giveBack(_ held: HeldFocus, at identity: ViewIdentity) {
        guard let focusID = held.focusID, let focusManager = held.focusManager else { return }
        let current = focusManager.currentFocusedID
        let inAlternate = focusManager.focusedIdentity.map { identity.isAncestor(of: $0) } ?? false
        guard current == nil || !held.landed || current == held.landedID || inAlternate else { return }
        if current != focusID { focusManager.relinquishFocus() }
        focusManager.focus(id: focusID)
    }

    /// The focused control's id if it rendered at `identity` or below it.
    private static func focusedID(in identity: ViewIdentity, of focusManager: FocusManager) -> String? {
        guard let focused = focusManager.focusedIdentity,
            focused == identity || identity.isAncestor(of: focused)
        else { return nil }
        return focusManager.currentFocusedID
    }

    /// Adds an observer for this walk, asked with the old and new state, both
    /// masked, whenever a report changes the state within `mask`.
    func observe(mask: EventModifiers, _ action: @escaping (EventModifiers, EventModifiers) -> Void) {
        observers.append(Observer(mask: mask, action: action))
    }

    /// Notes that this walk drew something from ``current``: a modifier key
    /// alternate.
    func noteDrawnFrom() {
        isDrawnFrom = true
    }

    /// The number of observers this walk registered, for tests.
    var observerCount: Int { observers.count }

    /// Takes a report from the terminal, tells each observer whose masked state
    /// it changes, and answers whether the screen needs a frame for it.
    ///
    /// - Returns: `true` when the state changed and the frame on screen drew
    ///   something from it. An observer's action asks for its own frame if it
    ///   changes state, as a key handler's does.
    @discardableResult
    package func record(_ state: ModifierKeyState) -> Bool {
        let old = current
        let new = EventModifiers(state)
        guard new != old else { return false }
        current = new
        for observer in observers {
            let before = old.intersection(observer.mask)
            let after = new.intersection(observer.mask)
            if before != after { observer.action(before, after) }
        }
        // The focus an alternate took goes back as its keys are released,
        // before the next frame draws anything.
        for (identity, held) in heldFocus where !held.showsAlternate(new) {
            heldFocus[identity] = nil
            giveBack(held, at: identity)
        }
        return isDrawnFrom
    }
}

// MARK: - From a report

extension EventModifiers {
    /// The modifiers a terminal's modifier-key report says are held, and Caps
    /// Lock if it is on.
    init(_ state: ModifierKeyState) {
        var result: Self = []
        if state.shift { result.insert(.shift) }
        if state.control { result.insert(.control) }
        if state.option { result.insert(.option) }
        if state.command { result.insert(.command) }
        if state.capsLock { result.insert(.capsLock) }
        self = result
    }
}

// MARK: - Environment

private struct ModifierKeyMonitorKey: EnvironmentKey {
    static let defaultValue: ModifierKeyMonitor? = nil
}

extension EnvironmentValues {
    /// The app's modifier-key state, published only where the terminal reports
    /// modifier keys on their own; `nil` everywhere else, which is the answer
    /// "no modifier key is held, and none ever will be reported".
    package var modifierKeyMonitor: ModifierKeyMonitor? {
        get { self[ModifierKeyMonitorKey.self] }
        set { self[ModifierKeyMonitorKey.self] = newValue }
    }
}
