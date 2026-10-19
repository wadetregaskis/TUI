//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationModifier+Content.swift
//
//  The presented content of a sheet or cover: the context it renders in, its
//  ESC item, and its drawing at the size its style and detent give it.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitChrome
import TUIkitFoundation

extension ModalPresentationModifier {
    /// The context the presented content renders in.
    func presentedContext(
        sectionID: String, gate: DismissalGate, overlayHeight: Int, context: RenderContext
    ) -> RenderContext {
        // Render the modal content against the CONTENT AREA (screen minus app
        // header and status bar), not the full terminal height, in the modal
        // section so its focusables register there. The compositor clamps
        // overlays to that same content area (top-biased), so a dialog built
        // against the full height would have its bottom rows — the footer with
        // Done/Cancel and the bottom border — sliced off, reading as "sliding
        // under the status bar". Building against `overlayContentHeight` makes
        // the container reserve its footer within the visible area instead. Width
        // is still the full terminal width (the horizontal clamp already works).
        //
        // The item's id IS the identity, for the `item:` forms. Presenting for
        // one row and then another handed the second row's content the first
        // row's `@State` — a half-typed draft, a scroll position, a selection —
        // because index 1 is the same slot whatever the sheet is about. That is
        // exactly what `ForEach` keys its rows by their element's id to avoid,
        // so this is the same `.keyed` step, for the same reason. The
        // `isPresented:` forms keep the positional slot: nothing about them
        // varies, and re-keying a presentation that is about nothing would only
        // throw its state away.
        var modalContext =
            (itemKey.map { context.withChildIdentity(erasedType: Modal.self, key: $0) }
            ?? context.withChildIdentity(type: Modal.self, index: 1))
            .withAvailableWidth(context.environment.terminalWidth)
            .withAvailableHeight(overlayHeight)
        modalContext.environment.activeFocusSectionID = sectionID
        // Its `.toolbar`s' items are the presentation's, drawn at its edges:
        // the window's bars are inert while it is up.
        modalContext.environment.presentationHostsToolbar = true
        modalContext.environment.presentationToolbar = presentationToolbar(context: context)
        modalContext.leavePresenter()
        modalContext.environment.dismiss = dismissAction()
        modalContext.environment.isPresented = true
        modalContext.environment.dismissalGate = gate
        return modalContext
    }

    /// The presentation's ESC item on the status bar: `escape`, named for
    /// what it does this frame (``DismissalGate/escapeLabel(dismissal:)``),
    /// and taking a held Escape's repeats as that does
    /// (``DismissalGate/escapeRepeats``). A click is a press.
    func escapeItem(gate: DismissalGate, escape: @escaping (_ isRepeat: Bool) -> Void) -> StatusBarItem {
        var item = StatusBarItem(shortcut: Shortcut.escape, label: gate.escapeLabel(dismissal: .dismiss)) {
            escape(false)
        }
        item.repeats = gate.escapeRepeats
        return item
    }

    /// Whether the presented sheet is a band across the content area: a
    /// detented sheet whose content lets the page through
    /// (``View/presentationBackgroundInteraction(_:)``), and names no sizing
    /// of its own — `.automatic` aside. One that does is sized by it, as any
    /// sheet is: `.fitted`, a card centred where the band would be.
    private func isBand(sizing: (any PresentationSizing)?, hasDetent: Bool) -> Bool {
        guard hasDetent, sizing == nil || sizing is AutomaticPresentationSizing,
            let interaction = presentationTrait(PresentationBackgroundInteractionProviding.self, of: modal)?
                .backgroundInteraction,
            case .enabled = interaction.kind
        else { return false }
        return true
    }

    /// The sheet's content as a box: every cell of its extent painted, and as
    /// tall as its detent asks.
    ///
    /// A `Dialog` or a `Panel` is one already — it fills its rectangle, and
    /// takes the detent's height to be its own (``sheetDetentHeight``) — and
    /// comes back unchanged. Plain content is not: a stack's spacing rows and
    /// the ends of its short lines paint nothing, so a centred sheet of it
    /// showed the dimmed page through every gap, where SwiftUI's sheet is
    /// opaque whatever it holds; and nothing took the detent's height, so a
    /// grabber dragged up changed the detent — past a live sheet's
    /// `upThrough`, dimming the page — and drew the sheet no taller. Laid on
    /// blank cells of the box's size, it is the box a `Dialog`'s interior is.
    static func sheetBox(_ buffer: FrameBuffer, detentHeight: Int?, palette: any Palette) -> FrameBuffer {
        let height = max(buffer.height, detentHeight ?? 0)
        guard buffer.width > 0, !(buffer.linesAreUniformWidth && height == buffer.height) else { return buffer }
        var box = FrameBuffer(emptyWithWidth: buffer.width, height: height)
        box.compositeCarryingClaimsOverNothing(with: buffer, at: (x: 0, y: 0), palette: palette)
        return box
    }

    /// The presented content drawn by `draw` with the toolbar items it hosts
    /// at its edges (`PresentationToolbarItems`, TUIkitChrome): `draw` is
    /// handed the context and the cap on the content's height less the rows
    /// they take — and a detent's height, which a `Dialog` takes as its own,
    /// less them too.
    private func hostingToolbar(
        context: RenderContext, capHeight: Int, draw: (RenderContext, Int) -> FrameBuffer
    ) -> FrameBuffer {
        guard let toolbar = context.environment.presentationToolbar else { return draw(context, capHeight) }
        return toolbar.hosting(
            context: context, capHeight: capHeight,
            seed: { seeding in _ = draw(seeding, capHeight) },
            draw: { inner, cap in
                var inner = inner
                let rows = context.availableHeight - inner.availableHeight
                if let detent = inner.environment.sheetDetentHeight {
                    inner.environment.sheetDetentHeight = max(1, detent - rows)
                }
                return draw(inner, cap)
            })
    }

    /// Renders the presented content at the size its style gives it: a sheet
    /// at its own height or its detent's (`detentHeight`), a cover over the
    /// whole content area.
    func renderModal(
        context: RenderContext, modalContext: RenderContext, overlayHeight: Int, detentHeight: Int?
    ) -> FrameBuffer {
        // A `presentationBackground` the content named fills the presentation —
        // the sheet's box, or the cover's whole area — so it goes around what
        // is presented here, where that size is known.
        let background = presentationTrait(PresentationBackgroundProviding.self, of: modal)

        switch style {
        case .sheet:
            var sheetContext = modalContext
            var capHeight = overlayHeight
            // The corners the content named for its sheet go to the sheet's
            // box, as its detent's height does (``EnvironmentValues/sheetCornerRadius``).
            if let radius = presentationTrait(PresentationCornerRadiusProviding.self, of: modal)?.cornerRadius {
                sheetContext.environment.sheetCornerRadius = radius
            }
            // A sizing the content named proposes the sheet's size, and its box
            // takes it — the height as a detent's, the width likewise (see
            // ``EnvironmentValues/sheetProposedWidth``). A detent's height wins.
            let sizing = presentationTrait(PresentationSizingProviding.self, of: modal)?.sizing
            if isBand(sizing: sizing, hasDetent: detentHeight != nil) {
                // A sheet beside a live page is a band across the whole
                // content area, as a `VSplitView`'s pane is (owner Q3) — at
                // every detent, so it does not narrow as it turns modal past
                // its `upThrough`. Its box takes the width.
                sheetContext.environment.sheetProposedWidth = sheetContext.availableWidth
            } else if let sizing,
                let proposedHeight = applyPresentationSizing(
                    sizing, of: modal, to: &sheetContext, hasDetent: detentHeight != nil,
                    kept: keptSheetSize(context: context))
            {
                capHeight = proposedHeight
            }
            if let detentHeight {
                // The height goes to the sheet's own box, via the environment
                // (``EnvironmentValues/sheetDetentHeight``) — NOT as a frame
                // around it. A fixed frame is top-aligned and a `Dialog` sizes
                // to its content, so wrapping left the leftover rows as blank,
                // unstyled, opaque overlay lines: a hole punched through the
                // page below the dialog, belonging to nothing.
                sheetContext.availableHeight = detentHeight
                sheetContext.environment.sheetDetentHeight = detentHeight
                capHeight = detentHeight
            }
            if let background {
                return hostingToolbar(context: sheetContext, capHeight: capHeight) { inner, cap in
                    renderPresentedDialog(background.presentationBackground(behind: modal), context: inner, capHeight: cap)
                }
            }
            return Self.sheetBox(
                hostingToolbar(context: sheetContext, capHeight: capHeight) { inner, cap in
                    renderPresentedDialog(modal, context: inner, capHeight: cap)
                },
                detentHeight: detentHeight, palette: context.environment.palette)
        case .fullScreen:
            // The cover IS the screen: full width and the whole content area,
            // so there is nothing of the page left to show through and nothing
            // to dim.
            //
            // Centred, explicitly. `frame(width:height:)` defaults to
            // `.topLeading` — deliberately, because a fixed frame is usually a
            // left-aligned column — but a cover is the opposite case: content
            // smaller than the screen, with the whole screen as its stage, and
            // SwiftUI centres it. Left at the default, a three-line message
            // huddles in the top-left corner of an otherwise empty terminal.
            let width = context.environment.terminalWidth
            return hostingToolbar(context: modalContext, capHeight: overlayHeight) { inner, height in
                let cover = modal.frame(width: width, height: height, alignment: .center)
                if let background {
                    return renderPresentedDialog(
                        background.presentationBackground(behind: cover), context: inner, capHeight: height)
                }
                return renderPresentedDialog(cover, context: inner, capHeight: height)
            }
        }
    }
}
