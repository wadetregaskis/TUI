//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationPanelSlot.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

extension AnimationPage {
    /// The panel, and the three answers to "what happens to the space it was
    /// in?"
    ///
    /// By default it is what SwiftUI's stack does: the space is taken on the
    /// frame the panel appears and given back on the frame it goes, and the
    /// page below glides with the change while the panel plays its transition
    /// where it is — fading in where it lands, the page sliding away from over
    /// it; fading out where it was, the page sliding up over it. Held
    /// (`.transitionSpace(.held)`, TUIkit's own), the space stays while the
    /// panel leaves and goes once it has gone, so the page stands still under
    /// the removal and then moves up at once. Kept, a fixed frame holds the
    /// space whether the panel is there or not, so nothing below ever moves.
    ///
    /// A function rather than a view of its own, so that what it returns
    /// stands in the page's stack exactly as if it were written there: a view
    /// with a `body` would be one child of the stack, drawn as a unit, where
    /// a frame on an `if` written in the stack reaches the `if`'s members.
    ///
    /// - Parameters:
    ///   - showsPanel: Whether the panel is there.
    ///   - space: What happens to its rows as it comes and goes.
    ///   - transition: How it comes and goes.
    static func panelSlot(
        showsPanel: Bool, space: PanelSpace, transition: AnyTransition
    ) -> some View {
        // The frame is on a stack that is always there, and the `if` is inside
        // it. On the `if` itself — `(showsPanel ? panel : nil).frame(…)`, which
        // this used to be — the frame reaches only what the `if` has, as a
        // frame on a `Group` reaches only its members, and with the panel gone
        // that is nothing: no rows were kept at all. SwiftUI does the same,
        // measured: a `nil` framed 50 tall adds no height to its stack, the
        // same `nil` in a `VStack` framed 50 tall adds 50.
        //
        // One frame and one `transitionSpace` whatever the choice, with a
        // height of `nil` when the space is not kept — NOT `if kept {
        // slot.frame(…) } else { slot }`. Swapping the wrapper is a change of
        // view IDENTITY: every `@State` below it is recreated at its initial
        // value the moment the picker moves, which is a bug this page would
        // have been an unusually good place to demonstrate accidentally.
        // Unkept and empty, the stack is no rows and takes no spacing, so the
        // page closes up — TUIkit's rule, not SwiftUI's, which would leave a
        // spacing's gap (`Documentation/SwiftUI parity/SwiftUI compatibility
        // guide.md`, "A child with no extent takes no stack spacing").
        //
        // Nothing clips the slot: a panel leaving is drawn where it was, past
        // a stack that has already given its rows back, and a clip would cut
        // it away.
        //
        // Five rows, which is what the panel IS: a text row, a row of padding
        // each side of it, and the border's two. Reserving three left the
        // padding fighting the border for one row.
        VStack(spacing: 0) {
            if showsPanel {
                Text("page.animation.panel")
                    .padding(1)
                    .border(.palette.accent)
                    .transition(transition)
            }
        }
        .frame(height: space == .kept ? 5 : nil, alignment: .top)
        .transitionSpace(space == .held ? .held : .released)
    }
}
