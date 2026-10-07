//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationModifier+Live.swift
//
//  A sheet whose content lets the page behind it through
//  (`presentationBackgroundInteraction(.enabled)`): docked at the bottom of the
//  content area under a page laid out in the rows above it — a pane beside the
//  page, as a `VSplitView`'s are, rather than a modal over it (decisions A19,
//  design C).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The rule a live sheet docks by

/// Whether a presented sheet is docked live, and how.
enum LiveSheet {
    /// The fewest rows a docked sheet may take, and the page above it keep:
    /// one bordered row each. Shorter, the sheet is a modal over the whole
    /// page — which on a short terminal is what the feature comes to, a
    /// documented run-time capability (decisions A18).
    static let minimumRows = 3

    /// Where among the popovers a docked sheet is composited: above a page's
    /// displaced drawing (`.offset`, `.position`, at -1), below the page's own
    /// drop-downs, menus and tooltips (at 0), which open over it as they open
    /// over anything else on the page.
    static let zIndex = -0.5

    /// The rows a sheet resting at `detents`' height docks in a content area
    /// `extent` rows tall, or `nil` when it is a modal: its content lets the
    /// page through at that height (`interaction`), and both it and the page
    /// above it have ``minimumRows``. A sheet without detents is a modal: its
    /// height is its content's, known only once the content has drawn — and
    /// the page's height has to be known before.
    ///
    /// So is one presented from inside a presentation that holds the keyboard
    /// (`environment.isInModalPresentation`): what is behind it is that
    /// presentation, not a page that could share the keyboard with it. Docked
    /// there, it reflowed the dimmed page under both, and the presentation
    /// around it took the focus back every frame and kept the input grabbed,
    /// so nothing in it could be reached from the keyboard.
    ///
    /// And so is one its presenter's `entry` keeps off the dock
    /// (``PresentationEntry/isKeptOffTheDock``).
    @MainActor
    static func dock(
        detents: PresentedDetents?, interaction: PresentationBackgroundInteraction, extent: Int,
        environment: EnvironmentValues, entry: PresentationEntry?
    ) -> Int? {
        guard !environment.isInModalPresentation, entry?.isKeptOffTheDock != true,
            let height = detents?.height, height >= minimumRows,
            extent - height >= minimumRows,
            interaction.letsThePageThrough(atHeight: height, extent: extent, environment: environment)
        else { return nil }
        return height
    }

    /// What the presenter resolved for a presented frame, handed to the live
    /// branch whole.
    struct Presented {
        let sectionID: String
        let modalContext: RenderContext
        let detents: PresentedDetents?
        let isGrabbed: Bool
        let gate: DismissalGate
        let escape: (_ isRepeat: Bool) -> Void
        let dismissIsDisabled: Bool
    }
}

// MARK: - Inside a modal presentation

/// Environment key for the content of a presentation that holds the keyboard.
private struct InModalPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is the content of a presentation that holds the
    /// keyboard — a modal sheet, a full-screen cover, a popover — so that a
    /// sheet presented from it is a modal too, whatever its background
    /// interaction (`LiveSheet.dock`).
    ///
    /// Set by those presenters for the content they present; a live sheet's
    /// content shares the keyboard with its page, and does not set it.
    var isInModalPresentation: Bool {
        get { self[InModalPresentationKey.self] }
        set { self[InModalPresentationKey.self] = newValue }
    }
}

/// Whether a presented sheet has taken the focus since it was presented — a
/// box at the presenter's identity, emptied on its closed frames and when an
/// `item:` sheet is presented for another item
/// (`ModalPresentationModifier.startOver(context:)`).
///
/// A modal sheet takes the focus on every frame it is drawn
/// (`FocusManager.activatePresentedSection(id:)`); a live one only on entry,
/// or it would take the focus back from the page on the frame after every Tab
/// out of it. Set only against the real focus manager: a presenter drawn into
/// another presentation's throwaway backdrop has not entered anything.
final class PresentationEntry {
    var hasEntered = false

    /// Whether the sheet is a modal, not docked, for as long as it stays
    /// presented: set when its presenter, drawn now, was left out of a lazy
    /// container's window on the frame laid out short by the sheet's dock
    /// (`FocusManager.presenterWentUndrawnUnderItsDock(_:)`) — a row of a lazy
    /// stack or a list that the shortened page left out. Docked again, the
    /// row would leave again, and the sheet with it.
    var isKeptOffTheDock = false

    /// The rows the live sheet was last drawn in, where that was fewer than
    /// its detent — content with no box, which keeps its own height
    /// (`sheetDetentHeight`) — or `nil` where it filled the detent.
    ///
    /// What it docks, then, rather than the detent: the rows between the
    /// page and a sheet that does not fill them would belong to nothing. Kept
    /// only while short, so a sheet that fills its detent docks the detent
    /// the reader moves it to on that very frame, never a frame late.
    var rowsShortOfDetent: Int?

    /// The identity key of the item the sheet was last presented for, for
    /// the `item:` forms — `nil` for the `isPresented:` forms, which are
    /// about nothing.
    var itemKey: String?
}

// MARK: - Presenting live

extension ModalPresentationModifier {
    /// Posts, for the root, the rows this sheet docks — every frame,
    /// presented or not (`FocusManager.notePresentationDock(id:resolver:)`).
    ///
    /// Posted while dismissed too, so that a sheet the app presents between
    /// two frames is laid out docked on the first frame it is drawn: the
    /// resolver reads the binding when the root asks, before the walk. An
    /// `item:` sheet's content is unknown while it is dismissed, so its first
    /// frame is learnt late, and settles on the next.
    ///
    /// A presented sheet whose presenter its own dock pushed out of the
    /// page's lazy window, drawn again now the page is whole, is kept off the
    /// dock from here on (``PresentationEntry/isKeptOffTheDock``): a modal,
    /// which leaves the page its height and the presenter its row. Pushed
    /// out, not merely undrawn: drawn into a backdrop, which posts nothing
    /// (below), or away for a frame with its tab, it is not held.
    ///
    /// Posted with the presenter's identity, which is what the ledger asks
    /// about (`FocusManager.settlePresentationDock(laidOutBy:in:storage:)`).
    func postDock(_ interaction: PresentationBackgroundInteraction, sectionID: String, context: RenderContext) {
        guard !context.isMeasuring, case .enabled = interaction.kind,
            let focusManager = context.environment.focusManager, !focusManager.isBackdrop
        else { return }
        let isPresented = self.isPresented
        let modal = self.modal
        let environment = context.environment
        let state =
            isPresented.wrappedValue
            ? detentState(context: context) : existingDetentState(context: context) ?? SheetDetentState()
        let entry =
            isPresented.wrappedValue ? presentationEntry(context: context) : existingPresentationEntry(context: context)
        if let entry, isPresented.wrappedValue, focusManager.presenterWentUndrawnUnderItsDock(sectionID) {
            entry.isKeptOffTheDock = true
        }
        focusManager.notePresentationDock(id: sectionID, presenter: context.identity) { contentHeight in
            guard isPresented.wrappedValue else { return nil }
            let detents = PresentedDetents(of: modal, extent: contentHeight, environment: environment, state: state)
            let rows = LiveSheet.dock(
                detents: detents, interaction: interaction, extent: contentHeight, environment: environment,
                entry: entry)
            // Content with no box docks the rows it draws, not its detent's.
            return rows.map { min($0, entry?.rowsShortOfDetent ?? $0) }
        }
    }

    /// The presented sheet, live: the page it wraps drawn as itself, and the
    /// sheet docked at the bottom of the content area — in the rows the root
    /// laid the page out short by (`FocusManager.presentationDock(in:)`), or
    /// over the page's bottom rows on a frame the dock was learnt late.
    ///
    /// None of what a modal does to hold the page still: no isolation, no
    /// input grab, no modal mark, no dimming, the page's regions and runs kept.
    /// What is the sheet's is its PANE's instead (`renderingPane`): its
    /// shortcuts, its claim on Escape, its focus sections.
    func renderLive(_ presented: LiveSheet.Presented, contentContext: RenderContext, context: RenderContext)
        -> FrameBuffer
    {
        var baseBuffer = TUIkit.renderToBuffer(content, context: contentContext)
        // The sheet's section after the page's, so it is last in the Tab ring.
        let escapeItemRegistration = context.isMeasuring ? nil : joinThePage(presented, context: context)
        // The presenter's manual boxes — see the modal branch.
        context.stateStorage?.markActive(context.identity)
        var sheet = renderingPane(presented.sectionID, context: context) {
            drawSheet(
                modalContext: presented.modalContext, detents: presented.detents, isGrabbed: presented.isGrabbed,
                gate: presented.gate, escape: presented.escape, escapeItemRegistration: escapeItemRegistration,
                sectionID: presented.sectionID, context: context)
        }
        if !context.isMeasuring, let detentHeight = presented.detents?.height {
            // Short of its detent, the sheet docks the rows it drew (`postDock`).
            presentationEntry(context: context).rowsShortOfDetent =
                sheet.height < detentHeight ? sheet.height : nil
        }
        guard !sheet.isEmpty else { return baseBuffer }
        if !context.isMeasuring { blockThePage(under: &sheet, context: context) }
        baseBuffer.overlays.append(
            .dockedAtBottom(content: sheet, level: .popover, zIndex: LiveSheet.zIndex, dimsBackground: false))
        return baseBuffer
    }

    /// Makes the live sheet a pane beside the page for this frame: its focus
    /// section registered, and activated on ENTRY only; the quit key stopped
    /// if its content asked; and — unless its content forbade interactive
    /// dismissal — Escape bound to dismissing it, on the status bar (an item
    /// of its section, which shows while the focus is there) and as a key
    /// handler that hears Escape only while the focus is in its pane: with
    /// the focus on the page, Escape is the page's (owner Q6).
    ///
    /// - Returns: The ESC item's registration, or `nil` when none was
    ///   published.
    private func joinThePage(_ presented: LiveSheet.Presented, context: RenderContext) -> Int? {
        let sectionID = presented.sectionID
        // Per-frame registrations, as the modal branch's (`takeKeyboard`).
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let focusManager = context.environment.focusManager
        focusManager?.registerSection(id: sectionID)
        // Presenting moves the focus into the sheet, as every sheet does; a
        // reader who has since moved it to the page keeps it there.
        let entry = presentationEntry(context: context)
        if !entry.hasEntered, let focusManager, !focusManager.isBackdrop {
            focusManager.activatePresentedSection(id: sectionID)
            entry.hasEntered = true
        }
        if presentationPreventsTermination(of: modal) {
            context.environment.statusBar?.preventQuit()
        }
        guard !presented.dismissIsDisabled else { return nil }
        let escape = presented.escape
        let registration = context.environment.statusBar?.registerSectionItems(
            sectionID: sectionID, items: [escapeItem(gate: presented.gate, escape: escape)], composition: .merge)
        context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { event in
            guard event.key == .escape, focusManager?.activePaneID == sectionID else { return false }
            escape(event.phase == .repeat)
            return true
        }
        return registration
    }

    /// A region under the whole sheet that takes every press, release, drag
    /// and wheel tick its own controls leave — inserted first, so each of
    /// them wins over it.
    ///
    /// No page row lies under a docked sheet, except on the frame its dock is
    /// learnt late, when the sheet is drawn over the page's bottom rows: a
    /// click on a blank cell of the sheet then reached the page control under
    /// it. Overlay regions are appended after the page's rather than punched
    /// out of them, so a sheet has to say that its cells are its own.
    private func blockThePage(under sheet: inout FrameBuffer, context: RenderContext) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        let handlerID = dispatcher.register(in: context) { event in
            switch event.phase {
            case .entered, .exited, .moved: false
            default: true
            }
        }
        sheet.hitTestRegions.insert(
            HitTestRegion(offsetX: 0, offsetY: 0, width: sheet.width, height: sheet.height, handlerID: handlerID),
            at: 0)
    }
}
