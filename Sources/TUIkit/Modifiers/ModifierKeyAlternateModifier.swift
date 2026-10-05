//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModifierKeyAlternateModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - modifierKeyAlternate

extension View {
    /// Builds a view to use in place of the modified view when the user
    /// presses the modifier key(s) indicated by the given set.
    ///
    /// ```swift
    /// Button("Go Forward") { forward() }
    ///     .modifierKeyAlternate(.option) {
    ///         Button("Go to Page…") { goToPage() }
    ///     }
    /// ```
    ///
    /// The alternate is drawn while every key in `modifiers` is held, and the
    /// modified view the rest of the time. A view can have several alternates
    /// on different keys; when more than one matches the held keys, the one
    /// on the most keys prevails, wherever it sits in the chain.
    ///
    /// The modified view keeps its `@State` while the alternate is drawn, and
    /// if the focus was in it when the alternate took its place, the focus
    /// goes back to it when the keys are released — unless it has been moved
    /// somewhere else in the meantime.
    ///
    /// ## Where it works
    ///
    /// A terminal reports a modifier key held on its own only under the kitty
    /// keyboard protocol's "report all keys as escape codes" enhancement,
    /// which TUIkit turns on wherever the terminal answers its query. Read
    /// ``EnvironmentValues/keyboardReporting``'s
    /// ``KeyboardReporting/reportsModifierKeys`` to know: where it is `false`
    /// the modified view is always drawn and the alternate never is, so give
    /// whatever the alternate does another route.
    ///
    /// SwiftUI also turns an alternate inside a menu into an alternate menu
    /// item, and gives it the modified view's keyboard shortcut with the
    /// alternate's modifiers added. Here an alternate in a menu replaces the
    /// row while the keys are held, like anywhere else, and takes no shortcut
    /// of its own: write one on it with ``View/keyboardShortcut(_:modifiers:)``.
    ///
    /// - Parameters:
    ///   - modifiers: The modifier keys to associate with the alternate view.
    ///     While all these keys are held, the alternate replaces the modified
    ///     view.
    ///   - alternate: A view builder for the modified view's alternate.
    /// - Returns: A modified view with an alternate view to use while specific
    ///   modifier keys are held down.
    public func modifierKeyAlternate<V: View>(
        _ modifiers: EventModifiers, @ViewBuilder _ alternate: () -> V
    ) -> some View {
        ModifierKeyAlternateModifier(content: self, modifiers: modifiers, alternate: alternate())
    }
}

// MARK: - The modifier

/// A view that can say which of the alternates in its chain the held keys
/// match most specifically — so the outermost of several can defer to a more
/// specific one inside it.
@MainActor
protocol ModifierKeyAlternating {
    /// The modifier set of the most specific alternate in this chain that
    /// `held` matches, or `nil` when none does.
    func mostSpecificMatch(held: EventModifiers) -> EventModifiers?
}

/// The view behind ``View/modifierKeyAlternate(_:_:)``.
///
/// Draws the modified view at its own identity and the alternate one level
/// below, so the two never share a state slot.
///
/// While an alternate is drawn the modified view is not, so nothing in it
/// renders and marks its state active. Left at that, a tap of the modifier
/// key would cost the modified view its `@State` — a counter reset to zero
/// for one frame of "Go to…". So while any alternate in the chain shows, this
/// declares the subtree retained, as a collapsed `DisclosureGroup` does for
/// its content, and the modified view comes back with its state. The focus
/// comes back too: see ``ModifierKeyMonitor`` and its held focus.
struct ModifierKeyAlternateModifier<Content: View, Alternate: View>: View, ModifierKeyAlternating {
    let content: Content
    let modifiers: EventModifiers
    let alternate: Alternate

    var body: Never {
        fatalError("ModifierKeyAlternateModifier renders via Renderable")
    }

    /// Whether `held` includes every one of this alternate's keys.
    private func matches(_ held: EventModifiers) -> Bool {
        !modifiers.isEmpty && held.isSuperset(of: modifiers)
    }

    func mostSpecificMatch(held: EventModifiers) -> EventModifiers? {
        let inner = (content as? any ModifierKeyAlternating)?.mostSpecificMatch(held: held)
        guard matches(held) else { return inner }
        guard let inner, inner.rawValue.nonzeroBitCount > modifiers.rawValue.nonzeroBitCount else {
            return modifiers
        }
        return inner
    }

    /// Whether this alternate is the one to draw for `held`: it matches, and
    /// no alternate inside it matches on more keys.
    func showsAlternate(held: EventModifiers) -> Bool {
        guard matches(held) else { return false }
        return mostSpecificMatch(held: held) == modifiers
    }

    /// The context the alternate draws in: one level below this view.
    private func alternateContext(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Alternate.self, index: 0)
    }
}

extension ModifierKeyAlternateModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let monitor = context.environment.modifierKeyMonitor else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        // What is drawn depends on keys that change between frames with no
        // state changing, so no memo may keep it, and a change of them needs
        // a frame.
        context.environment.volatileReadTracker?.recordVolatileRead()
        if !context.isMeasuring {
            monitor.noteDrawnFrom()
            keepModifiedView(context: context, monitor: monitor)
        }
        guard showsAlternate(held: monitor.current) else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        return TUIkitView.renderToBuffer(alternate, context: alternateContext(context))
    }

    /// Keeps the modified view's state, and its focus, through the frames an
    /// alternate replaces it. Render path only; the claims are per pass.
    ///
    /// Asked of every modifier in a chain that renders, and every one of them
    /// gives the same answer — whether ANY alternate in the chain shows — since
    /// an inner one renders only while no outer one shows its own. Each step is
    /// idempotent, so a chain of two makes the same claims as one.
    private func keepModifiedView(context: RenderContext, monitor: ModifierKeyMonitor) {
        let focusManager = context.environment.focusManager
        guard mostSpecificMatch(held: monitor.current) != nil else {
            monitor.modifiedViewShown(at: context.identity, focusManager: focusManager)
            return
        }
        // The modified view renders at this identity, so its own `@State` is
        // here, which a retained subtree's root does not cover: only what is
        // strictly below it.
        context.stateStorage?.markActive(context.identity)
        context.stateStorage?.retainSubtree(context.identity)
        monitor.alternateShown(at: context.identity, focusManager: focusManager)
    }
}

extension ModifierKeyAlternateModifier: Layoutable {
    /// Measures whichever of the two it would draw.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if let monitor = context.environment.modifierKeyMonitor, showsAlternate(held: monitor.current) {
            return measureChild(alternate, proposal: proposal, context: alternateContext(context))
        }
        return measureChild(content, proposal: proposal, context: context)
    }
}
