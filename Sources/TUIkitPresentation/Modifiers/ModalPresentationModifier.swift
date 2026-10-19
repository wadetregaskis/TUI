//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

/// A modifier that presents content as a centered modal overlay when a binding is true.
///
/// This is a generic presentation modifier that dims the base content and shows
/// the provided content centered on top. Unlike `AlertPresentationModifier`, this
/// accepts any view content.
///
/// ## Example
///
/// ```swift
/// VStack {
///     Text("Main content")
/// }
/// .modal(isPresented: $showModal) {
///     Dialog(title: "Settings") {
///         Text("Setting 1")
///         Text("Setting 2")
///     }
/// }
/// ```
public struct ModalPresentationModifier<Content: View, Modal: View>: View {
    /// How a presentation fills the screen.
    ///
    /// The two shapes SwiftUI distinguishes, and they differ in a terminal for
    /// the same reasons they differ anywhere: a sheet is a panel over a dimmed
    /// page, a cover replaces the page outright.
    enum Style {
        /// A centred panel sized to its content, over a dimmed page — `.sheet`,
        /// `.modal`, and every alert.
        case sheet
        /// The whole content area, nothing of the page showing through —
        /// `.fullScreenCover`.
        case fullScreen
    }

    /// The base content to render.
    let content: Content

    /// Binding to control modal visibility.
    let isPresented: Binding<Bool>

    /// The modal content to present.
    let modal: Modal

    /// Whether this presents as a panel or takes the whole screen.
    var style: Style = .sheet

    /// The identity key of the item this presentation is ABOUT, or `nil` for
    /// the `isPresented:` forms, which are about nothing in particular.
    ///
    /// The `item:` forms fold it into the presented content's identity below,
    /// which is what makes a different item a different view — fresh `@State`,
    /// fresh lifecycle — as SwiftUI's `item:` contract requires. Read at
    /// construction, from the same binding read the same moment the content is
    /// built from it, so the key and the content can never describe different
    /// items.
    var itemKey: String?

    public var body: Never {
        fatalError("ModalPresentationModifier renders via Renderable")
    }

    /// What `@Environment(\.dismiss)` means to the content being presented.
    ///
    /// Inside a presentation, dismissing means closing THAT presentation —
    /// which is the one thing `DismissAction`'s default cannot know. Left
    /// alone, the presented content inherits the top-level meaning, and the
    /// top-level meaning of dismissing a terminal app is to quit it: a
    /// `Button("Done") { dismiss() }` in a sheet — the shape SwiftUI's own
    /// documentation teaches — exited the whole program.
    ///
    /// Flipping the binding is deliberately the same act the ESC status-bar
    /// item performs, so the two routes out of a presentation cannot drift:
    /// `onDismiss` fires off the binding's presented → dismissed transition
    /// (see ``View/modal(isPresented:onDismiss:content:)``), so it
    /// runs for `dismiss()` exactly as it does for ESC.
    func dismissAction() -> DismissAction {
        let isPresented = self.isPresented
        return DismissAction { isPresented.wrappedValue = false }
    }
}

// MARK: - Renderable

extension ModalPresentationModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A focus section unique to THIS modal instance (its position in the
        // tree), so stacked modals each get a distinct section. Only the topmost
        // (most recently activated) section is interactive, and focus can't leak
        // between modals or to the background. A fixed shared id would make two
        // modals register into one section and break that isolation.
        let sectionID = "modal-\(context.identity.path)"

        // Both subtrees get their OWN child identities (the ContainerView
        // body/footer pattern). Rendering them at the modifier's identity made
        // a dialog's first `@State` share StateStorage key (identity, 0) with
        // this modifier's own drag-handler slot — the two boxes replaced each
        // other every frame (`storage(for:)` swaps on type mismatch), so any
        // state INSIDE the dialog silently reset (the colour picker's tab
        // selection never moved). The content identity is the same in the
        // dismissed and presented branches, so the page's state and lifecycle
        // tokens are stable across presentation.
        let contentContext = context.withChildIdentity(type: Content.self, index: 0)

        // Presented for another item than it was, it is a new sheet — before
        // anything reads what the presenter keeps for it.
        if !context.isMeasuring, isPresented.wrappedValue, let itemKey {
            startOver(forItem: itemKey, context: context)
        }

        // A sheet whose content lets the page through posts the rows it docks
        // every frame, presented or not, for the root to lay the page out by
        // before the walk (`postDock`).
        let backgroundInteraction =
            style == .sheet
            ? presentationTrait(PresentationBackgroundInteractionProviding.self, of: modal)?.backgroundInteraction
            : nil
        if let backgroundInteraction { postDock(backgroundInteraction, sectionID: sectionID, context: context) }

        // If not presented, just return base content.
        guard isPresented.wrappedValue else {
            // Tear down the modal focus section if it's still active (the modal
            // was just dismissed). This reverts focus to the page's section AND
            // restores its remembered focus, so the page doesn't jump to its
            // first element — which a ScrollView would then snap-scroll to,
            // resetting the scroll position.
            if !context.isMeasuring {
                // Deactivation mutates focus state — a render side effect
                // (see the presentation branch below).
                context.environment.volatileReadTracker?.recordRenderSideEffect()
                context.environment.focusManager?.deactivateSection(id: sectionID)
                // Presented again, it is a new sheet.
                startOver(context: context)
            }
            return TUIkitView.renderToBuffer(content, context: contentContext)
        }

        // Whether the content forbade interactive dismissal. Read BEFORE the
        // status-bar item below, which is why it rides a static conformance
        // rather than a preference — the same constraint the detent has.
        let dismissIsDisabled =
            presentationTrait(InteractiveDismissDisabling.self, of: modal)?
            .interactiveDismissIsDisabled ?? false

        // Kept for the presentation's life, its question cleared each frame —
        // see `presentationDismissalGate(context:propertyIndex:)`.
        let gate = presentationDismissalGate(context: context, propertyIndex: StateIndex.dismissalGate)
        // The reader's ways out go through the gate, so content with a
        // `dismissalConfirmationDialog` can ask first — and Escape is the
        // content's cancel button where it drew one, as on macOS
        // (`DismissalGate.escape`).
        let isPresented = self.isPresented
        let escape = { (isRepeat: Bool) in gate.escape(isRepeat: isRepeat) { isPresented.wrappedValue = false } }

        // The content's context: the content area's height, the modal's
        // section, and the presentation's ways out (`presentedContext`).
        let overlayHeight = context.environment.overlayContentHeight
        var modalContext = presentedContext(sectionID: sectionID, gate: gate, overlayHeight: overlayHeight, context: context)

        // A detent, if the content named one, decides the height instead of the
        // content's own. It has to be read BEFORE the render — it is the height
        // being rendered into — which is why it rides a static conformance
        // rather than a preference (see ``PresentationDetentsProviding``). A
        // cover is the whole content area and takes none.
        let detents =
            style == .sheet
            ? PresentedDetents(
                of: modal, extent: overlayHeight, environment: modalContext.environment,
                state: detentState(context: context))
            : nil
        // The grabber's rule is the sheet's top row, so the content is drawn a
        // row short of the detent — and at least one row tall.
        let isGrabbed = SheetGrabber.isShown(
            detents, visibility: presentationTrait(PresentationDragIndicatorProviding.self, of: modal)?
                .dragIndicatorVisibility)
        // Live, where the content lets the page through at this detent and
        // there is room for both: docked under the page, a pane beside it
        // (ModalPresentationModifier+Live.swift). A modal otherwise.
        if let backgroundInteraction,
            LiveSheet.dock(
                detents: detents, interaction: backgroundInteraction, extent: overlayHeight,
                environment: modalContext.environment, entry: existingPresentationEntry(context: context)) != nil
        {
            return renderLive(
                LiveSheet.Presented(
                    sectionID: sectionID, modalContext: modalContext, detents: detents, isGrabbed: isGrabbed,
                    gate: gate, escape: escape, dismissIsDisabled: dismissIsDisabled),
                contentContext: contentContext, context: context)
        }

        // Modal: what it presents is presented from inside a presentation
        // that holds the keyboard (`LiveSheet.dock`).
        modalContext.environment.isInModalPresentation = true

        // Register the modal focus section and activate it FIRST — so the page
        // rendered beneath registers its controls in the now-inactive page
        // section (and can't steal focus or auto-scroll), while the modal's own
        // controls auto-focus. The active section means Tab/arrows navigate only
        // within the modal. (Skipped while measuring — a measure mustn't mutate
        // focus or the status bar.) The ESC item's registration comes back,
        // to be named again once the content has drawn (below).
        let escapeItemRegistration =
            context.isMeasuring
            ? nil
            : takeKeyboard(sectionID: sectionID, gate: gate, escape: escape, context: context)

        // The drag-offset handler is a MANUAL box at this identity, and
        // nothing else hydrates it — endRenderPass would prune it every
        // frame, resetting a dragged dialog to centre on the next render.
        // Same gotcha NavigationPresentationModifier documents.
        context.stateStorage?.markActive(context.identity)

        // Render the page beneath as an inert backdrop, isolated from the live
        // focus / key / state systems (`isolatedForBackground`). The modal section
        // is already active, so a background control rendered into the real focus
        // manager would resolve to that section and steal the focus the modal's
        // own controls should auto-receive — and stay live to hotkeys. Isolation
        // keeps the real manager seeing only the modal, silences page `onKeyEvent`,
        // and (via throwaway state) preserves the page's scroll/@State. The root
        // compositor dims this buffer for the backdrop; mouse is isolated by that
        // dimmed backdrop dropping the page's hit-test regions.
        var baseBuffer = TUIkitView.renderToBuffer(
            content, context: contentContext.isolatedForBackground())

        // The page beneath is inert, and that has to be SAID rather than
        // arrived at. Until now it was a side effect of dimming: the root
        // compositor's backdrop pass rebuilds the buffer and drops its
        // hit-test regions on the way. That covers a sheet, which dims — and
        // leaves a `.fullScreenCover`, which deliberately does not, with every
        // control underneath it still clickable. A cover over a page with a
        // button drew "Loading…" and still fired the button when the blank
        // cell above it was clicked.
        //
        // Dropped here instead, for both styles, so inertness follows from
        // presenting rather than from a rendering detail that only one style
        // performs.
        //
        // The targets, not the geometry markers: the page is still laid out
        // where it is, and a reader on it still asks where that is.
        baseBuffer.removeHitTargets()
        // The RUNS are a different question, and they used to go with the
        // regions on the same line of reasoning — "the page cannot be seen".
        // That is true of a cover and false of a sheet, which shows the whole
        // dimmed page around a small dialog. Dropped there, an indeterminate
        // bar behind the dialog had no run to replay, so it advanced only when
        // something else happened to render: measured on the Example's
        // Progress page, about 2.5 pictures a second against the 30 it manages
        // with nothing presented, each one a full re-render of page, dim and
        // dialog rather than a splice. Kept, `dimmedAsBackdrop` flattens the
        // frames with the rows and the loop replays them; `composited` punches
        // out whatever the dialog covers, so nothing repaints through it.
        if style == .fullScreen {
            baseBuffer.animatedCells = []
        }

        var modalBuffer = drawSheet(
            modalContext: modalContext, detents: detents, isGrabbed: isGrabbed, gate: gate, escape: escape,
            escapeItemRegistration: escapeItemRegistration, sectionID: sectionID, context: context)
        guard !modalBuffer.isEmpty else { return baseBuffer }

        // A detented sheet rests on the bottom edge, as a sheet with detents
        // does on a phone: its height is the reader's to change, and the edge
        // it grows from stays put. Not draggable, as a cover is not: its
        // place is the edge. Its grabber is what moves it.
        if let detents, detents.height != nil {
            baseBuffer.overlays.append(
                .dockedAtBottom(content: modalBuffer, level: .modal, dimsBackground: true)
                    .presenting(modalContext.identity))
            return baseBuffer
        }

        // Make the dialog draggable by its title/border, and read back the offset
        // to place it at. The compositor clamps it fully on screen. A full-screen
        // cover is not draggable — there is nowhere for it to go, and grabbing
        // its border would only shift the screen off itself.
        let dragOffset =
            style == .fullScreen
            ? (x: 0, y: 0)
            : DialogDrag.offset(
                for: &modalBuffer, context: context, propertyIndex: StateIndex.dragHandler)

        // Float the modal to the screen root: it composites centred over the whole
        // screen and dims everything beneath — so it presents over the full screen
        // no matter where in the view tree `.modal` was attached (rather than
        // centring on the attachment's local area).
        baseBuffer.overlays.append(
            OverlayLayer(
                offsetX: dragOffset.x, offsetY: dragOffset.y, content: modalBuffer,
                level: .modal, centered: true, dimsBackground: style == .sheet
            ).presenting(modalContext.identity))
        return baseBuffer
    }

    /// The presented content, drawn — a row short of its detent under a
    /// grabber — with what is attached once it has drawn: the ESC item named
    /// for what Escape does now (`escapeItemRegistration`), and the grabber
    /// on a detented sheet's top edge.
    func drawSheet(
        modalContext: RenderContext, detents: PresentedDetents?, isGrabbed: Bool, gate: DismissalGate,
        escape: @escaping (_ isRepeat: Bool) -> Void, escapeItemRegistration: Int?, sectionID: String,
        context: RenderContext
    ) -> FrameBuffer {
        // The grabber takes a row above the content, unless the content draws
        // its own box, whose top edge it is drawn into.
        let inTopBorder = isGrabbed && SheetGrabber.isInTopBorder(of: modal)
        let modalBuffer = gate.drawingContent(context: context) {
            renderModal(
                context: context, modalContext: modalContext,
                overlayHeight: context.environment.overlayContentHeight,
                detentHeight: detents?.height.map { isGrabbed && !inTopBorder ? max(1, $0 - 1) : $0 })
        }
        // Registered before the content drew, the ESC item is named again for
        // what Escape does now it has: "cancel" where it presses the content's
        // cancel button, which may keep the sheet up — not "dismiss" — and
        // repeating only if that button does. Where the content forbade
        // interactive dismissal and drew no cancel button, the item stays —
        // Escape is still the presentation's — but is hidden and does nothing
        // (`SystemStatusBarItem.heldEscape`).
        //
        // And kept: where the content's own `.statusBarItems` registered into
        // the sheet's section, they took the place of the registration made
        // before they drew, and the item goes in among them — unless they bind
        // Escape themselves (`StatusBarState.keepPresentationItem`). Left out,
        // a page's "⎋ back" declared around the view presenting the sheet
        // answered Escape from behind it.
        if let escapeItemRegistration {
            let item =
                gate.interactiveDismissIsDisabled && !gate.escapePressesCancelButton
                ? SystemStatusBarItem.heldEscape : escapeItem(gate: gate, escape: escape)
            context.environment.statusBar?.keepPresentationItem(
                item, inSection: sectionID, registeredAs: escapeItemRegistration)
        }
        guard !modalBuffer.isEmpty, isGrabbed, let detents, detents.height != nil else { return modalBuffer }
        let interaction = presentationTrait(PresentationContentInteractionProviding.self, of: modal)
        return SheetGrabber.attach(
            to: modalBuffer, detents: detents, contentInteraction: interaction?.contentInteraction ?? .automatic,
            inTopBorder: inTopBorder, sectionID: sectionID, focusIDIndex: StateIndex.grabberFocusID, handlerIndex: StateIndex.grabber,
            context: context)
    }

    /// Makes the presented sheet the keyboard's for this frame: its focus
    /// section registered, activated as a presented one and marked modal, the
    /// input grabbed for it, the quit key stopped if its content asked, and
    /// Escape bound to `escape`, on the status bar and as a key handler — kept
    /// even where the content forbids interactive dismissal, when it does
    /// nothing (see ``View/interactiveDismissDisabled(_:)``).
    ///
    /// - Returns: The ESC item's registration, for naming it again once the
    ///   content has drawn, or `nil` when none was published.
    private func takeKeyboard(
        sectionID: String, gate: DismissalGate, escape: @escaping (_ isRepeat: Bool) -> Void,
        context: RenderContext
    ) -> Int? {
        // Section registration/activation + the status-bar item are
        // per-frame render side effects: a memoised replay of this subtree
        // would skip them, leaving a modal that no longer grabs focus.
        // Declare them so value/measure memos decline caching.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let focusManager = context.environment.focusManager
        focusManager?.registerSection(id: sectionID)
        // As a PRESENTED section: an alert or popover opened from inside
        // this modal holds the active section on top of it, and plain
        // activation took it back from that surface on every frame — see
        // `FocusManager.activatePresentedSection(id:)`.
        focusManager?.activatePresentedSection(id: sectionID)
        // Entered: shrunk to a detent that docks it live, the sheet keeps the
        // focus where it is (`renderLive`).
        if focusManager?.isBackdrop == false { presentationEntry(context: context).hasEntered = true }
        // Mark this section input-grabbing so the app's global default key
        // bindings (appearance/theme) don't fire behind the modal.
        focusManager?.markSectionModal(id: sectionID)
        // …and take the keyboard, so only handlers rendered inside the
        // modal run. Isolation already covers the page BENEATH; this
        // also covers a sibling elsewhere in the tree.
        context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
        // A claim on Escape made before this, outside the modal, names a key
        // the modal now holds (`StatusBarState.withdrawEscapeClaim`).
        context.environment.statusBar?.withdrawEscapeClaim()
        // Content that asked to stop the quit key does, for as long as it
        // is drawn.
        if presentationPreventsTermination(of: modal) {
            context.environment.statusBar?.preventQuit()
        }

        // While the modal is on screen ESC should close it. Publish an
        // ESC=dismiss item on the status bar tied to the modal section,
        // flipping the presentation binding back to false. Section items
        // are cleared each render pass, so closing the modal naturally
        // drops the override and restores the page's own items.
        //
        // `.merge` no longer merges anything OF THE PAGE'S: the backdrop
        // render publishes into a throwaway status bar now
        // (`isolatedForBackground`), because items that merely showed were
        // also still firing — `n` behind a dialog ran the page's "new".
        // What is left to merge with is whatever the app declares outside
        // the presented subtree, which is live and should show. The bar
        // therefore reads "⎋ dismiss   q quit" over a dialog, rather than
        // also advertising the page's own keys, which do nothing while it
        // is up.
        //
        // Kept where the content asked not to be dismissed by hand, too: then
        // the item is named again once the content has drawn (`drawSheet`) —
        // its cancel button's, or hidden and inert. Escape is the
        // presentation's either way. Unpublished, the key fell through to
        // whatever the app had bound it to OUTSIDE the presentation, which is
        // live: the Example's "⎋ back" took the page away from under a sheet
        // that would not close.
        let registration = context.environment.statusBar?.registerSectionItems(
            sectionID: sectionID, items: [escapeItem(gate: gate, escape: escape)], composition: .merge)
        // The same as a layer-2 key handler, the way the alert and popover
        // presenters register theirs. The item alone was unreachable from a
        // pushed NavigationStack screen: its bar claims the ESC label ("go
        // back") every frame, and the status bar skips EVERY escape item
        // while a claim stands — so ESC could not dismiss a sheet presented
        // from a pushed screen. The handler rides the modal's own grabbed
        // section, so it runs precisely while the modal holds the keyboard.
        // Where the content, drawn, forbade dismissal (`DismissalGate`) and
        // has no cancel button for Escape to press, it takes the key and
        // does nothing.
        context.environment.keyEventDispatcher!.addHandler(
            sectionID: sectionID
        ) { event in
            guard event.key == .escape else { return false }
            if gate.interactiveDismissIsDisabled, !gate.escapePressesCancelButton { return true }
            escape(event.phase == .repeat)
            return true
        }
        return registration
    }
}

/// The presenter's `StateStorage` indices, named where its state lives
/// (ModalPresentationModifier+State.swift).
private typealias StateIndex = ModalPresentationStateIndex

// MARK: - Layoutable

extension ModalPresentationModifier: Layoutable {
    /// The modal is *presented over* the page (a centred overlay on the dimmed
    /// base, which spans the page), so the layout footprint is the base
    /// `content` — both when dismissed and when presented. Forwarding also keeps
    /// the focus-section / status-bar side-effects on the render pass; a measure
    /// must not register or activate sections. The content's child identity
    /// mirrors the render path so measure-time @State binds to the same boxes.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withChildIdentity(type: Content.self, index: 0))
    }
}

// MARK: - In a Form

/// A modal written on a form row — `.modal { … }`, and the sheet or the
/// full-screen cover `.sheet(…)` and `.fullScreenCover(…)` draw through one —
/// goes around the row the form lays out, which keeps its place, as SwiftUI's
/// form keeps a row under a sheet (measured, `Tools/SwiftUIProbes/Form rows`).
extension ModalPresentationModifier: FormRowRewrapping {
    package var formRowContent: Content { content }

    package func rewrappingFormRow<V: View>(_ row: V) -> any View {
        // The style is a type of each specialisation's own, so it is spelled
        // again for the new one.
        let style: ModalPresentationModifier<V, Modal>.Style =
            switch self.style {
            case .sheet: .sheet
            case .fullScreen: .fullScreen
            }
        return ModalPresentationModifier<V, Modal>(
            content: row, isPresented: isPresented, modal: modal, style: style, itemKey: itemKey)
    }
}
